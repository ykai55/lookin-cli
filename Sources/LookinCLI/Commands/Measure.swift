import ArgumentParser
import CoreGraphics
import Foundation
import LookinCore

struct Measure: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "measure",
        abstract: "Measure the geometric relationship between two UI elements.",
    )

    @OptionGroup var output: OutputOptions

    @Argument(help: "First element selector: oid:<n> | point:<x>,<y> | axe:<id>")
    var selectorA: String

    @Argument(help: "Second element selector: oid:<n> | point:<x>,<y> | axe:<id>")
    var selectorB: String

    @Option(name: .long, help: "Alignment tolerance in points (default: 0.5).")
    var tolerance: Double = 0.5

    @Option(name: .long, help: "Also write an annotated PNG to this path.")
    var annotate: String?

    // MARK: Encodable report

    struct ElementReport: Encodable {
        let selector: String
        let oid: UInt
        let `class`: String
        let absoluteFrame: [Double]
        let parent: ParentRef?
        let boxModel: BoxModel?
    }

    struct ParentRef: Encodable { let oid: UInt; let `class`: String }
    struct BoxModel: Encodable {
        let top: Double; let left: Double; let right: Double; let bottom: Double
    }

    struct Report: Encodable {
        let a: ElementReport
        let b: ElementReport
        let gap: Gap
        let edges: Edges
        let center: Center
        let alignment: Alignment
        let overlap: Overlap?
        let containment: Containment
        let commonAncestor: ParentRef?
        let coordinateModel: String
        var annotated: String?
    }

    func run() throws {
        let session = try loadSession()

        let selA = try Selector.parse(selectorA)
        let selB = try Selector.parse(selectorB)

        let report = try runAsync { () -> Report in
            let hierarchy = try await Hierarchy.fetch(session: session)
            let a = try resolveSelector(raw: selectorA, selector: selA,
                                        hierarchy: hierarchy, session: session)
            let b = try resolveSelector(raw: selectorB, selector: selB,
                                        hierarchy: hierarchy, session: session)
            if a.oid == b.oid {
                throw MeasureError.sameElement(a.oid)
            }
            guard let frameA = hierarchy.absoluteFrame(oid: a.oid),
                  let frameB = hierarchy.absoluteFrame(oid: b.oid)
            else {
                throw MeasureError.noAbsoluteFrame
            }

            let geo = Geometry.measure(a: frameA, b: frameB, tolerance: tolerance)

            var rep = Report(
                a: Measure.elementReport(a, hierarchy: hierarchy),
                b: Measure.elementReport(b, hierarchy: hierarchy),
                gap: geo.gap, edges: geo.edges, center: geo.center,
                alignment: geo.alignment, overlap: geo.overlap,
                containment: geo.containment,
                commonAncestor: Measure.commonAncestorRef(a.oid, b.oid, hierarchy: hierarchy),
                coordinateModel: "frame-accumulation",
                annotated: nil,
            )

            if let annotatePath = annotate {
                do {
                    try await Measure.annotateScreenshot(
                        session: session, hierarchy: hierarchy,
                        frameA: frameA, frameB: frameB, result: geo, to: annotatePath,
                    )
                    rep.annotated = annotatePath
                } catch {
                    FileHandle.standardError.write(
                        Data("warning: annotation failed: \(error)\n".utf8),
                    )
                }
            }
            return rep
        }

        try emit(report, options: output)
        exitSuccess()
    }

    // MARK: Helpers

    private static func elementReport(
        _ el: ResolvedElement, hierarchy: Hierarchy,
    ) -> ElementReport {
        let absFrame = hierarchy.absoluteFrame(oid: el.oid) ?? .zero
        let parentItem = hierarchy.parent(oid: el.oid)
        let parentRef: ParentRef? = parentItem.flatMap { p in
            Hierarchy.oid(of: p).map {
                ParentRef(oid: $0, class: Hierarchy.className(of: p))
            }
        }
        var box: BoxModel?
        if let p = parentItem {
            let f = el.item.frame
            let pb = p.bounds
            box = BoxModel(
                top: Double(f.minY - pb.minY),
                left: Double(f.minX - pb.minX),
                right: Double(pb.maxX - f.maxX),
                bottom: Double(pb.maxY - f.maxY),
            )
        }
        return ElementReport(
            selector: el.raw,
            oid: el.oid,
            class: Hierarchy.className(of: el.item),
            absoluteFrame: [Double(absFrame.minX), Double(absFrame.minY),
                            Double(absFrame.width), Double(absFrame.height)],
            parent: parentRef,
            boxModel: box,
        )
    }

    private static func commonAncestorRef(
        _ a: UInt, _ b: UInt, hierarchy: Hierarchy,
    ) -> ParentRef? {
        guard let oid = hierarchy.commonAncestorOid(a, b),
              let item = hierarchy.item(oid: oid) else { return nil }
        return ParentRef(oid: oid, class: Hierarchy.className(of: item))
    }

    /// Fetches a base screenshot and renders the annotation onto it.
    private static func annotateScreenshot(
        session: Session, hierarchy: Hierarchy,
        frameA: CGRect, frameB: CGRect, result: GeometryResult, to path: String,
    ) async throws {
        guard let window = hierarchy.roots.first else {
            throw MeasureError.noWindow
        }
        let png = try await captureBase(session: session, hierarchy: hierarchy, window: window)
        try Annotation.render(
            pngData: png,
            windowPointWidth: window.frame.width,
            a: frameA, b: frameB, result: result, to: path,
        )
    }

    /// Captures the base image the annotation draws onto.
    ///
    /// On a simulator we prefer a real `simctl io screenshot`: it captures the
    /// physical panel at full fidelity. The annotation's `scale = pixelWidth /
    /// windowPointWidth` absorbs the panel-vs-window resolution difference, so
    /// LookinServer-space rects still map correctly onto it.
    ///
    /// LookinServer's own `groupScreenshot` is the fallback (for real devices,
    /// or if simctl fails). Note it renders blank for some SwiftUI-hosted
    /// windows that do not rasterize via `renderInContext`.
    private static func captureBase(
        session: Session, hierarchy _: Hierarchy, window: LookinDisplayItem,
    ) async throws -> Data {
        if session.target == .simulator,
           let udid = session.simulatorUDID,
           let png = simctlScreenshot(udid: udid)
        {
            return png
        }
        guard let windowOid = Hierarchy.oid(of: window) else {
            throw MeasureError.noWindow
        }
        // The hierarchy fetch already opened and closed a connection. LookinServer
        // is single-client and re-listens after every close, so a second
        // connection opened immediately after can race the relisten — retry.
        var png: Data?
        for attempt in 0 ..< 4 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
            do {
                png = try await Screenshot.fetchScreenshot(session: session, viewOid: windowOid)
                if png != nil { break }
            } catch {
                if attempt == 3 { throw error }
            }
        }
        guard let png else {
            throw MeasureError.screenshotFailed
        }
        return png
    }

    /// Runs `xcrun simctl io <udid> screenshot` and returns the PNG bytes.
    private static func simctlScreenshot(udid: String) -> Data? {
        let tmp = NSTemporaryDirectory() + "lookin-measure-\(UUID().uuidString).png"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["simctl", "io", udid, "screenshot", tmp]
        proc.standardOutput = Pipe()
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        defer { try? FileManager.default.removeItem(atPath: tmp) }
        guard proc.terminationStatus == 0 else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: tmp))
    }
}

enum MeasureError: Error, CustomStringConvertible {
    case sameElement(UInt)
    case noAbsoluteFrame
    case noWindow
    case screenshotFailed

    var description: String {
        switch self {
        case let .sameElement(n):
            "both selectors resolved to the same element (oid \(n))"
        case .noAbsoluteFrame:
            "could not compute absolute frame for an element"
        case .noWindow:
            "no root window in hierarchy"
        case .screenshotFailed:
            "window screenshot fetch returned no data"
        }
    }
}
