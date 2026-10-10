import CoreGraphics

public struct AnnotationColor: Equatable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }

    public func withAlpha(_ alpha: CGFloat) -> AnnotationColor {
        AnnotationColor(red: red, green: green, blue: blue, alpha: min(max(alpha, 0), 1))
    }

    /// Opaque default palette (red first, so a new annotation is immediately visible on most content).
    public static let palette: [AnnotationColor] = [
        AnnotationColor(red: 1.00, green: 0.23, blue: 0.19),  // red
        AnnotationColor(red: 1.00, green: 0.58, blue: 0.00),  // orange
        AnnotationColor(red: 1.00, green: 0.80, blue: 0.00),  // yellow
        AnnotationColor(red: 0.20, green: 0.78, blue: 0.35),  // green
        AnnotationColor(red: 0.00, green: 0.48, blue: 1.00),  // blue
        AnnotationColor(red: 0.69, green: 0.32, blue: 0.87),  // purple
        AnnotationColor(red: 0.00, green: 0.00, blue: 0.00),  // black
        AnnotationColor(red: 1.00, green: 1.00, blue: 1.00),  // white
    ]
}

public struct StrokeStyle: Equatable {
    public var color: AnnotationColor
    /// Width in points.
    public var width: CGFloat

    public init(color: AnnotationColor, width: CGFloat) {
        self.color = color
        self.width = width
    }
}
