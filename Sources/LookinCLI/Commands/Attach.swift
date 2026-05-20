import ArgumentParser
import Foundation
import LookinCore
import LookinTransport

struct Attach: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attach",
        abstract: "Discover and connect to a LookinServer; save session to ~/.lookin-cli/session.json.",
    )

    @OptionGroup var output: OutputOptions

    @Flag(name: .long, help: "Target real device USB port range instead of simulator.")
    var device: Bool = false

    func run() throws {
        let target: PortScanner.Target = device ? .device : .simulator
        let result = try runAsync { try await Attach.probe(target: target) }

        guard let port = result.port, let serverVersion = result.serverVersion else {
            var msg = "No LookinServer found"
            if device {
                msg += ". Did you run `iproxy 47175 47175`?"
            } else {
                msg += ". Is a simulator app with LookinServer running?"
            }
            fputs("error: \(msg)\n", stderr)
            throw ExitCode.failure
        }

        let session = Session(
            host: "127.0.0.1",
            port: port,
            target: device ? .device : .simulator,
            serverVersion: serverVersion,
            capturedAt: Date(),
            simulatorUDID: device ? nil : Attach.bootedSimulatorUDID(),
        )
        try session.save()

        struct SessionReport: Encodable {
            let host: String
            let port: UInt16
            let target: String
            let serverVersion: Int
            let capturedAt: String
            let sessionPath: String
        }

        let isoFormatter = ISO8601DateFormatter()
        let report = SessionReport(
            host: session.host,
            port: session.port,
            target: session.target.rawValue,
            serverVersion: session.serverVersion,
            capturedAt: isoFormatter.string(from: session.capturedAt),
            sessionPath: Session.defaultPath.path,
        )
        try emit(report, options: output)
        exitSuccess()
    }

    /// Returns the UDID of the first booted simulator, or nil if none / xcrun fails.
    /// For the demo we take the first booted device; if multiple simulators are
    /// booted this may not be the one hosting the app — documented in README.
    static func bootedSimulatorUDID() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["simctl", "list", "devices", "booted", "-j"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: Any] else { return nil }
        for (_, runtimeDevices) in devices {
            guard let list = runtimeDevices as? [[String: Any]] else { continue }
            for device in list {
                if (device["state"] as? String) == "Booted",
                   let udid = device["udid"] as? String
                {
                    return udid
                }
            }
        }
        return nil
    }

    private static func probe(target: PortScanner.Target) async throws -> (port: UInt16?, serverVersion: Int?) {
        if let result = await resolveServer(target: target) {
            return (result.port, result.serverVersion)
        }
        return (nil, nil)
    }
}
