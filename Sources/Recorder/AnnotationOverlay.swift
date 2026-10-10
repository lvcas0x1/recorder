import AppKit
import Annotation

/// Live annotation over the recorded area (design D5).
///
/// - `canvas` draws the annotations. It is the one window of this app that the capture filter includes, so the
///   drawings appear in the video. With no tool active it ignores the mouse, so clicks reach the apps below.
/// - `chrome` draws editing aids (the text box frame and handles, the caret, the eraser ring). It is not captured.
final class AnnotationOverlay {
    let area: CGRect
    let document = AnnotationDocument()
    let drawing: DrawingController
    private let canvas: CanvasPanel
    private let chrome: PassivePanel
    /// Last pointer position over the canvas, for the eraser ring.
    fileprivate var pointer: CGPoint?
    var onChange: (() -> Void)?

    /// - Parameter area: The recorded area in global top-left points.
    init(area: CGRect) {
        self.area = area
        drawing = DrawingController(document: document)
        let frame = ScreenSpace.appKit(fromTopLeft: area)
        canvas = CanvasPanel(frame: frame)
        chrome = PassivePanel(frame: frame, level: Levels.chrome)
        let canvasView = CanvasView(overlay: nil, size: area.size)
        canvas.contentView = canvasView
        chrome.contentView = ChromeView(overlay: nil, size: area.size)
        canvasView.overlay = self
        (chrome.contentView as? ChromeView)?.overlay = self
        document.onChange = { [weak self] in self?.changed() }
        drawing.onDraftChange = { [weak self] in self?.changed() }
    }

    /// The canvas window number, needed to include it in the capture filter.
    var canvasWindowNumber: Int { canvas.windowNumber }

    func show() {
        canvas.orderFrontRegardless()
        chrome.orderFrontRegardless()
    }

    func close() {
        drawing.tool = nil
        canvas.orderOut(nil)
        chrome.orderOut(nil)
    }

    /// Selects `tool`, or leaves it when it is already active (`nil` leaves any tool).
    func toggleTool(_ tool: DrawingTool?) {
        drawing.tool = (tool == nil || drawing.tool == tool) ? nil : tool
        toolChanged()
    }

    func undo() {
        // While typing, undo throws the unfinished text away instead of removing an earlier annotation.
        if drawing.isEditingText { drawing.cancelText() } else { document.undo() }
    }

    func redo() { document.redo() }
    func clearAll() { document.clearAll() }

    /// Called after a key-driven tool change too (Tab, Esc).
    fileprivate func toolChanged() {
        let active = drawing.tool != nil
        canvas.ignoresMouseEvents = !active
        if active {
            canvas.makeKey()
            canvas.makeFirstResponder(canvas.contentView)
        } else {
            canvas.resignKey()
        }
        canvas.invalidateCursorRects(for: canvas.contentView!)
        changed()
    }

    fileprivate func changed() {
        canvas.contentView?.needsDisplay = true
        chrome.contentView?.needsDisplay = true
        onChange?()
    }

    fileprivate func toLocal(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - area.minX, y: p.y - area.minY) }
}

private final class CanvasPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = Levels.overlay
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: Canvas (captured)

private final class CanvasView: NSView {
    weak var overlay: AnnotationOverlay?
    fileprivate var candidateTimer: Timer?
    private static let preciseStep: CGFloat = 20
    private static let wheelInterval: TimeInterval = 0.06
    private var scrollAccumulator: CGFloat = 0
    private var lastWheelStep: TimeInterval = 0

    init(overlay: AnnotationOverlay?, size: CGSize) {
        self.overlay = overlay
        super.init(frame: CGRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var drawing: DrawingController? { overlay?.drawing }

    private func global(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x + (overlay?.area.minX ?? 0), y: p.y + (overlay?.area.minY ?? 0))
    }

    override func resetCursorRects() {
        if drawing?.tool != nil { addCursorRect(bounds, cursor: .crosshair) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    // MARK: Mouse

    override func mouseMoved(with event: NSEvent) {
        let point = global(event)
        overlay?.pointer = point
        drawing?.pointerMoved(to: point)
        if drawing?.tool == .eraser { overlay?.changed() }
    }

    override func mouseExited(with event: NSEvent) {
        overlay?.pointer = nil
        overlay?.changed()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        drawing?.pointerDown(at: global(event), shift: event.modifierFlags.contains(.shift))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = global(event)
        overlay?.pointer = point
        drawing?.pointerDragged(to: point, shift: event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) { drawing?.pointerUp(at: global(event)) }

    /// Right-click finishes a line strip.
    override func rightMouseDown(with event: NSEvent) { drawing?.finishDraft() }

    /// Wheel up widens the pen by 1 pt per step. With natural scrolling the reported delta is inverted, so the device
    /// direction is used. One wheel notch can arrive as a burst of events, so a mouse wheel steps at most once per
    /// `wheelInterval`; a trackpad steps once per `preciseStep` points of accumulated scrolling.
    override func scrollWheel(with event: NSEvent) {
        guard drawing?.tool?.usesStrokeWidth == true, event.scrollingDeltaY != 0 else { return }
        let deviceDelta = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
        var steps = 0
        if event.hasPreciseScrollingDeltas {
            scrollAccumulator += deviceDelta
            while abs(scrollAccumulator) >= Self.preciseStep {
                steps += scrollAccumulator > 0 ? 1 : -1
                scrollAccumulator -= scrollAccumulator > 0 ? Self.preciseStep : -Self.preciseStep
            }
        } else if event.timestamp - lastWheelStep >= Self.wheelInterval {
            lastWheelStep = event.timestamp
            steps = deviceDelta > 0 ? 1 : -1
        }
        guard steps != 0 else { return }
        drawing?.adjustWidth(by: CGFloat(steps))
        overlay?.changed()
    }

    // MARK: Keys

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let overlay, overlay.drawing.tool != nil else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch (flags, event.charactersIgnoringModifiers?.lowercased()) {
        case (.command, "z"): overlay.undo()
        case (.command, "y"): overlay.redo()
        case ([.command, .shift], "z"): overlay.clearAll()
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let overlay, let drawing else { return }
        // While text is being edited every key goes to the input method (Japanese composition, Return, Delete, Esc).
        if drawing.isEditingText {
            interpretKeyEvents([event])
            return
        }
        if event.keyCode == 53 { // Escape leaves the tool
            overlay.toggleTool(nil)
            return
        }
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.shift).isEmpty,
              let key = event.charactersIgnoringModifiers else { return super.keyDown(with: event) }
        switch key {
        case "\t":
            guard drawing.toggleLineArrow() else { return }
            overlay.toolChanged()
        case "1":
            guard drawing.tool?.usesStrokeWidth == true else { return }
            drawing.adjustWidth(by: -1)
            overlay.changed()
        case "2":
            guard drawing.tool?.usesStrokeWidth == true else { return }
            drawing.adjustWidth(by: 1)
            overlay.changed()
        case "\r":
            drawing.finishDraft()
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: Drawing (this is what the video shows)

    override func draw(_ dirtyRect: NSRect) {
        guard let overlay, let cg = NSGraphicsContext.current?.cgContext else { return }
        cg.saveGState()
        // Annotations live in global top-left points; this flipped view starts at the area's origin.
        cg.translateBy(x: -overlay.area.minX, y: -overlay.area.minY)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        let scale = window?.backingScaleFactor ?? 2
        let context = AnnotationRenderContext(context: cg, scale: scale, origin: overlay.area.origin)
        overlay.document.draw(in: context, draft: overlay.drawing.draft, hidden: overlay.drawing.pendingErasure)
        if let text = overlay.drawing.textDraft {
            cg.saveGState()
            text.render(in: context)
            cg.restoreGState()
        }
        cg.restoreGState()
    }
}

// MARK: Text input (typing and Japanese/CJK composition for the text tool)

extension CanvasView: NSTextInputClient {
    private static func plain(_ value: Any) -> String {
        (value as? NSAttributedString)?.string ?? (value as? String) ?? ""
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        drawing?.insertText(Self.plain(string))
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        drawing?.setMarkedText(Self.plain(string))
        startCandidateWatch()
    }

    /// The input method's candidate list is a normal-level window of this process, so the floating canvas would hide
    /// it. While text is being composed, lift such windows above the overlay every 0.1 s.
    private func startCandidateWatch() {
        raiseCandidateWindows()
        guard candidateTimer == nil else { return }
        candidateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self, self.hasMarkedText() else {
                timer.invalidate()
                self?.candidateTimer = nil
                return
            }
            self.raiseCandidateWindows()
        }
    }

    private func raiseCandidateWindows() {
        for other in NSApp.windows where other.isVisible && Self.isCandidateWindow(other) {
            if other.level.rawValue <= Levels.chrome.rawValue {
                other.level = Levels.toolbox
                other.orderFrontRegardless()
            }
        }
    }

    private static func isCandidateWindow(_ window: NSWindow) -> Bool {
        let name = String(describing: type(of: window)).lowercased()
        return name.contains("viewbridge") || name.contains("candidate")
    }

    func unmarkText() { drawing?.unmarkText() }

    func selectedRange() -> NSRange {
        NSRange(location: (drawing?.committedTextLength ?? 0) + (drawing?.markedTextLength ?? 0), length: 0)
    }

    func markedRange() -> NSRange {
        guard let drawing, drawing.markedTextLength > 0 else { return NSRange(location: NSNotFound, length: 0) }
        return NSRange(location: drawing.committedTextLength, length: drawing.markedTextLength)
    }

    func hasMarkedText() -> Bool { (drawing?.markedTextLength ?? 0) > 0 }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    /// Where the input method shows its candidate window: just below the caret, in screen coordinates.
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let caret = drawing?.textDraft?.caret else { return .zero }
        let primaryHeight = ScreenSpace.primaryHeight
        return NSRect(x: caret.bottom.x, y: primaryHeight - caret.bottom.y, width: 1, height: caret.bottom.y - caret.top.y)
    }

    func characterIndex(for point: NSPoint) -> Int { 0 }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)): drawing?.deleteBackward()
        case #selector(NSResponder.insertNewline(_:)): drawing?.insertNewline()
        case #selector(NSResponder.cancelOperation(_:)): drawing?.commitText() // Esc finishes the text
        default: break
        }
    }
}

// MARK: Chrome (not captured)

private final class ChromeView: NSView {
    weak var overlay: AnnotationOverlay?

    init(overlay: AnnotationOverlay?, size: CGSize) {
        self.overlay = overlay
        super.init(frame: CGRect(origin: .zero, size: size))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let overlay, let cg = NSGraphicsContext.current?.cgContext else { return }
        if overlay.drawing.tool == .eraser, let pointer = overlay.pointer {
            let p = overlay.toLocal(pointer)
            let r = DrawingController.eraserRadius
            cg.setStrokeColor(NSColor.controlAccentColor.cgColor)
            cg.setLineWidth(1.5)
            cg.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        }
        guard let box = overlay.drawing.textDraft else { return }
        drawTextEditor(box, overlay: overlay, in: cg)
    }

    /// Frame, corner handles, rotation handle, and caret of the text being edited.
    private func drawTextEditor(_ box: TextAnnotation, overlay: AnnotationOverlay, in cg: CGContext) {
        let corners = box.corners.map(overlay.toLocal)
        cg.saveGState()
        cg.setStrokeColor(NSColor.controlAccentColor.cgColor)
        cg.setLineWidth(1)
        cg.setLineDash(phase: 0, lengths: [4, 3])
        cg.beginPath()
        cg.addLines(between: corners)
        cg.closePath()
        cg.strokePath()
        cg.setLineDash(phase: 0, lengths: [])

        let topLeft = box.point(of: .topLeft), topRight = box.point(of: .topRight)
        let topCenter = overlay.toLocal(CGPoint(x: (topLeft.x + topRight.x) / 2, y: (topLeft.y + topRight.y) / 2))
        let rotate = overlay.toLocal(box.point(of: .rotate))
        cg.beginPath()
        cg.move(to: topCenter)
        cg.addLine(to: rotate)
        cg.strokePath()

        cg.setFillColor(NSColor.white.cgColor)
        cg.setLineWidth(1.5)
        for corner in corners {
            let r = CGRect(x: corner.x - 4, y: corner.y - 4, width: 8, height: 8)
            cg.fill(r)
            cg.stroke(r)
        }
        let circle = CGRect(x: rotate.x - 5, y: rotate.y - 5, width: 10, height: 10)
        cg.fillEllipse(in: circle)
        cg.strokeEllipse(in: circle)

        let caret = box.caret
        cg.beginPath()
        cg.move(to: overlay.toLocal(caret.top))
        cg.addLine(to: overlay.toLocal(caret.bottom))
        cg.strokePath()
        cg.restoreGState()
    }
}
