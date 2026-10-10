import CoreGraphics
import Foundation

public struct RectangleAnnotation: Annotation {
    public let rect: CGRect
    public let style: StrokeStyle

    public init(rect: CGRect, style: StrokeStyle) {
        self.rect = rect.standardized
        self.style = style
    }

    public func render(in context: AnnotationRenderContext) {
        let ctx = context.context
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.width)
        ctx.setLineJoin(.miter)
        ctx.stroke(rect)
    }

    /// Hits the outline only, so a rectangle drawn around content does not swallow clicks inside it.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY),
        ]
        return HitGeometry.distance(from: point, toPolyline: corners) <= style.width / 2 + tolerance
    }
}

/// A connected series of line segments, used for lines, freehand pencil strokes, and the marker.
/// The whole path is stroked once, so a translucent stroke does not darken where it crosses itself.
public struct PolylineAnnotation: Annotation {
    public let points: [CGPoint]
    public let style: StrokeStyle
    public let lineCap: CGLineCap

    public init(points: [CGPoint], style: StrokeStyle, lineCap: CGLineCap = .round) {
        self.points = points
        self.style = style
        self.lineCap = lineCap
    }

    public func render(in context: AnnotationRenderContext) {
        guard let first = points.first else { return }
        let ctx = context.context
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setLineWidth(style.width)
        ctx.setLineCap(lineCap)
        ctx.setLineJoin(.round)
        if points.count == 1 {
            // A single point renders as a dot.
            ctx.setFillColor(style.color.cgColor)
            let r = style.width / 2
            ctx.fillEllipse(in: CGRect(x: first.x - r, y: first.y - r, width: style.width, height: style.width))
            return
        }
        ctx.beginPath()
        ctx.move(to: first)
        points.dropFirst().forEach { ctx.addLine(to: $0) }
        ctx.strokePath()
    }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        HitGeometry.distance(from: point, toPolyline: points) <= style.width / 2 + tolerance
    }
}

public struct ArrowAnnotation: Annotation {
    public let from: CGPoint
    public let to: CGPoint
    public let style: StrokeStyle

    public init(from: CGPoint, to: CGPoint, style: StrokeStyle) {
        self.from = from
        self.to = to
        self.style = style
    }

    public func render(in context: AnnotationRenderContext) {
        guard let head = ArrowGeometry.head(from: from, to: to, width: style.width) else { return }
        let ctx = context.context
        ctx.setStrokeColor(style.color.cgColor)
        ctx.setFillColor(style.color.cgColor)
        ctx.setLineWidth(style.width)
        ctx.setLineCap(.round)
        ctx.beginPath()
        ctx.move(to: from)
        ctx.addLine(to: head.base)
        ctx.strokePath()
        ctx.beginPath()
        ctx.move(to: head.tip)
        ctx.addLine(to: head.left)
        ctx.addLine(to: head.right)
        ctx.closePath()
        ctx.fillPath()
    }

    /// Hits the shaft or anywhere on the head.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        if HitGeometry.distance(from: point, toSegment: from, to) <= style.width / 2 + tolerance { return true }
        guard let head = ArrowGeometry.head(from: from, to: to, width: style.width) else { return false }
        let edges = [head.tip, head.left, head.right, head.tip]
        return HitGeometry.distance(from: point, toPolyline: edges) <= tolerance
            || Self.triangle(head.tip, head.left, head.right, contains: point)
    }

    private static func triangle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, contains p: CGPoint) -> Bool {
        func sign(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGFloat {
            (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
        }
        let d1 = sign(p, a, b), d2 = sign(p, b, c), d3 = sign(p, c, a)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
    }
}

public enum ArrowGeometry {
    public struct Head: Equatable {
        public let tip: CGPoint
        public let left: CGPoint
        public let right: CGPoint
        /// Midpoint of the head's back edge; the shaft ends here so it never pokes past the tip.
        public let base: CGPoint
    }

    /// Head size grows with the stroke width and never exceeds 60% of the arrow's length.
    public static func head(from: CGPoint, to: CGPoint, width: CGFloat) -> Head? {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return nil }
        let headLength = min(max(10, width * 4), length * 0.6)
        let halfSpread = headLength * tan(28 * .pi / 180)
        let ux = dx / length, uy = dy / length
        let base = CGPoint(x: to.x - ux * headLength, y: to.y - uy * headLength)
        // (-uy, ux) is the unit normal of the arrow's direction.
        let left = CGPoint(x: base.x - uy * halfSpread, y: base.y + ux * halfSpread)
        let right = CGPoint(x: base.x + uy * halfSpread, y: base.y - ux * halfSpread)
        return Head(tip: to, left: left, right: right, base: base)
    }
}
