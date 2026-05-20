import CoreGraphics
import Foundation
import LookinCore
import LookinTransport

/// Fetches the view hierarchy once and provides oid lookup, parent lookup,
/// and screen-absolute frame computation. Shared substrate for `measure`
/// (and a candidate for migrating tree/find/attributes onto later).
public final class Hierarchy {
    public let roots: [LookinDisplayItem]
    public let serverVersion: Int

    private var itemByOid: [UInt: LookinDisplayItem] = [:]
    private var parentByOid: [UInt: UInt] = [:]
    private var absoluteOriginByOid: [UInt: CGPoint] = [:]

    public init(info: LookinHierarchyInfo) {
        roots = info.displayItems ?? []
        serverVersion = Int(info.serverVersion)
        index()
    }

    /// Fetches and indexes the hierarchy from a live LookinServer.
    ///
    /// LookinServer is single-client and re-listens after every connection
    /// close, so a connect that lands during the relisten window fails with an
    /// I/O error. Retry a few times with a short backoff.
    public static func fetch(session: Session) async throws -> Hierarchy {
        var lastError: Error?
        for attempt in 0 ..< 4 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
            do {
                let info = try await Tree.fetchHierarchy(session: session)
                return Hierarchy(info: info)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? LookinTransportError.notConnected
    }

    /// The public oid of an item: the view's oid, or the layer's if view-less.
    public static func oid(of item: LookinDisplayItem) -> UInt? {
        if let v = item.viewObject { return v.oid }
        if let l = item.layerObject { return l.oid }
        return nil
    }

    public static func className(of item: LookinDisplayItem) -> String {
        (item.viewObject ?? item.layerObject)?.rawClassName() ?? "(unknown)"
    }

    private func index() {
        func visit(_ item: LookinDisplayItem, parentOid: UInt?, parentAbs: CGPoint, parentBoundsOrigin: CGPoint) {
            guard let id = Hierarchy.oid(of: item) else { return }
            itemByOid[id] = item
            let absOrigin: CGPoint = if parentOid != nil {
                CGPoint(
                    x: parentAbs.x + item.frame.origin.x - parentBoundsOrigin.x,
                    y: parentAbs.y + item.frame.origin.y - parentBoundsOrigin.y,
                )
            } else {
                item.frame.origin
            }
            if let parentOid { parentByOid[id] = parentOid }
            absoluteOriginByOid[id] = absOrigin
            for child in item.subitems ?? [] {
                visit(child, parentOid: id, parentAbs: absOrigin, parentBoundsOrigin: item.bounds.origin)
            }
        }
        for root in roots {
            visit(root, parentOid: nil, parentAbs: .zero, parentBoundsOrigin: .zero)
        }
    }

    public func item(oid: UInt) -> LookinDisplayItem? {
        itemByOid[oid]
    }

    public func parent(oid: UInt) -> LookinDisplayItem? {
        guard let pid = parentByOid[oid] else { return nil }
        return itemByOid[pid]
    }

    public func absoluteFrame(oid: UInt) -> CGRect? {
        guard let item = itemByOid[oid], let origin = absoluteOriginByOid[oid] else { return nil }
        return CGRect(origin: origin, size: item.frame.size)
    }

    /// Deepest (smallest-area) item whose absolute frame contains `point`.
    /// Hidden / fully transparent items are skipped unless `includeHidden`.
    public func hitTest(point: CGPoint, includeHidden: Bool = false) -> LookinDisplayItem? {
        var best: (item: LookinDisplayItem, area: CGFloat)?
        for (id, item) in itemByOid {
            if !includeHidden && (item.isHidden || item.alpha <= 0.01) { continue }
            guard let frame = absoluteFrame(oid: id), frame.contains(point) else { continue }
            let area = frame.width * frame.height
            if best == nil || area < best!.area {
                best = (item, area)
            }
        }
        return best?.item
    }

    /// Lowest oid that is an ancestor of (or equal to) both `a` and `b`.
    public func commonAncestorOid(_ a: UInt, _ b: UInt) -> UInt? {
        var ancestorsOfA: Set<UInt> = []
        var cur: UInt? = a
        while let c = cur {
            ancestorsOfA.insert(c)
            cur = parentByOid[c]
        }
        cur = b
        while let c = cur {
            if ancestorsOfA.contains(c) { return c }
            cur = parentByOid[c]
        }
        return nil
    }
}
