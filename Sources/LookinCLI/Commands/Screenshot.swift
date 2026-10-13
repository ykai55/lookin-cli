import ArgumentParser
import Foundation
import LookinCore
import LookinTransport

struct Screenshot: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "screenshot",
        abstract: "Save a PNG of a UIImageView's image (request 208) or any layer's group snapshot (request 203).",
    )

    @Option(name: .long, help: "View OID (from `lookin tree` output).")
    var view: UInt

    @Option(name: [.customShort("o"), .long], help: "Output path (default: /tmp/lookin-screenshot.png).")
    var out: String = "/tmp/lookin-screenshot.png"

    func run() throws {
        let session = try loadSession()

        let pngData = try runAsync {
            try await Screenshot.fetchScreenshot(session: session, viewOid: view)
        }

        guard let pngData else {
            fputs("error: no screenshot data returned for oid \(view)\n", stderr)
            throw ExitCode.failure
        }

        let url = URL(fileURLWithPath: out)
        try pngData.write(to: url, options: .atomic)
        fputs("saved \(pngData.count) bytes to \(url.path)\n", stderr)
        exitSuccess()
    }

    static func fetchScreenshot(session: Session, viewOid: UInt) async throws -> Data? {
        let transport = try await session.transport()
        defer { Task { await transport.close() } }

        // Step 1: Ping
        let ping = LookinConnectionAttachment()
        ping.dataType = LookinCodingValueType(rawValue: 4)!
        ping.data = NSNumber(value: LOOKIN_CLIENT_VERSION)
        _ = try? await withRequestTimeout(seconds: 8) {
            try await transport.send(type: UInt32(LookinRequestTypePing), payload: ping)
        }

        // Step 2: Fetch hierarchy to find the item and its class
        let hierarchyReq = LookinConnectionAttachment()
        hierarchyReq.dataType = LookinCodingValueType(rawValue: 4)!
        hierarchyReq.data = NSNumber(value: LOOKIN_CLIENT_VERSION)
        let hierResponse = try await withRequestTimeout(seconds: 30) {
            try await transport.send(type: UInt32(LookinRequestTypeHierarchy), payload: hierarchyReq)
        }
        guard let info = hierResponse.data as? LookinHierarchyInfo else { return nil }
        let roots = info.displayItems ?? []
        let all = flatItems(from: roots)
        guard let item = all.first(where: { ($0.viewObject?.oid ?? $0.layerObject?.oid) == viewOid }) else {
            return nil
        }

        let className = item.viewObject?.rawClassName() ?? item.layerObject?.rawClassName() ?? ""
        let isImageView = className.hasSuffix("ImageView")

        if isImageView, let viewObjOid = item.viewObject?.oid {
            // Request 208 (FetchImageViewImage): takes UIImageView OID, returns NSData (PNG/JPEG)
            return try await fetchImageViewImage(transport: transport, imageViewOid: viewObjOid)
        } else {
            // Request 203 (HierarchyDetails) streaming: fetch solo screenshot via CALayer rendering
            let layerOid = item.layerObject?.oid ?? (item.viewObject?.oid ?? 0)
            return try await fetchLayerScreenshot(transport: transport, layerOid: layerOid)
        }
    }

    private static func fetchImageViewImage(
        transport: PeertalkTransport,
        imageViewOid: UInt,
    ) async throws -> Data? {
        let req = LookinConnectionAttachment()
        req.dataType = LookinCodingValueType(rawValue: 4)! // LongLong NSNumber
        req.data = NSNumber(value: imageViewOid)

        let response = try await withRequestTimeout(seconds: 20) {
            try await transport.send(type: UInt32(LookinRequestTypeFetchImageViewImage), payload: req)
        }

        if let resp = response as? LookinConnectionResponseAttachment, let err = resp.error {
            fputs("warning: FetchImageViewImage error: \(err.localizedDescription)\n", stderr)
            return nil
        }

        if let data = response.data as? Data { return data }
        if let data = response.data as? NSData { return data as Data }
        return nil
    }

    private static func fetchLayerScreenshot(
        transport: PeertalkTransport,
        layerOid: UInt,
    ) async throws -> Data? {
        // Request 203 (HierarchyDetails) with a single SoloScreenshot task.
        // Server responds with 1 frame containing NSArray<LookinDisplayItemDetail *>.
        let task = LookinStaticAsyncUpdateTask()
        task.oid = layerOid
        task.taskType = LookinStaticAsyncUpdateTaskType(rawValue: 1)! // SoloScreenshot
        task.attrRequest = LookinDetailUpdateTaskAttrRequest(rawValue: 2)! // NotNeed
        task.needBasisVisualInfo = false
        task.needSubitems = false

        let package = LookinStaticAsyncUpdateTasksPackage()
        package.tasks = [task]

        let detailReq = LookinConnectionAttachment()
        detailReq.dataType = LookinCodingValueType(rawValue: 0)!
        detailReq.data = [package] as NSArray

        // Expect exactly 1 streaming frame (1 task in 1 package).
        do {
            let responses = try await withRequestTimeout(seconds: 30) {
                try await transport.sendStreaming(
                    type: UInt32(LookinRequestTypeHierarchyDetails),
                    payload: detailReq,
                    expectedTotal: 1,
                )
            }

            guard let first = responses.first else { return nil }

            if let details = first.data as? [LookinDisplayItemDetail],
               let detail = details.first
            {
                return screenshotData(from: detail)
            }
            if let detail = first.data as? LookinDisplayItemDetail {
                return screenshotData(from: detail)
            }
            fputs("warning: unexpected screenshot response data type: \(type(of: first.data))\n", stderr)
            return nil
        } catch {
            fputs("warning: fetchLayerScreenshot (203) failed: \(error)\n", stderr)
            return nil
        }
    }

    private static func screenshotData(from detail: LookinDisplayItemDetail) -> Data? {
        let image = detail.soloScreenshot ?? detail.groupScreenshot
        guard let image else { return nil }
        return imageToPNGData(image)
    }
}

// MARK: - Platform image → PNG

private func imageToPNGData(_ image: AnyObject) -> Data? {
    // LookinServer encodes screenshots as NSData (PNG).
    // The LookinDisplayItemDetail.initWithCoder: reconstructs them as NSImage (macOS).
    if let data = image as? Data { return data }
    if let data = image as? NSData { return data as Data }
    // NSImage path (macOS target)
    let nsImage = image as? NSImage
    guard let nsImage else { return nil }
    guard let tiff = nsImage.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
    return bitmap.representation(using: .png, properties: [:])
}
