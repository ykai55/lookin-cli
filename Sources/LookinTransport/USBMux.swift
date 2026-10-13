import Foundation
import Network

/// Talks to macOS's usbmuxd daemon. A successful Connect turns the same socket
/// into a byte stream to the device; no local TCP listener or helper is needed.
public enum USBMux {
    public struct Device: Equatable, Encodable {
        public let id: Int
        public let udid: String
    }

    public enum Failure: LocalizedError {
        case protocolError(String)
        case rejected(Int)
        case noDevice(String?)
        case multipleDevices([String])

        public var errorDescription: String? {
            switch self {
            case let .protocolError(message): "usbmuxd: \(message)"
            case let .rejected(code): "usbmuxd rejected the connection (code \(code)). Keep the device unlocked and the app with LookinServer in the foreground."
            case let .noDevice(udid): "No USB device\(udid.map { " matching \($0)" } ?? "") found. Connect and trust the iPhone."
            case let .multipleDevices(udids): "Multiple USB devices connected. Select one with --udid: \(udids.joined(separator: ", "))"
            }
        }
    }

    static func connection() -> NWConnection {
        NWConnection(to: .unix(path: "/var/run/usbmuxd"), using: .tcp)
    }

    // State updates and cancellation can both finish a connection attempt.
    private final class ConnectionStart: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, Error>?

        init(_ continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        func finish(_ result: Result<Void, Error>) {
            let pending = lock.withLock {
                defer { continuation = nil }
                return continuation
            }
            pending?.resume(with: result)
        }
    }

    public static func devices() async throws -> [Device] {
        let connection = connection()
        defer { connection.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let queue = DispatchQueue(label: "lookin.usbmux.discovery")
                let start = ConnectionStart(continuation)
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        start.finish(.success(()))
                    case let .failed(error), let .waiting(error):
                        start.finish(.failure(error))
                    case .cancelled:
                        start.finish(.failure(CancellationError()))
                    default: break
                    }
                }
                connection.start(queue: queue)
            }
            let response = try await request(["MessageType": "ListDevices"], on: connection)
            return try parseDevices(response)
        } onCancel: {
            connection.cancel()
        }
    }

    public static func select(_ devices: [Device], udid: String?) throws -> Device {
        if let udid {
            guard let device = devices.first(where: { $0.udid == udid }) else {
                throw Failure.noDevice(udid)
            }
            return device
        }
        guard !devices.isEmpty else { throw Failure.noDevice(nil) }
        guard devices.count == 1 else { throw Failure.multipleDevices(devices.map(\.udid)) }
        return devices[0]
    }

    static func parseDevices(_ response: [String: Any]) throws -> [Device] {
        guard let list = response["DeviceList"] as? [[String: Any]] else {
            throw Failure.protocolError("missing DeviceList")
        }
        return list.compactMap { entry in
            guard let properties = entry["Properties"] as? [String: Any],
                  properties["ConnectionType"] as? String == "USB",
                  let id = entry["DeviceID"] as? Int,
                  let udid = properties["SerialNumber"] as? String else { return nil }
            return Device(id: id, udid: udid)
        }
    }

    static func connect(_ connection: NWConnection, deviceID: Int, port: UInt16) async throws {
        let response = try await request(connectMessage(deviceID: deviceID, port: port), on: connection)
        guard response["MessageType"] as? String == "Result",
              let code = response["Number"] as? Int else {
            throw Failure.protocolError("missing Connect result")
        }
        guard code == 0 else { throw Failure.rejected(code) }
    }

    static func connectMessage(deviceID: Int, port: UInt16) -> [String: Any] {
        ["MessageType": "Connect", "DeviceID": deviceID, "PortNumber": Int(port.bigEndian)]
    }

    static func encode(_ message: [String: Any]) throws -> Data {
        var message = message
        message["ClientVersionString"] = "lookin-cli"
        message["ProgName"] = "lookin-cli"
        message["kLibUSBMuxVersion"] = 3
        let body = try PropertyListSerialization.data(fromPropertyList: message, format: .xml, options: 0)
        var data = Data()
        // usbmuxd v1: total length, protocol version, plist message type, request tag.
        for value in [UInt32(body.count + 16), 1, 8, 1] {
            var value = value.littleEndian
            withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        }
        data.append(body)
        return data
    }

    static func bodyLength(_ header: Data) throws -> Int {
        guard header.count == 16 else { throw Failure.protocolError("truncated header") }
        let fields = stride(from: 0, to: 16, by: 4).map { offset in
            header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
        }
        guard fields[0] >= 16, fields[0] <= 1_048_576,
              fields[1] == 1, fields[2] == 8, fields[3] == 1 else {
            throw Failure.protocolError("invalid response header")
        }
        return Int(fields[0]) - 16
    }

    private static func request(_ message: [String: Any], on connection: NWConnection) async throws -> [String: Any] {
        let data = try encode(message)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
        let header = try await receive(16, on: connection)
        let body = try await receive(bodyLength(header), on: connection)
        guard let response = try PropertyListSerialization.propertyList(from: body, format: nil) as? [String: Any] else {
            throw Failure.protocolError("invalid response plist")
        }
        return response
    }

    private static func receive(_ count: Int, on connection: NWConnection) async throws -> Data {
        var result = Data()
        while result.count < count {
            let remaining = count - result.count
            let chunk: Data = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: remaining) { data, _, _, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, !data.isEmpty { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: Failure.protocolError("unexpected EOF")) }
                }
            }
            result.append(chunk)
        }
        return result
    }
}
