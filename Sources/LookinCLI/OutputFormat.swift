import ArgumentParser
import Foundation
import LookinCore
import LookinTransport

// MARK: - Session loader

func loadSession() throws -> Session {
    guard let session = try Session.load() else {
        fputs("error: no session found. Run `lookin attach` first.\n", stderr)
        throw ExitCode.failure
    }
    return session
}

public struct OutputOptions: ParsableArguments {
    @Flag(name: .long, help: "Pretty-print JSON output.")
    public var pretty: Bool = false

    public init() {}

    public func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return enc
    }
}

public func emit(_ value: some Encodable, options: OutputOptions) throws {
    let data = try options.encoder().encode(value)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A])) // trailing newline
}

/// Force-exit the process after emitting output.
/// NWConnection's background DispatchQueues can keep the process alive indefinitely,
/// so we must call Foundation.exit explicitly after all output is flushed.
func exitSuccess() -> Never {
    Foundation.exit(0)
}

/// Throws `LookinCLIError.timeout` if the async body doesn't complete within `seconds`.
enum LookinCLIError: Error {
    case timeout
    case notFound(String)
}

func withRequestTimeout<T>(seconds: Double = 10, operation: @escaping () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw LookinCLIError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

/// Resolve a live LookinServer in the port range by *actually* connecting and
/// pinging on each port. We avoid a separate "is reachable" probe because that
/// probe is a TCP connect-and-close, and LookinServer treats every closed
/// channel as a reset that triggers a re-listen cycle. During that cycle the
/// server briefly cannot accept connections, which makes a subsequent real
/// connect race with the relisten. By skipping the probe and using the ping
/// itself as the liveness check, each port costs at most one reset cycle, and
/// retries don't pile up.
///
/// Spec §4.3: single retry on cold start.
func resolveServer(
    target: PortScanner.Target,
    deviceID: Int? = nil,
    timeoutSeconds: Double = 15,
    coldStartRetries: Int = 1,
    retryDelaySeconds: Double = 0.8,
) async -> (port: UInt16, serverVersion: Int)? {
    for port in target.range {
        if let result = await tryPing(
            port: port,
            deviceID: deviceID,
            timeoutSeconds: timeoutSeconds,
            attemptsRemaining: coldStartRetries,
            retryDelaySeconds: retryDelaySeconds,
        ) {
            return result
        }
    }
    return nil
}

private func tryPing(
    port: UInt16,
    deviceID: Int?,
    timeoutSeconds: Double,
    attemptsRemaining: Int,
    retryDelaySeconds: Double,
) async -> (port: UInt16, serverVersion: Int)? {
    let transport = deviceID.map { PeertalkTransport(deviceID: $0, port: port) }
        ?? PeertalkTransport(host: "127.0.0.1", port: port)
    let payload = LookinConnectionAttachment()
    payload.dataType = LookinCodingValueType(rawValue: 4)! // LookinCodingValueTypeLongLong
    payload.data = NSNumber(value: LOOKIN_CLIENT_VERSION)
    do {
        let response = try await withRequestTimeout(seconds: timeoutSeconds) {
            try await transport.send(type: UInt32(LookinRequestTypePing), payload: payload)
        }
        await transport.close()
        let serverVersion: Int
        if let resp = response as? LookinConnectionResponseAttachment {
            if resp.error != nil { return nil }
            serverVersion = Int(resp.lookinServerVersion)
        } else if let n = response.data as? NSNumber {
            serverVersion = n.intValue
        } else {
            return nil
        }
        return (port, serverVersion)
    } catch {
        await transport.close()
        if attemptsRemaining > 0, !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(retryDelaySeconds * 1_000_000_000))
            return await tryPing(
                port: port,
                deviceID: deviceID,
                timeoutSeconds: timeoutSeconds,
                attemptsRemaining: attemptsRemaining - 1,
                retryDelaySeconds: retryDelaySeconds,
            )
        }
        return nil
    }
}
