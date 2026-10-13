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

    @Flag(name: .long, help: "Connect directly to a USB device via usbmuxd.")
    var device: Bool = false

    @Option(name: .long, help: "USB device UDID (required when multiple devices are connected).")
    var udid: String?

    mutating func validate() throws {
        if udid != nil, !device { throw ValidationError("--udid requires --device.") }
    }

    func run() throws {
        let target: PortScanner.Target = device ? .device : .simulator
        let usbDevice: USBMux.Device? = try runAsync {
            guard device else { return nil }
            let devices = try await withRequestTimeout(seconds: 5) { try await USBMux.devices() }
            return try USBMux.select(devices, udid: udid)
        }
        let result = try runAsync {
            await resolveServer(target: target, deviceID: usbDevice?.id, timeoutSeconds: device ? 3 : 15)
        }

        guard let result else {
            var msg = "No LookinServer found"
            if device {
                msg += ". Keep the iPhone unlocked and the app with LookinServer in the foreground. Disconnect other Lookin clients."
            } else {
                msg += ". Is a simulator app with LookinServer running?"
            }
            fputs("error: \(msg)\n", stderr)
            throw ExitCode.failure
        }

        let session = Session(
            host: device ? "usbmuxd" : "127.0.0.1",
            port: result.port,
            target: device ? .device : .simulator,
            serverVersion: result.serverVersion,
            capturedAt: Date(),
            simulatorUDID: device ? nil : Attach.bootedSimulatorUDID(),
            deviceUDID: usbDevice?.udid,
        )
        try session.save()

        struct SessionReport: Encodable {
            let host: String
            let port: UInt16
            let target: String
            let serverVersion: Int
            let capturedAt: String
            let sessionPath: String
            let deviceUDID: String?
        }

        let isoFormatter = ISO8601DateFormatter()
        let report = SessionReport(
            host: session.host,
            port: session.port,
            target: session.target.rawValue,
            serverVersion: session.serverVersion,
            capturedAt: isoFormatter.string(from: session.capturedAt),
            sessionPath: Session.defaultPath.path,
            deviceUDID: session.deviceUDID,
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
}
