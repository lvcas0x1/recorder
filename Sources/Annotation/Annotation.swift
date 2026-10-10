import CoreGraphics

/// Everything an annotation needs to draw itself, live on the overlay or when flattened onto an image.
public struct AnnotationRenderContext {
    /// Context whose user space is global screen points with the origin at the top-left (y grows downward).
    public let context: CGContext
    /// Output pixels per point.
    public let scale: CGFloat
    /// The image being annotated when flattening; `nil` when drawing live over the screen.
    public let base: CGImage?
    /// Global top-left point corresponding to the top-left pixel of `base`.
    public let origin: CGPoint

    public init(context: CGContext, scale: CGFloat, base: CGImage? = nil, origin: CGPoint) {
        self.context = context
        self.scale = scale
        self.base = base
        self.origin = origin
    }

    /// The area covered by `base`, in global points; `nil` when there is no base image.
    public var bounds: CGRect? {
        base.map { CGRect(x: origin.x, y: origin.y, width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale) }
    }
}

/// A drawable mark. Implementations are value types holding their geometry in global top-left points.
public protocol Annotation {
    func render(in context: AnnotationRenderContext)
    /// Whether `point` touches the drawn mark, allowing `tolerance` points of slack (used by the eraser).
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool
}

public extension Annotation {
    func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool { false }
}

public enum HitGeometry {
    /// Shortest distance from `point` to the segment `a`-`b`.
    public static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(max(((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared, 0), 1)
        return hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
    }

    /// Shortest distance from `point` to the polyline through `points`.
    public static func distance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return hypot(point.x - first.x, point.y - first.y) }
        return zip(points, points.dropFirst()).map { distance(from: point, toSegment: $0.0, $0.1) }.min() ?? .infinity
    }
}
