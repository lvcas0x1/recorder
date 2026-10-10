import CoreGraphics
import CoreText
import Foundation

/// A text box: multi-line text drawn around `center`, rotated by `rotation` (radians, clockwise on screen).
public struct TextAnnotation: Annotation {
    public enum Handle: Equatable {
        case topLeft, topRight, bottomRight, bottomLeft
        case rotate
    }

    public static let padding: CGFloat = 4
    /// Distance from the top edge of the box to the rotation handle.
    public static let rotationHandleOffset: CGFloat = 24
    public static let fontSizeRange: ClosedRange<CGFloat> = 6...300
    public static let defaultFontSize: CGFloat = 24

    public var text: String
    /// Center of the box in global top-left points.
    public var center: CGPoint
    public var fontSize: CGFloat
    public var rotation: CGFloat
    public var color: AnnotationColor

    public init(
        text: String, center: CGPoint, fontSize: CGFloat = TextAnnotation.defaultFontSize,
        rotation: CGFloat = 0, color: AnnotationColor
    ) {
        self.text = text
        self.center = center
        self.fontSize = fontSize
        self.rotation = rotation
        self.color = color
    }

    /// Magnet for rotating with Shift held: within `toleranceDegrees` of 0, 90, 180, or 270 degrees the angle
    /// snaps to that right angle; elsewhere it is unchanged.
    public static func snappedRotation(_ angle: CGFloat, toleranceDegrees: CGFloat = 8) -> CGFloat {
        let quarter = CGFloat.pi / 2
        let nearest = (angle / quarter).rounded() * quarter
        return abs(angle - nearest) <= toleranceDegrees * .pi / 180 ? nearest : angle
    }

    // MARK: Layout

    struct Layout {
        let lines: [CTLine]
        let lineWidths: [CGFloat]
        let ascent: CGFloat
        let lineHeight: CGFloat
        var textWidth: CGFloat { lineWidths.max() ?? 0 }
        var textHeight: CGFloat { lineHeight * CGFloat(max(lines.count, 1)) }
    }

    func layout() -> Layout {
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let ascent = CTFontGetAscent(font)
        let lineHeight = ascent + CTFontGetDescent(font) + CTFontGetLeading(font)
        let strings = text.components(separatedBy: "\n")
        let lines = strings.map { CTLineCreateWithAttributedString(NSAttributedString(string: $0, attributes: attributes)) }
        let widths = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
        return Layout(lines: lines, lineWidths: widths, ascent: ascent, lineHeight: lineHeight)
    }

    /// Size of the (unrotated) box including padding. An empty box keeps a minimum width so it stays visible and clickable.
    public var size: CGSize {
        let l = layout()
        return CGSize(
            width: max(l.textWidth, fontSize * 0.5) + 2 * Self.padding,
            height: l.textHeight + 2 * Self.padding
        )
    }

    // MARK: Geometry

    /// Maps a point in the box's own frame (origin at the center, y down) to global points.
    func toWorld(_ local: CGPoint) -> CGPoint {
        let c = cos(rotation), s = sin(rotation)
        return CGPoint(x: center.x + local.x * c - local.y * s, y: center.y + local.x * s + local.y * c)
    }

    func toLocal(_ world: CGPoint) -> CGPoint {
        let dx = world.x - center.x, dy = world.y - center.y
        let c = cos(rotation), s = sin(rotation)
        return CGPoint(x: dx * c + dy * s, y: -dx * s + dy * c)
    }

    public func point(of handle: Handle) -> CGPoint {
        let half = CGSize(width: size.width / 2, height: size.height / 2)
        switch handle {
        case .topLeft: return toWorld(CGPoint(x: -half.width, y: -half.height))
        case .topRight: return toWorld(CGPoint(x: half.width, y: -half.height))
        case .bottomRight: return toWorld(CGPoint(x: half.width, y: half.height))
        case .bottomLeft: return toWorld(CGPoint(x: -half.width, y: half.height))
        case .rotate: return toWorld(CGPoint(x: 0, y: -half.height - Self.rotationHandleOffset))
        }
    }

    public var corners: [CGPoint] {
        [Handle.topLeft, .topRight, .bottomRight, .bottomLeft].map(point(of:))
    }

    /// The handle under `point`, preferring the rotation handle.
    public func handle(at point: CGPoint, tolerance: CGFloat = 10) -> Handle? {
        for handle in [Handle.rotate, .topLeft, .topRight, .bottomRight, .bottomLeft] {
            let p = self.point(of: handle)
            if hypot(p.x - point.x, p.y - point.y) <= tolerance { return handle }
        }
        return nil
    }

    /// The text cursor at the end of the last line, as two global points (top, bottom).
    public var caret: (top: CGPoint, bottom: CGPoint) {
        let l = layout()
        let box = size
        let x = -box.width / 2 + Self.padding + (l.lineWidths.last ?? 0)
        let top = -box.height / 2 + Self.padding + CGFloat(max(l.lines.count - 1, 0)) * l.lineHeight
        return (toWorld(CGPoint(x: x, y: top)), toWorld(CGPoint(x: x, y: top + l.lineHeight)))
    }

    /// Top-left of the unrotated frame, kept fixed while text is typed so the box grows rightwards and downwards.
    func anchor() -> CGPoint { toWorld(CGPoint(x: -size.width / 2, y: -size.height / 2)) }

    func settingText(_ newText: String) -> TextAnnotation {
        let anchorPoint = anchor()
        var copy = self
        copy.text = newText
        let box = copy.size
        // center = anchor + R * (w/2, h/2)
        let c = cos(rotation), s = sin(rotation)
        let hx = box.width / 2, hy = box.height / 2
        copy.center = CGPoint(x: anchorPoint.x + hx * c - hy * s, y: anchorPoint.y + hx * s + hy * c)
        return copy
    }

    /// Hits anywhere inside the (rotated) box, grown by `tolerance`.
    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        guard !text.isEmpty else { return false }
        let local = toLocal(point)
        let box = size
        return abs(local.x) <= box.width / 2 + tolerance && abs(local.y) <= box.height / 2 + tolerance
    }

    // MARK: Rendering

    public func render(in context: AnnotationRenderContext) {
        guard !text.isEmpty else { return }
        let ctx = context.context
        let l = layout()
        let box = size
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: rotation)
        ctx.scaleBy(x: 1, y: -1) // y-up local frame so Core Text draws upright
        ctx.setFillColor(color.cgColor)
        ctx.textMatrix = .identity
        let left = -box.width / 2 + Self.padding
        let firstBaseline = box.height / 2 - Self.padding - l.ascent
        for (index, line) in l.lines.enumerated() {
            ctx.textPosition = CGPoint(x: left, y: firstBaseline - CGFloat(index) * l.lineHeight)
            CTLineDraw(line, ctx)
        }
    }
}
