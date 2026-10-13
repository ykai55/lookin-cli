import ArgumentParser
import Foundation
import LookinCore
import LookinTransport

struct Tree: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tree",
        abstract: "Print the running view hierarchy as JSON.",
    )

    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "Max depth of the tree (default: unlimited = 999).")
    var depth: Int = 999

    func run() throws {
        let session = try loadSession()
        let hierarchy = try runAsync { try await Tree.fetchHierarchy(session: session) }
        let roots = hierarchy.displayItems ?? []

        struct TreeEnvelope: Encodable {
            let serverVersion: Int
            let windowCount: Int
            let roots: [PublicNode]
        }

        let envelope = TreeEnvelope(
            serverVersion: Int(hierarchy.serverVersion),
            windowCount: roots.count,
            roots: roots.map { PublicNode(from: $0, depth: depth) },
        )
        try emit(envelope, options: output)
        exitSuccess()
    }

    static func fetchHierarchy(session: Session) async throws -> LookinHierarchyInfo {
        let transport = try await session.transport()
        defer { Task { await transport.close() } }

        // Send ping first to establish the session on this connection.
        // The server expects a ping before serving other requests on the same connection.
        let ping = LookinConnectionAttachment()
        ping.dataType = LookinCodingValueType(rawValue: 4)! // LookinCodingValueTypeLongLong
        ping.data = NSNumber(value: LOOKIN_CLIENT_VERSION)
        _ = try? await withRequestTimeout(seconds: 8) {
            try await transport.send(type: UInt32(LookinRequestTypePing), payload: ping)
        }

        let req = LookinConnectionAttachment()
        // Payload: NSNumber with client version (LookinCodingValueTypeLongLong = rawValue 4)
        req.dataType = LookinCodingValueType(rawValue: 4)!
        req.data = NSNumber(value: LOOKIN_CLIENT_VERSION)

        let response = try await withRequestTimeout(seconds: 30) {
            try await transport.send(
                type: UInt32(LookinRequestTypeHierarchy),
                payload: req,
            )
        }

        if let resp = response as? LookinConnectionResponseAttachment, resp.error != nil {
            throw NSError(domain: "LookinCLI", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: resp.error!.localizedDescription])
        }

        guard let info = response.data as? LookinHierarchyInfo else {
            throw NSError(domain: "LookinCLI", code: -2,
                          userInfo: [NSLocalizedDescriptionKey:
                              "Response data was not LookinHierarchyInfo; got \(type(of: response.data))"])
        }
        return info
    }
}
