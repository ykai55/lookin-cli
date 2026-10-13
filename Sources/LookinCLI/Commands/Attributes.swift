import ArgumentParser
import Foundation
import LookinCore
import LookinTransport

struct Attributes: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attributes",
        abstract: "Print all attribute groups for a single view, identified by --oid.",
    )

    @OptionGroup var output: OutputOptions

    @Option(name: .long, help: "View OID (from `lookin tree` output).")
    var oid: UInt?

    @Option(name: .long, help: "Accessibility identifier (from `lookin tree` output).")
    var axId: String?

    func run() throws {
        guard oid != nil || axId != nil else {
            fputs("error: provide --oid or --ax-id\n", stderr)
            throw ExitCode.failure
        }

        let session = try loadSession()

        // Fetch hierarchy + details on the SAME connection.
        // Protocol: ping -> hierarchy (202) -> details (210) all on same TCP connection.
        let result = try runAsync {
            try await Attributes.fetchAttributesOnSingleConnection(
                session: session,
                oid: oid,
                axId: axId,
            )
        }

        guard let result else {
            fputs("error: no view found with the given identifier\n", stderr)
            throw ExitCode.failure
        }

        struct AttributesEnvelope: Encodable {
            let oid: UInt
            let `class`: String
            let attributeCount: Int
            let attributes: [PublicAttribute]
        }

        let envelope = AttributesEnvelope(
            oid: result.oid,
            class: result.className,
            attributeCount: result.attrs.count,
            attributes: result.attrs,
        )
        try emit(envelope, options: output)
        exitSuccess()
    }

    struct AttributeResult {
        let oid: UInt
        let className: String
        let attrs: [PublicAttribute]
    }

    /// Fetches attributes by:
    /// 1. Ping on a fresh connection
    /// 2. Fetch hierarchy (202) on the same connection
    /// 3. Find the target OID in the hierarchy
    /// 4. Send AllAttrGroups request (210) on the same connection using the CALayer OID
    static func fetchAttributesOnSingleConnection(
        session: Session,
        oid: UInt?,
        axId: String?,
    ) async throws -> AttributeResult? {
        let transport = try await session.transport()
        defer { Task { await transport.close() } }

        // Step 1: Ping
        let ping = LookinConnectionAttachment()
        ping.dataType = LookinCodingValueType(rawValue: 4)!
        ping.data = NSNumber(value: LOOKIN_CLIENT_VERSION)
        _ = try? await withRequestTimeout(seconds: 8) {
            try await transport.send(type: UInt32(LookinRequestTypePing), payload: ping)
        }

        // Step 2: Fetch hierarchy
        let hierarchyReq = LookinConnectionAttachment()
        hierarchyReq.dataType = LookinCodingValueType(rawValue: 4)!
        hierarchyReq.data = NSNumber(value: LOOKIN_CLIENT_VERSION)

        let hierResponse = try await withRequestTimeout(seconds: 30) {
            try await transport.send(type: UInt32(LookinRequestTypeHierarchy), payload: hierarchyReq)
        }
        guard let info = hierResponse.data as? LookinHierarchyInfo else { return nil }

        // Step 3: Find target item
        let roots = info.displayItems ?? []
        let all = flatItems(from: roots)
        let item: LookinDisplayItem? = if let oid {
            all.first { ($0.viewObject?.oid ?? $0.layerObject?.oid) == oid }
        } else if let axId {
            all.first { ($0.viewObject?.specialTrace ?? $0.layerObject?.specialTrace) == axId }
        } else {
            nil
        }
        guard let item else { return nil }

        let obj = item.viewObject ?? item.layerObject
        let targetOid = obj?.oid ?? 0
        let className = obj?.rawClassName() ?? "(unknown)"

        // Quick check: does hierarchy already have attributes?
        var attrs = publicAttributes(from: item)
        if !attrs.isEmpty {
            return AttributeResult(oid: targetOid, className: className, attrs: attrs)
        }

        // Request 210 (AllAttrGroups): fetch all attribute groups for a single LAYER OID.
        // The server handler does: CALayer *layer = [NSObject lks_objectWithOid:oid];
        // so we MUST use layerObject.oid (not viewObject.oid).
        let layerOid = item.layerObject?.oid ?? targetOid

        let detailReq = LookinConnectionAttachment()
        detailReq.dataType = LookinCodingValueType(rawValue: 4)! // LongLong - NSNumber
        detailReq.data = NSNumber(value: layerOid)

        do {
            let detailResponse = try await withRequestTimeout(seconds: 20) {
                try await transport.send(type: UInt32(LookinRequestTypeAllAttrGroups), payload: detailReq)
            }

            if let resp = detailResponse as? LookinConnectionResponseAttachment, resp.error != nil {
                fputs("warning: attrGroups (210) error: \(resp.error!.localizedDescription)\n", stderr)
            } else if let groups = detailResponse.data as? [LookinAttributesGroup] {
                let synthetic = LookinDisplayItem()
                synthetic.attributesGroupList = groups
                attrs = publicAttributes(from: synthetic)
            } else if let group = detailResponse.data as? LookinAttributesGroup {
                let synthetic = LookinDisplayItem()
                synthetic.attributesGroupList = [group]
                attrs = publicAttributes(from: synthetic)
            }
        } catch {
            fputs("warning: fetchDetail (210) failed: \(error)\n", stderr)
        }

        return AttributeResult(oid: targetOid, className: className, attrs: attrs)
    }
}
