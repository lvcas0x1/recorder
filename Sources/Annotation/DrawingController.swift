import CoreGraphics
import Foundation

public enum DrawingTool: Equatable {
    case rectangle, line, arrow, pencil, marker, text, eraser

    /// Whether color and alpha apply to this tool.
    public var usesStrokeStyle: Bool { self != .eraser }
    /// Whether the pen width applies to this tool (text is sized by scaling its box instead).
    public var usesStrokeWidth: Bool { usesStrokeStyle && self != .text }
}

/// Turns pointer input into annotations for the active tool. Pure logic: no AppKit.
public final class DrawingController {
    public static let widthRange: ClosedRange<CGFloat> = 1...24
    /// Minimum pointer travel (points) for a press to count as a drag instead of a click.
    public static let dragThreshold: CGFloat = 3
    /// The marker is a wider, translucent version of the pen.
    public static let markerWidthFactor: CGFloat = 3
    public static let markerAlphaFactor: CGFloat = 0.4
    /// How far (points) from a mark the eraser still removes it.
    public static let eraserRadius: CGFloat = 6

    private enum State {
        case idle
        case pressed(start: CGPoint)
        case dragging(start: CGPoint, points: [CGPoint])
        case strip(points: [CGPoint], cursor: CGPoint?)
    }

    public let document: AnnotationDocument
    /// The active tool; `nil` means the user is not annotating.
    public var tool: DrawingTool? {
        didSet {
            guard tool != oldValue else { return }
            if oldValue == .text { commitText() }
            cancelDraft()
        }
    }

    public private(set) var baseColor = AnnotationColor.palette[0]
    public private(set) var alpha: CGFloat = 1
    public private(set) var width: CGFloat = 3
    private var state: State = .idle
    /// The eraser's last pointer position during a drag.
    private var eraserLast: CGPoint?
    /// Annotations the current eraser gesture will remove on pointer up; the overlay hides them meanwhile.
    public private(set) var pendingErasure: Set<UUID> = []

    // MARK: Text editing state

    private enum TextGesture {
        case scale(startFontSize: CGFloat, startDistance: CGFloat)
        case rotate
    }

    private var textBox: TextAnnotation?
    private var committedText = ""
    private var markedText = ""
    private var textGesture: TextGesture?

    /// Called when the in-progress shape changes (for live preview).
    public var onDraftChange: (() -> Void)?

    public init(document: AnnotationDocument) {
        self.document = document
    }

    public var isEditing: Bool { tool != nil }
    public var color: AnnotationColor { baseColor.withAlpha(alpha) }

    public var isDraftActive: Bool {
        if case .idle = state { return false }
        return true
    }

    // MARK: Style

    public func setColor(_ color: AnnotationColor) {
        baseColor = color.withAlpha(1)
        alpha = color.alpha
        onDraftChange?()
    }

    public func setAlpha(_ value: CGFloat) {
        alpha = min(max(value, 0), 1)
        onDraftChange?()
    }

    public func setWidth(_ value: CGFloat) {
        width = min(max(value, Self.widthRange.lowerBound), Self.widthRange.upperBound)
    }

    /// Positive grows and negative shrinks the pen by `steps` points.
    public func adjustWidth(by steps: CGFloat) { setWidth(width + steps) }

    /// Tab: switches between the line and arrow tools. Returns `false` for any other tool.
    @discardableResult
    public func toggleLineArrow() -> Bool {
        switch tool {
        case .line: tool = .arrow; return true
        case .arrow: tool = .line; return true
        default: return false
        }
    }

    private var penStyle: StrokeStyle { StrokeStyle(color: color, width: width) }
    private var markerStyle: StrokeStyle {
        StrokeStyle(color: color.withAlpha(alpha * Self.markerAlphaFactor), width: width * Self.markerWidthFactor)
    }

    // MARK: Pointer input

    /// - Parameter shift: Whether Shift is held; with the text tool, grabbing a corner with Shift levels the text.
    public func pointerDown(at point: CGPoint, shift: Bool = false) {
        guard tool != nil else { return }
        if tool == .text {
            textPointerDown(at: point, shift: shift)
            return
        }
        if tool == .eraser {
            eraserLast = point
            pendingErasure = document.hits(at: point, tolerance: Self.eraserRadius)
            onDraftChange?()
            return
        }
        switch state {
        case .strip: break // clicks extend the strip on pointer up
        default: state = .pressed(start: point)
        }
        onDraftChange?()
    }

    /// - Parameter shift: With the text tool, holding Shift while rotating snaps to right angles.
    public func pointerDragged(to point: CGPoint, shift: Bool = false) {
        guard let tool else { return }
        if tool == .text {
            textPointerDragged(to: point, shift: shift)
            return
        }
        if tool == .eraser {
            eraseAlong(to: point)
            return
        }
        switch state {
        case .pressed(let start):
            guard distance(start, point) >= Self.dragThreshold else { return }
            state = .dragging(start: start, points: [start, point])
        case .dragging(let start, var points):
            if tool == .pencil || tool == .marker { points.append(point) } else { points = [start, point] }
            state = .dragging(start: start, points: points)
        case .strip(let points, _):
            state = .strip(points: points, cursor: point)
        case .idle:
            return
        }
        onDraftChange?()
    }

    /// Hover movement: shows the rubber band of a line strip.
    public func pointerMoved(to point: CGPoint) {
        if case .strip(let points, _) = state {
            state = .strip(points: points, cursor: point)
            onDraftChange?()
        }
    }

    public func pointerUp(at point: CGPoint) {
        guard let tool else { return }
        if tool == .text {
            textGesture = nil
            return
        }
        if tool == .eraser {
            if eraserLast != nil { eraseAlong(to: point) }
            let ids = pendingErasure
            eraserLast = nil
            pendingErasure = []
            document.remove(ids: ids)
            onDraftChange?()
            return
        }
        switch state {
        case .dragging(let start, var points):
            if tool == .pencil || tool == .marker { points.append(point) } else { points = [start, point] }
            commit(tool: tool, points: points)
            state = .idle
        case .pressed(let start):
            // A click: only the line tool uses it (to build a strip).
            if tool == .line {
                state = .strip(points: [start], cursor: nil)
            } else {
                state = .idle
            }
        case .strip(var points, _):
            points.append(point)
            state = .strip(points: points, cursor: nil)
        case .idle:
            return
        }
        onDraftChange?()
    }

    /// Right-click or Return: completes a line strip.
    public func finishDraft() {
        if case .strip(let points, _) = state, points.count >= 2, tool == .line {
            commit(tool: .line, points: points)
        }
        state = .idle
        onDraftChange?()
    }

    /// Adds every annotation touched on the way from the last eraser position to `point`.
    private func eraseAlong(to point: CGPoint) {
        guard let last = eraserLast else { return }
        let steps = max(1, Int((distance(last, point) / 2).rounded(.up)))
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: last.x + (point.x - last.x) * t, y: last.y + (point.y - last.y) * t)
            pendingErasure.formUnion(document.hits(at: p, tolerance: Self.eraserRadius))
        }
        eraserLast = point
        onDraftChange?()
    }

    public func cancelDraft() {
        if eraserLast != nil || !pendingErasure.isEmpty {
            eraserLast = nil
            pendingErasure = []
            onDraftChange?()
        }
        guard isDraftActive else { return }
        state = .idle
        onDraftChange?()
    }

    // MARK: Text

    public var isEditingText: Bool { textBox != nil }

    /// The text box being edited, in the current color; includes any text still being composed by an input method.
    public var textDraft: TextAnnotation? {
        guard var box = textBox else { return nil }
        box.color = color
        return box
    }

    private func textPointerDown(at point: CGPoint, shift: Bool) {
        if var box = textBox, let handle = box.handle(at: point) {
            switch handle {
            case .rotate:
                textGesture = .rotate
            case .topLeft, .topRight, .bottomRight, .bottomLeft:
                if shift { box.rotation = 0 }
                textBox = box
                textGesture = .scale(startFontSize: box.fontSize, startDistance: max(hypot(point.x - box.center.x, point.y - box.center.y), 1))
            }
            onDraftChange?()
            return
        }
        // A press anywhere else finishes the current text and starts a new one at that point.
        commitText()
        let empty = TextAnnotation(text: "", center: .zero, color: color)
        let box = empty.size
        textBox = TextAnnotation(
            text: "", center: CGPoint(x: point.x + box.width / 2, y: point.y + box.height / 2), color: color
        )
        onDraftChange?()
    }

    private func textPointerDragged(to point: CGPoint, shift: Bool) {
        guard var box = textBox, let gesture = textGesture else { return }
        switch gesture {
        case .rotate:
            let angle = atan2(point.x - box.center.x, -(point.y - box.center.y))
            box.rotation = shift ? TextAnnotation.snappedRotation(angle) : angle
        case .scale(let startFontSize, let startDistance):
            let distance = hypot(point.x - box.center.x, point.y - box.center.y)
            let size = startFontSize * distance / startDistance
            box.fontSize = min(max(size, TextAnnotation.fontSizeRange.lowerBound), TextAnnotation.fontSizeRange.upperBound)
        }
        textBox = box
        onDraftChange?()
    }

    private func refreshTextBox() {
        guard let box = textBox else { return }
        textBox = box.settingText(committedText + markedText)
        onDraftChange?()
    }

    /// Typed or committed text from the input method.
    public func insertText(_ string: String) {
        guard textBox != nil else { return }
        markedText = ""
        committedText += string
        refreshTextBox()
    }

    /// Text still being composed (not yet confirmed). Replaces any earlier composition.
    public func setMarkedText(_ string: String) {
        guard textBox != nil else { return }
        markedText = string
        refreshTextBox()
    }

    /// Number of characters still being composed.
    public var markedTextLength: Int { markedText.count }
    /// Number of confirmed characters in the draft.
    public var committedTextLength: Int { committedText.count }

    /// The input method ended composition without replacing the text: keep what was composed.
    public func unmarkText() {
        guard textBox != nil, !markedText.isEmpty else { return }
        committedText += markedText
        markedText = ""
        refreshTextBox()
    }

    public func deleteBackward() {
        guard textBox != nil else { return }
        if !markedText.isEmpty { markedText.removeLast() } else if !committedText.isEmpty { committedText.removeLast() }
        refreshTextBox()
    }

    public func insertNewline() { insertText("\n") }

    /// Finishes the current text. Empty text is discarded.
    public func commitText() {
        guard var box = textBox else { return }
        box.text = committedText + markedText
        box.color = color
        textBox = nil
        committedText = ""
        markedText = ""
        textGesture = nil
        if !box.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { document.add(box) }
        onDraftChange?()
    }

    /// Throws the current text away.
    public func cancelText() {
        guard textBox != nil else { return }
        textBox = nil
        committedText = ""
        markedText = ""
        textGesture = nil
        onDraftChange?()
    }

    // MARK: Draft preview

    /// The shape being drawn, or `nil`. Render it above committed annotations for live feedback.
    public var draft: (any Annotation)? {
        guard let tool else { return nil }
        switch state {
        case .dragging(_, let points): return annotation(tool: tool, points: points, minimumLength: 0)
        case .strip(let points, let cursor): return annotation(tool: .line, points: points + (cursor.map { [$0] } ?? []), minimumLength: 0)
        case .pressed(let start) where tool == .pencil || tool == .marker: return annotation(tool: tool, points: [start], minimumLength: 0)
        default: return nil
        }
    }

    private func commit(tool: DrawingTool, points: [CGPoint]) {
        if let item = annotation(tool: tool, points: points, minimumLength: 2) { document.add(item) }
    }

    private func annotation(tool: DrawingTool, points: [CGPoint], minimumLength: CGFloat) -> (any Annotation)? {
        guard let first = points.first, let last = points.last else { return nil }
        switch tool {
        case .rectangle:
            let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(first.x - last.x), height: abs(first.y - last.y))
            return max(rect.width, rect.height) >= minimumLength ? RectangleAnnotation(rect: rect, style: penStyle) : nil
        case .line:
            guard points.count >= 2, pathLength(points) >= minimumLength else { return nil }
            return PolylineAnnotation(points: points, style: penStyle)
        case .arrow:
            return distance(first, last) >= minimumLength && first != last ? ArrowAnnotation(from: first, to: last, style: penStyle) : nil
        case .pencil:
            return pathLength(points) >= minimumLength ? PolylineAnnotation(points: points, style: penStyle) : nil
        case .marker:
            return pathLength(points) >= minimumLength ? PolylineAnnotation(points: points, style: markerStyle, lineCap: .butt) : nil
        case .text:
            return nil // text boxes are managed by the text editing API
        case .eraser:
            return nil // the eraser removes annotations instead of drawing
        }
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        zip(points, points.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }
}
