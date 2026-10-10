import AppKit
import Recording
import Selection

/// Lets the user pick what to record: a window (hover highlight, click) or a custom area (drag, handles, Return or
/// the Record button). Esc cancels. One transparent panel per screen over the live screen (spec: Window mode,
/// Custom area mode, Cancel selection).
final class SelectionOverlayController {
    enum Kind { case window, area }

    private let kind: Kind
    private var panels: [SelectionPanel] = []
    private var windows: [WindowInfo] = []
    private(set) var hover: WindowInfo?
    /// Area mode: the model of the screen where the current selection was started.
    private(set) var model: SelectionModel?
    private var previousApp: NSRunningApplication?
    private var completion: ((RecordingTarget?) -> Void)?

    init(kind: Kind) {
        self.kind = kind
    }

    var isAreaMode: Bool { kind == .area }

    func begin(completion: @escaping (RecordingTarget?) -> Void) {
        self.completion = completion
        previousApp = NSWorkspace.shared.frontmostApplication
        windows = kind == .window ? WindowDetector.snapshot().filter { $0.layer == 0 } : []
        panels = NSScreen.screens.map { SelectionPanel(screen: $0, controller: self) }
        NSApp.activate()
        panels.forEach { $0.orderFrontRegardless() }
        let mouseScreen = ScreenSpace.screen(containing: ScreenSpace.mouseLocation)
        panels.first { $0.screen == mouseScreen }?.makeKey()
        updateHover(at: ScreenSpace.mouseLocation)
        NSCursor.crosshair.set()
    }

    // MARK: Input from the panels (points are global top-left)

    func mouseMoved(to point: CGPoint) {
        updateHover(at: point)
        redraw()
    }

    func mouseDown(at point: CGPoint) {
        guard kind == .area else { return }
        if model == nil || !(model!.bounds.contains(point)) {
            let screen = ScreenSpace.screen(containing: point)
            model = SelectionModel(bounds: ScreenSpace.topLeft(fromAppKit: screen.frame))
        }
        model?.mouseDown(at: point)
        redraw()
    }

    func mouseDragged(to point: CGPoint) {
        guard kind == .area else { return }
        model?.mouseDragged(to: point)
        redraw()
    }

    func mouseUp(at point: CGPoint) {
        switch kind {
        case .window:
            if let window = WindowDetector.hit(point, in: windows) {
                finish(.window(id: window.id, frame: window.frame), activating: window.ownerPID)
            }
        case .area:
            model?.mouseUp(at: point)
            redraw()
        }
    }

    func confirm() {
        guard kind == .area, let rect = model?.rect, rect.width >= 1, rect.height >= 1 else { return }
        finish(.area(rect), activating: nil)
    }

    func cancel() { finish(nil, activating: nil) }

    // MARK: State for drawing

    /// The selected area, or the hovered window's frame.
    var highlight: CGRect? {
        switch kind {
        case .window: hover?.frame
        case .area: model?.rect
        }
    }

    func pixelSize(of rect: CGRect) -> CGSize {
        let scale = ScreenSpace.screen(containing: CGPoint(x: rect.midX, y: rect.midY)).backingScaleFactor
        return CGSize(width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
    }

    private func updateHover(at point: CGPoint) {
        guard kind == .window else { return }
        hover = WindowDetector.hit(point, in: windows)
    }

    private func redraw() { panels.forEach { $0.refresh() } }

    private func finish(_ target: RecordingTarget?, activating pid: Int32?) {
        guard let completion else { return }
        self.completion = nil
        panels.forEach { $0.orderOut(nil) }
        panels = []
        NSCursor.arrow.set()
        // Give the keyboard back: to the picked window's app in window mode, otherwise to the app used before.
        if let pid, let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        } else {
            previousApp?.activate()
        }
        completion(target)
    }
}

private final class SelectionPanel: NSPanel {
    init(screen: NSScreen, controller: SelectionOverlayController) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = Levels.selection
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        // Set explicitly: by default clicks on fully transparent pixels (the highlighted hole) pass through.
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = SelectionView(screenFrame: ScreenSpace.topLeft(fromAppKit: screen.frame), controller: controller)
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func refresh() { (contentView as? SelectionView)?.refresh() }
}

private final class SelectionView: NSView {
    private static let dimAlpha: CGFloat = 0.25
    /// This screen in global top-left points.
    private let screenFrame: CGRect
    private unowned let controller: SelectionOverlayController
    private let recordButton = NSButton(title: "Record", target: nil, action: nil)

    init(screenFrame: CGRect, controller: SelectionOverlayController) {
        self.screenFrame = screenFrame
        self.controller = controller
        super.init(frame: CGRect(origin: .zero, size: screenFrame.size))
        recordButton.bezelStyle = .push
        recordButton.keyEquivalent = "\r"
        recordButton.image = NSImage(systemSymbolName: "record.circle", accessibilityDescription: nil)
        recordButton.imagePosition = .imageLeading
        recordButton.target = self
        recordButton.action = #selector(record)
        recordButton.isHidden = true
        addSubview(recordButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func record() { controller.confirm() }

    func refresh() {
        needsDisplay = true
        layoutRecordButton()
    }

    private func local(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY) }

    private func global(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x + screenFrame.minX, y: p.y + screenFrame.minY)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseMoved(with event: NSEvent) { controller.mouseMoved(to: global(event)) }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        controller.mouseDown(at: global(event))
    }
    override func mouseDragged(with event: NSEvent) { controller.mouseDragged(to: global(event)) }
    override func mouseUp(with event: NSEvent) { controller.mouseUp(at: global(event)) }
    override func rightMouseDown(with event: NSEvent) { controller.cancel() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: controller.cancel() // Escape
        case 36, 76: controller.confirm() // Return, keypad Enter
        default: super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) { controller.cancel() }

    private func layoutRecordButton() {
        guard controller.isAreaMode, let selection = controller.highlight, screenFrame.intersects(selection) else {
            recordButton.isHidden = true
            return
        }
        let rect = local(selection)
        recordButton.sizeToFit()
        var origin = CGPoint(x: rect.maxX - recordButton.frame.width, y: rect.maxY + 8)
        if origin.y + recordButton.frame.height > bounds.maxY { origin.y = rect.maxY - recordButton.frame.height - 8 }
        origin.x = max(bounds.minX + 4, origin.x)
        recordButton.setFrameOrigin(origin)
        recordButton.isHidden = false
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        let highlight = controller.highlight.map(local)
        if let highlight {
            dim.appendRect(highlight)
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(Self.dimAlpha).setFill()
        dim.fill()
        guard let highlight, highlight.intersects(bounds) else { return }

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: highlight.insetBy(dx: -1, dy: -1))
        border.lineWidth = 2
        border.stroke()

        if controller.isAreaMode, let rect = controller.highlight {
            drawHandles(on: highlight)
            drawLabel("\(Int(controller.pixelSize(of: rect).width)) \u{00D7} \(Int(controller.pixelSize(of: rect).height))  \u{00B7}  Return: record  \u{00B7}  Esc: cancel", near: highlight)
        } else {
            drawLabel("Click to record this window  \u{00B7}  Esc: cancel", near: highlight)
        }
    }

    private func drawHandles(on rect: CGRect) {
        for handle in ResizeHandle.allCases {
            let p = handle.position(on: rect)
            let r = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: r).fill()
            NSColor.controlAccentColor.setStroke()
            NSBezierPath(ovalIn: r).stroke()
        }
    }

    private func drawLabel(_ text: String, near rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - 10)
        if origin.y < bounds.minY + 4 { origin.y = rect.minY + 6 }
        origin.x = min(max(origin.x, 4), bounds.maxX - size.width - 12)
        let background = CGRect(x: origin.x, y: origin.y, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: background, xRadius: 5, yRadius: 5).fill()
        string.draw(at: CGPoint(x: origin.x + 6, y: origin.y + 3))
    }
}
