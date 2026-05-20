import ArgumentParser
import Foundation
import LookinCore
import LookinTransport

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Probe simulator/device for a reachable LookinServer; print diagnostics.",
    )

    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Probe the device USB port range instead of the simulator range.")
    var device: Bool = false

    func run() throws {
        let target: PortScanner.Target = device ? .device : .simulator
        let start = Date()
        let result = try runAsync { try await Doctor.probe(target: target) }
        let elapsed = Date().timeIntervalSince(start) * 1000

        struct Report: Encodable {
            let target: String
            let host: String
            let port: UInt16?
            let reachable: Bool
            let serverVersion: Int?
            let probeMs: Int
            let hint: String?
        }
        let report = Report(
            target: device ? "device" : "simulator",
            host: "127.0.0.1",
            port: result.port,
            reachable: result.port != nil,
            serverVersion: result.serverVersion,
            probeMs: Int(elapsed),
            hint: result.port == nil
                ? (device
                    ? "No port reachable. Did you run `iproxy 47175 47175`?"
                    : "No port reachable. Is the simulator app running in Debug?")
                : nil,
        )
        try emit(report, options: output)
        exitSuccess()
    }

    private static func probe(target: PortScanner.Target) async throws -> (port: UInt16?, serverVersion: Int?) {
        if let result = await resolveServer(target: target) {
            return (result.port, result.serverVersion)
        }
        return (nil, nil)
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
