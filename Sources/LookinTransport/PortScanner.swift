import Foundation
import Network

public enum PortScanner {
    public enum Target {
        case simulator // 47164...47169
        case device // 47175...47179, but normally already forwarded via iproxy

        public var range: ClosedRange<UInt16> {
            switch self {
            case .simulator: 47164 ... 47169
            case .device: 47175 ... 47179
            }
        }
    }

    public static func firstResponsivePort(
        host: String = "127.0.0.1",
        target: Target,
        timeout: TimeInterval = 0.25,
    ) async -> UInt16? {
        for port in target.range {
            if await isReachable(host: host, port: port, timeout: timeout) { return port }
        }
        return nil
    }

    public static func isReachable(host: String, port: UInt16, timeout: TimeInterval) async -> Bool {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!,
        )
        let connection = NWConnection(to: endpoint, using: .tcp)
        return await withCheckedContinuation { cont in
            let queue = DispatchQueue(label: "lookin.portscan.\(port)")
            var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    connection.cancel()
                    cont.resume(returning: true)
                case .failed, .cancelled:
                    resumed = true
                    cont.resume(returning: false)
                case .waiting:
                    // Connection refused / no listener: NWConnection would retry
                    // forever. Treat as unreachable and stop waiting immediately.
                    resumed = true
                    connection.cancel()
                    cont.resume(returning: false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                guard !resumed else { return }
                resumed = true
                connection.cancel()
                cont.resume(returning: false)
            }
        }
    }
}
