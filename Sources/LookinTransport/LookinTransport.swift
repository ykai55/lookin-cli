import Foundation
import LookinCore

/// Abstracts how the CLI talks to a running LookinServer.
/// Today: `PeertalkTransport` (route B). Tomorrow: `HTTPTransport` (route A).
public protocol LookinTransport: AnyObject {
    /// Sends a request, awaits the matching tagged response.
    func send(
        type: UInt32,
        payload: LookinConnectionAttachment,
    ) async throws -> LookinConnectionAttachment

    /// Sends a request whose response arrives as multiple frames (streaming).
    /// Collects frames until `currentDataCount == dataTotalCount` (or timeout),
    /// then returns all collected attachments in order.
    func sendStreaming(
        type: UInt32,
        payload: LookinConnectionAttachment,
        expectedTotal: Int,
    ) async throws -> [LookinConnectionAttachment]

    /// Tear down the underlying connection.
    func close() async
}

public enum LookinTransportError: Error, CustomStringConvertible {
    case notConnected
    case decodeFailed(String)
    case serverError(code: Int, message: String)
    case versionMismatch(client: Int, server: Int)
    case io(String)

    public var description: String {
        switch self {
        case .notConnected: "Not connected to LookinServer."
        case let .decodeFailed(msg): "Decode failed: \(msg)"
        case let .serverError(code, msg): "Server error \(code): \(msg)"
        case let .versionMismatch(c, s): "Version mismatch (client=\(c), server=\(s))."
        case let .io(msg): "I/O error: \(msg)"
        }
    }
}
