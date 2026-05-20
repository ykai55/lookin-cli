import AppKit
import CoreGraphics
import Foundation

public enum AnnotationError: Error, CustomStringConvertible {
    case badImage
    case contextFailed
    case encodeFailed

    public var description: String {
        switch self {
        case .badImage: "could not decode window screenshot"
        case .contextFailed: "could not create drawing context"
        case .encodeFailed: "could not encode annotated PNG"
        }
    }
}

public enum Annotation {
    /// Draws element outlines + the measured gap onto a window screenshot.
    /// - pngData: full-window screenshot (device-pixel resolution).
    /// - windowPointWidth: the window's width in points (to derive the scale).
    /// - a / b: the two elements' absolute frames, in points.
    public static func render(
        pngData: Data,
        windowPointWidth: CGFloat,
        a: CGRect,
        b: CGRect,
        result: GeometryResult,
        to path: String,
    ) throws {
        guard let rep = NSBitmapImageRep(data: pngData) else { throw AnnotationError.badImage }
        let pixelW = CGFloat(rep.pixelsWide)
        let pixelH = CGFloat(rep.pixelsHigh)
        let scale = pixelW / windowPointWidth

        let canvas = NSImage(size: NSSize(width: pixelW, height: pixelH))
        canvas.addRepresentation(rep)

        let outRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0,
        )!
        guard let ctx = NSGraphicsContext(bitmapImageRep: outRep) else {
            throw AnnotationError.contextFailed
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx

        // Base screenshot.
        rep.draw(in: NSRect(x: 0, y: 0, width: pixelW, height: pixelH))

        /// Point-space (top-left origin) -> pixel-space (bottom-left origin).
        func px(_ r: CGRect) -> NSRect {
            NSRect(x: r.minX * scale,
                   y: pixelH - (r.maxY * scale),
                   width: r.width * scale,
                   height: r.height * scale)
        }

        let blue = NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1)
        let orange = NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.05, alpha: 1)

        let pa = px(a), pb = px(b)
        blue.setStroke()
        let pathA = NSBezierPath(rect: pa); pathA.lineWidth = 1.5 * scale; pathA.stroke()
        orange.setStroke()
        let pathB = NSBezierPath(rect: pb); pathB.lineWidth = 1.5 * scale; pathB.stroke()

        // Dimension line + label across the measured gap.
        let dimColor = NSColor(calibratedRed: 0.78, green: 0.42, blue: 0.05, alpha: 1)
        if let v = result.gap.vertical {
            drawDimension(value: v, axis: .vertical, a: pa, b: pb,
                          scale: scale, color: dimColor)
        } else if let h = result.gap.horizontal {
            drawDimension(value: h, axis: .horizontal, a: pa, b: pb,
                          scale: scale, color: dimColor)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let png = outRep.representation(using: .png, properties: [:]) else {
            throw AnnotationError.encodeFailed
        }
        try png.write(to: URL(fileURLWithPath: path))
    }

    private enum Axis { case vertical, horizontal }

    /// Draws an I-beam dimension line spanning *exactly* the measured gap —
    /// from the facing edge of one element to the facing edge of the other —
    /// with perpendicular end caps, plus a pill label placed beside the line.
    ///
    /// All coordinates are in flipped pixel space (bottom-left origin), so a
    /// rect's `minY` is its visual bottom edge and `maxY` its visual top edge.
    private static func drawDimension(
        value: Double, axis: Axis, a: NSRect, b: NSRect,
        scale: CGFloat, color: NSColor,
    ) {
        color.setStroke()
        color.setFill()
        let line = NSBezierPath()
        line.lineWidth = 2 * scale
        let cap = 9 * scale // half-length of each end cap
        let pillGap = 8 * scale // space between the line and the pill

        let label = String(format: value == value.rounded() ? "%.0f" : "%.1f", value)
        let font = NSFont.boldSystemFont(ofSize: 13 * scale)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.white,
        ]
        let textSize = (label as NSString).size(withAttributes: textAttrs)
        let padX = 11 * scale, padY = 6 * scale
        let pillW = textSize.width + padX * 2
        let pillH = textSize.height + padY * 2

        let pillCenter: NSPoint
        switch axis {
        case .vertical:
            // Gap spans from the lower element's top edge to the upper
            // element's bottom edge.
            let lowerTop = min(a.maxY, b.maxY)
            let upperBottom = max(a.minY, b.minY)
            let lineX = (a.midX + b.midX) / 2
            line.move(to: NSPoint(x: lineX, y: lowerTop))
            line.line(to: NSPoint(x: lineX, y: upperBottom))
            line.move(to: NSPoint(x: lineX - cap, y: lowerTop))
            line.line(to: NSPoint(x: lineX + cap, y: lowerTop))
            line.move(to: NSPoint(x: lineX - cap, y: upperBottom))
            line.line(to: NSPoint(x: lineX + cap, y: upperBottom))
            line.stroke()
            // Pill to the left of the line; flip to the right if it would clip.
            let gapMidY = (lowerTop + upperBottom) / 2
            var pillX = lineX - cap - pillGap - pillW / 2
            if pillX - pillW / 2 < 2 * scale {
                pillX = lineX + cap + pillGap + pillW / 2
            }
            pillCenter = NSPoint(x: pillX, y: gapMidY)
        case .horizontal:
            // Gap spans from the left element's right edge to the right
            // element's left edge.
            let leftRight = min(a.maxX, b.maxX)
            let rightLeft = max(a.minX, b.minX)
            let lineY = (a.midY + b.midY) / 2
            line.move(to: NSPoint(x: leftRight, y: lineY))
            line.line(to: NSPoint(x: rightLeft, y: lineY))
            line.move(to: NSPoint(x: leftRight, y: lineY - cap))
            line.line(to: NSPoint(x: leftRight, y: lineY + cap))
            line.move(to: NSPoint(x: rightLeft, y: lineY - cap))
            line.line(to: NSPoint(x: rightLeft, y: lineY + cap))
            line.stroke()
            // Pill above the line.
            let gapMidX = (leftRight + rightLeft) / 2
            pillCenter = NSPoint(x: gapMidX, y: lineY + cap + pillGap + pillH / 2)
        }

        let pill = NSRect(
            x: pillCenter.x - pillW / 2, y: pillCenter.y - pillH / 2,
            width: pillW, height: pillH,
        )
        let pillPath = NSBezierPath(roundedRect: pill, xRadius: pillH / 2, yRadius: pillH / 2)
        pillPath.fill()
        (label as NSString).draw(
            at: NSPoint(x: pill.minX + padX, y: pill.minY + padY),
            withAttributes: textAttrs,
        )
    }
}
