import CoreGraphics
import Foundation

// MARK: - Encodable result types

public struct GeometryResult: Encodable {
    public let gap: Gap
    public let edges: Edges
    public let center: Center
    public let alignment: Alignment
    public let overlap: Overlap?
    public let containment: Containment
}

public struct Gap: Encodable {
    public let vertical: Double?
    public let horizontal: Double?
}

public struct Edges: Encodable {
    public let leftToLeft: Double
    public let rightToRight: Double
    public let topToTop: Double
    public let bottomToBottom: Double
    public let aMaxXToBMinX: Double?
    public let aMaxYToBMinY: Double?
    public let bMaxXToAMinX: Double?
    public let bMaxYToAMinY: Double?
}

public struct Center: Encodable {
    public let dx: Double
    public let dy: Double
}

public struct Alignment: Encodable {
    public let left: Bool
    public let right: Bool
    public let top: Bool
    public let bottom: Bool
    public let centerX: Bool
    public let centerY: Bool
}

public struct Overlap: Encodable {
    public let rect: [Double] // [x, y, w, h]
    public let area: Double
}

public struct Containment: Encodable {
    public let aInsideB: Bool
    public let bInsideA: Bool
}

// MARK: - Pure measurement

public enum Geometry {
    /// True iff the two rects' projections onto the X axis overlap.
    static func overlapsX(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minX < b.maxX && b.minX < a.maxX
    }

    /// True iff the two rects' projections onto the Y axis overlap.
    static func overlapsY(_ a: CGRect, _ b: CGRect) -> Bool {
        a.minY < b.maxY && b.minY < a.maxY
    }

    public static func measure(a: CGRect, b: CGRect, tolerance: Double) -> GeometryResult {
        let tol = CGFloat(tolerance)

        // Gap: empty distance on the axis where the rects do NOT overlap.
        let vGap: Double? = overlapsY(a, b)
            ? nil
            : Double(max(a.minY, b.minY) - min(a.maxY, b.maxY))
        let hGap: Double? = overlapsX(a, b)
            ? nil
            : Double(max(a.minX, b.minX) - min(a.maxX, b.maxX))

        // Facing-edge deltas are only defined on the non-overlapping axis.
        let aMaxXToBMinX: Double? = overlapsX(a, b) ? nil : Double(b.minX - a.maxX)
        let bMaxXToAMinX: Double? = overlapsX(a, b) ? nil : Double(a.minX - b.maxX)
        let aMaxYToBMinY: Double? = overlapsY(a, b) ? nil : Double(b.minY - a.maxY)
        let bMaxYToAMinY: Double? = overlapsY(a, b) ? nil : Double(a.minY - b.maxY)

        let edges = Edges(
            leftToLeft: Double(b.minX - a.minX),
            rightToRight: Double(b.maxX - a.maxX),
            topToTop: Double(b.minY - a.minY),
            bottomToBottom: Double(b.maxY - a.maxY),
            aMaxXToBMinX: aMaxXToBMinX,
            aMaxYToBMinY: aMaxYToBMinY,
            bMaxXToAMinX: bMaxXToAMinX,
            bMaxYToAMinY: bMaxYToAMinY,
        )

        let center = Center(dx: Double(b.midX - a.midX), dy: Double(b.midY - a.midY))

        let alignment = Alignment(
            left: abs(b.minX - a.minX) <= tol,
            right: abs(b.maxX - a.maxX) <= tol,
            top: abs(b.minY - a.minY) <= tol,
            bottom: abs(b.maxY - a.maxY) <= tol,
            centerX: abs(b.midX - a.midX) <= tol,
            centerY: abs(b.midY - a.midY) <= tol,
        )

        let intersection = a.intersection(b)
        let overlap: Overlap? = (intersection.isNull || intersection.isEmpty)
            ? nil
            : Overlap(
                rect: [Double(intersection.minX), Double(intersection.minY),
                       Double(intersection.width), Double(intersection.height)],
                area: Double(intersection.width * intersection.height),
            )

        let containment = Containment(
            aInsideB: b.contains(a),
            bInsideA: a.contains(b),
        )

        return GeometryResult(
            gap: Gap(vertical: vGap, horizontal: hGap),
            edges: edges,
            center: center,
            alignment: alignment,
            overlap: overlap,
            containment: containment,
        )
    }
}
