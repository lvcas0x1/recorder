import AppKit
import Annotation
import Recording
import ScreenCaptureKit
import Selection
import Settings
import os

enum CoordinatorError: LocalizedError {
    case targetOffScreen

    var errorDescription: String? { "The selected area is not on a display." }
}

/// Connects the recording session to the on-screen pieces: the selection overlay, the annotation overlay, the
/// frame, the toolbox, and the notices.
@MainActor
final class RecordingCoordinator {
    private let log = Logger(subsystem: "dev.lvcas0x1.recorder", category: "recording")
    private let settings: SettingsStore
    private let notices: NoticeHUD
    private(set) var session: RecordingSession!
    let toolboxModel = ToolboxModel()

    private var selection: SelectionOverlayController?
    private var overlay: AnnotationOverlay?
    private var frame: RecordingFrame?
    private var toolbox: ToolboxPanel?
    private var timer: Timer?
    private lazy var colorPanelBridge = ColorPanelBridge { [weak self] color in self?.applyCustomColor(color) }

    /// Called when the menu-bar indicator must refresh (state or elapsed time changed).
    var onIndicatorChange: (() -> Void)?

    init(settings: SettingsStore, notices: NoticeHUD) {
        self.settings = settings
        self.notices = notices
        session = RecordingSession(
            outputFolder: { settings.outputFolderURL },
            makeEngine: { [unowned self] target, base in try await self.makeEngine(for: target, segmentBase: base) }
        )
        session.onBeginSelection = { [unowned self] mode in self.beginSelection(mode) }
        session.onStateChange = { [unowned self] state in self.stateChanged(state) }
        session.onEnded = { [unowned self] in self.tearDown() }
        session.onSaved = { [unowned self] url in self.notices.showSaved(url) }
        session.onError = { [unowned self] error in self.report(error) }
        wireToolbox()
    }

    var state: RecordingSession.State { session.state }
    var elapsed: TimeInterval { session.elapsed }

    /// A mode shortcut or menu item (spec: one recording at a time; a shortcut stops a running recording).
    func request(_ mode: RecordingMode) {
        Task { await session.request(mode) }
    }

    func stop() {
        Task { await session.stop() }
    }

    // MARK: Selection

    private func beginSelection(_ mode: RecordingMode) {
        switch mode {
        case .fullScreen:
            Task { await session.selectionCompleted(.fullScreen) }
        case .window, .area:
            let controller = SelectionOverlayController(kind: mode == .window ? .window : .area)
            selection = controller
            controller.begin { [weak self] target in
                guard let self else { return }
                self.selection = nil
                if let target {
                    Task { await self.session.selectionCompleted(target) }
                } else {
                    self.session.selectionCancelled()
                }
            }
        }
    }

    // MARK: Starting

    private func makeEngine(for target: RecordingTarget, segmentBase: URL) async throws -> RecordingEngineType {
        let screen: NSScreen
        switch target {
        case .fullScreen:
            screen = ScreenSpace.screen(containing: ScreenSpace.mouseLocation)
        case .window(_, let rect), .area(let rect):
            screen = ScreenSpace.screen(containing: CGPoint(x: rect.midX, y: rect.midY))
        }
        let microphone = await MicrophonePermission.decide(wanted: settings.values.microphone)
        if microphone.showDeniedNotice { showMicrophoneNotice() }
        let options = CaptureOptions(
            box: settings.values.resolution.box,
            systemAudio: settings.values.systemAudio,
            microphone: microphone.capturesMicrophone,
            showsCursor: settings.values.recordCursor
        )
        guard let plan = CapturePlan.make(target: target, display: ScreenSpace.recordingDisplay(for: screen), options: options) else {
            throw CoordinatorError.targetOffScreen
        }
        log.notice("plan: \(String(describing: plan), privacy: .public)")
        let overlay = showRecordingUI(plan: plan, fullScreen: target == .fullScreen)

        // The overlay must be known to the window server before it can be included in the capture filter.
        var attempt = 0
        while true {
            try await Task.sleep(nanoseconds: 100_000_000)
            do {
                let (filter, configuration) = try await CaptureSetup.make(plan: plan, overlayWindowNumber: overlay.canvasWindowNumber)
                let engine = RecordingEngine(filter: filter, configuration: configuration, segmentBase: segmentBase)
                engine.onMicrophoneUnavailable = { [weak self] in self?.showMicrophoneNotice() }
                return engine
            } catch CaptureSetupError.overlayNotFound where attempt < 10 {
                attempt += 1
            }
        }
    }

    private func showMicrophoneNotice() {
        notices.showMessage(
            "Microphone not recorded", detail: "Recorder has no Microphone permission. The recording continues without it.",
            actionTitle: "Open Settings", action: { NSWorkspace.shared.open(MicrophonePermission.settingsURL) }
        )
    }

    private func showRecordingUI(plan: CapturePlan, fullScreen: Bool) -> AnnotationOverlay {
        let overlay = AnnotationOverlay(area: plan.area)
        overlay.onChange = { [weak self] in self?.syncToolbox() }
        overlay.show()
        self.overlay = overlay

        if plan.showsFrame {
            let frame = RecordingFrame(area: plan.area)
            frame.show()
            self.frame = frame
        }

        toolboxModel.elapsed = 0
        toolboxModel.isPaused = false
        toolboxModel.isFinishing = false
        toolboxModel.showsCursor = plan.showsCursor
        toolboxModel.tool = nil
        toolboxModel.styleRowAbove = false
        let toolbox = ToolboxPanel(model: toolboxModel)
        toolbox.place(near: plan.area, fullScreen: fullScreen)
        toolbox.orderFrontRegardless()
        self.toolbox = toolbox
        syncToolbox()
        return overlay
    }

    // MARK: State

    private func stateChanged(_ state: RecordingSession.State) {
        toolboxModel.isPaused = state == .paused
        toolboxModel.isFinishing = state == .finishing
        switch state {
        case .recording, .paused, .finishing, .starting:
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.tick() }
                }
            }
        case .idle, .selecting:
            timer?.invalidate()
            timer = nil
        }
        tick()
    }

    private func tick() {
        let elapsed = session.elapsed
        if toolboxModel.elapsed != elapsed.rounded(.down) { toolboxModel.elapsed = elapsed.rounded(.down) }
        onIndicatorChange?()
    }

    /// Spec: Annotations end with the recording.
    private func tearDown() {
        NSColorPanel.shared.orderOut(nil)
        overlay?.close()
        overlay = nil
        frame?.close()
        frame = nil
        toolbox?.orderOut(nil)
        toolbox = nil
        onIndicatorChange?()
    }

    private func report(_ error: Error) {
        log.error("recording error: \(String(describing: error), privacy: .public)")
        switch error {
        case RecordingSessionError.joinFailed(let segments, let underlying):
            let names = segments.map(\.lastPathComponent).joined(separator: ", ")
            notices.showError("Could not finish the recording", detail: "\(underlying.localizedDescription) The parts were kept in the output folder as hidden files: \(names)")
        case OutputFilesError.folderNotWritable(let path):
            notices.showError("Cannot save the recording", detail: "The folder is not writable: \((path as NSString).abbreviatingWithTildeInPath)")
        default:
            notices.showError("Recording failed", detail: error.localizedDescription)
        }
    }

    // MARK: Toolbox

    private func wireToolbox() {
        toolboxModel.togglePause = { [unowned self] in Task { await self.session.togglePause() } }
        toolboxModel.stop = { [unowned self] in self.stop() }
        toolboxModel.selectTool = { [unowned self] tool in self.overlay?.toggleTool(tool) }
        toolboxModel.undo = { [unowned self] in self.overlay?.undo() }
        toolboxModel.redo = { [unowned self] in self.overlay?.redo() }
        toolboxModel.clearAll = { [unowned self] in self.overlay?.clearAll() }
        toolboxModel.toggleCursor = { [unowned self] in self.toggleCursor() }
        toolboxModel.setColor = { [unowned self] color in self.overlay?.drawing.setColor(color); self.syncToolbox() }
        toolboxModel.setAlpha = { [unowned self] value in self.overlay?.drawing.setAlpha(value); self.syncToolbox() }
        toolboxModel.setWidth = { [unowned self] value in self.overlay?.drawing.setWidth(value); self.syncToolbox() }
        toolboxModel.openColorPanel = { [unowned self] in self.openColorPanel() }
    }

    /// Spec: Cursor in recording — the toolbox toggle switches it live and the choice is kept for later recordings.
    private func toggleCursor() {
        let shows = !settings.values.recordCursor
        settings.values.recordCursor = shows
        toolboxModel.showsCursor = shows
        Task { await session.setShowsCursor(shows) }
    }

    private func syncToolbox() {
        guard let overlay else { return }
        let drawing = overlay.drawing
        func assign<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<ToolboxModel, T>, _ value: T) {
            if toolboxModel[keyPath: keyPath] != value { toolboxModel[keyPath: keyPath] = value }
        }
        assign(\.tool, drawing.tool)
        assign(\.baseColor, drawing.baseColor)
        assign(\.alpha, drawing.alpha)
        assign(\.width, drawing.width)
        assign(\.canUndo, overlay.document.canUndo)
        assign(\.canRedo, overlay.document.canRedo)
        assign(\.hasAnnotations, !overlay.document.isEmpty)
    }

    private func openColorPanel() {
        guard let drawing = overlay?.drawing else { return }
        let panel = NSColorPanel.shared
        panel.showsAlpha = true
        panel.color = NSColor(srgbRed: drawing.baseColor.red, green: drawing.baseColor.green, blue: drawing.baseColor.blue, alpha: drawing.alpha)
        panel.setTarget(colorPanelBridge)
        panel.setAction(#selector(ColorPanelBridge.colorChanged(_:)))
        panel.level = Levels.toolbox
        panel.orderFrontRegardless()
    }

    private func applyCustomColor(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return }
        overlay?.drawing.setColor(AnnotationColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent, alpha: srgb.alphaComponent))
        syncToolbox()
    }
}

/// Receives color changes from the shared `NSColorPanel` (target/action needs an Objective-C compatible object).
final class ColorPanelBridge: NSObject {
    private let onChange: (NSColor) -> Void

    init(onChange: @escaping (NSColor) -> Void) {
        self.onChange = onChange
    }

    @objc func colorChanged(_ sender: NSColorPanel) {
        onChange(sender.color)
    }
}
