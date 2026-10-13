import ArgumentParser
import Foundation
import LookinCore
import LookinTransport

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Probe simulator/device for a reachable LookinServer; print per-port diagnostics.",
    )

    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Probe the device USB port range instead of the simulator range.")
    var device: Bool = false

    @Option(name: .long, help: "USB device UDID (required when multiple devices are connected).")
    var udid: String?

    mutating func validate() throws {
        if udid != nil, !device { throw ValidationError("--udid requires --device.") }
    }

    // MARK: - Report shape

    /// Per-port diagnostic detail.
    struct PortReport: Encodable {
        let port: UInt16
        /// "open" if a TCP connection was accepted, otherwise "closed".
        let tcp: String
        /// Socket state from `lsof`: "listen" | "established" | "none".
        let socket: String
        /// LookinServer ping result: "ok" | "failed" | "skipped".
        let ping: String
        let serverVersion: Int?
    }

    struct Report: Encodable {
        let target: String
        let host: String
        let reachable: Bool
        /// "ok" | "no_listener" | "port_in_use_by_other_client" | "scan_timed_out"
        let reason: String
        let port: UInt16?
        let serverVersion: Int?
        let probeMs: Int
        let ports: [PortReport]
        let hint: String?
    }

    func run() throws {
        if device {
            let report = try runAsync { await Doctor.diagnoseUSB(udid: udid) }
            try emit(report, options: output)
            exitSuccess()
        }
        let target: PortScanner.Target = device ? .device : .simulator
        let start = Date()
        let report = try runAsync {
            try await Doctor.diagnose(target: target, device: device, start: start)
        }
        try emit(report, options: output)
        exitSuccess()
    }

    // MARK: - Diagnosis

    struct USBReport: Encodable {
        let target = "device"
        let transport = "usbmuxd"
        let devices: [USBMux.Device]
        let deviceUDID: String?
        let reachable: Bool
        let port: UInt16?
        let serverVersion: Int?
        let hint: String?
    }

    static func diagnoseUSB(udid: String?) async -> USBReport {
        var devices: [USBMux.Device] = []
        do {
            devices = try await withRequestTimeout(seconds: 5) { try await USBMux.devices() }
            let device = try USBMux.select(devices, udid: udid)
            let result = await resolveServer(target: .device, deviceID: device.id, timeoutSeconds: 1, coldStartRetries: 0)
            return USBReport(devices: devices, deviceUDID: device.udid, reachable: result != nil,
                             port: result?.port, serverVersion: result?.serverVersion,
                             hint: result == nil ? "USB device found, but LookinServer did not respond. Unlock the phone, keep the app in the foreground, and disconnect other Lookin clients." : nil)
        } catch {
            return USBReport(devices: devices, deviceUDID: udid, reachable: false,
                             port: nil, serverVersion: nil, hint: error.localizedDescription)
        }
    }

    /// Overall budget for the whole scan. With fast-failing connections this is
    /// never hit in practice; exceeding it yields a distinct `scan_timed_out`.
    private static let scanBudgetSeconds: Double = 12
    private static let tcpProbeTimeout: TimeInterval = 0.4
    private static let pingTimeoutSeconds: Double = 3

    static func diagnose(
        target: PortScanner.Target, device: Bool, start: Date,
    ) async throws -> Report {
        let range = target.range
        let socketStates = SocketInspector.states(in: range)

        let probes: [PortReport]? = try? await withRequestTimeout(seconds: scanBudgetSeconds) {
            await probePorts(range: range, socketStates: socketStates)
        }
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)

        guard let probes else {
            return Report(
                target: device ? "device" : "simulator", host: "127.0.0.1",
                reachable: false, reason: "scan_timed_out", port: nil,
                serverVersion: nil, probeMs: elapsed, ports: [],
                hint: "Port scan timed out. The simulator/device may be unresponsive — retry.",
            )
        }
        return classify(probes: probes, device: device, elapsed: elapsed)
    }

    /// Probes every port in `range` concurrently.
    private static func probePorts(
        range: ClosedRange<UInt16>, socketStates: [UInt16: SocketState],
    ) async -> [PortReport] {
        await withTaskGroup(of: PortReport.self) { group in
            for port in range {
                group.addTask { await probePort(port, socketState: socketStates[port]) }
            }
            var results: [PortReport] = []
            for await r in group {
                results.append(r)
            }
            return results.sorted { $0.port < $1.port }
        }
    }

    private static func probePort(_ port: UInt16, socketState: SocketState?) async -> PortReport {
        let socket = switch socketState {
        case .listen: "listen"
        case .established: "established"
        case nil: "none"
        }

        let tcpOpen = await PortScanner.isReachable(
            host: "127.0.0.1", port: port, timeout: tcpProbeTimeout,
        )
        guard tcpOpen else {
            return PortReport(port: port, tcp: "closed", socket: socket,
                              ping: "skipped", serverVersion: nil)
        }
        if let version = await ping(port: port) {
            return PortReport(port: port, tcp: "open", socket: socket,
                              ping: "ok", serverVersion: version)
        }
        return PortReport(port: port, tcp: "open", socket: socket,
                          ping: "failed", serverVersion: nil)
    }

    /// Pings a port once with a short timeout; returns the server version on success.
    private static func ping(port: UInt16) async -> Int? {
        let transport = PeertalkTransport(host: "127.0.0.1", port: port)
        defer { Task { await transport.close() } }
        let payload = LookinConnectionAttachment()
        payload.dataType = LookinCodingValueType(rawValue: 4)! // LookinCodingValueTypeLongLong
        payload.data = NSNumber(value: LOOKIN_CLIENT_VERSION)
        do {
            let response = try await withRequestTimeout(seconds: pingTimeoutSeconds) {
                try await transport.send(type: UInt32(LookinRequestTypePing), payload: payload)
            }
            if let resp = response as? LookinConnectionResponseAttachment {
                return Int(resp.lookinServerVersion)
            }
            if let n = response.data as? NSNumber { return n.intValue }
            return nil
        } catch {
            return nil
        }
    }

    private static func classify(
        probes: [PortReport], device: Bool, elapsed: Int,
    ) -> Report {
        func report(reachable: Bool, reason: String, port: UInt16?, version: Int?, hint: String?) -> Report {
            Report(target: device ? "device" : "simulator", host: "127.0.0.1",
                   reachable: reachable, reason: reason, port: port,
                   serverVersion: version, probeMs: elapsed, ports: probes, hint: hint)
        }

        if let ok = probes.first(where: { $0.ping == "ok" }) {
            return report(reachable: true, reason: "ok", port: ok.port,
                          version: ok.serverVersion, hint: nil)
        }

        // A port accepted TCP or shows an established socket, but no LookinServer
        // answered — almost always the single-client connection held elsewhere.
        if let occupied = probes.first(where: { $0.ping == "failed" || $0.socket == "established" }) {
            return report(
                reachable: false, reason: "port_in_use_by_other_client",
                port: occupied.port, version: nil,
                hint: "Port \(occupied.port) is occupied but no LookinServer answered. "
                    + "LookinServer is single-client — close the Lookin macOS app "
                    + "(or another lookin-cli) holding the connection, then retry.",
            )
        }

        // Nothing listening anywhere in the range.
        let hint = device
            ? "No LookinServer port is listening on the TCP forward. Run `lookin attach --device` to connect directly over USB."
            : "No LookinServer port is listening. Check: (1) LookinServer is linked "
            + "and the app runs in Debug; (2) the app is foreground-active — a system "
            + "modal (e.g. the ATT prompt) delays LookinServer's listener until the "
            + "app becomes active."
        return report(reachable: false, reason: "no_listener",
                      port: nil, version: nil, hint: hint)
    }
}

// MARK: - Async bridge

func runAsync<T>(_ body: @escaping () async throws -> T) throws -> T {
    let group = DispatchGroup()
    var result: Result<T, Error>!
    group.enter()
    Task {
        do { result = try await .success(body()) }
        catch { result = .failure(error) }
        group.leave()
    }
    group.wait()
    return try result.get()
}
