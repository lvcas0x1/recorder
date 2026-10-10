import AppKit
import Recording
import Selection
import Settings
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "dev.lvcas0x1.recorder", category: "app")
    private var statusItem: NSStatusItem?
    private let settings = SettingsStore()
    private let hotkeys = HotkeyManager(store: HotkeyStore())
    private let access = ScreenCaptureAccess()
    private lazy var onboarding = OnboardingWindowController(access: access)
    private let notices = NoticeHUD()
    private lazy var coordinator = RecordingCoordinator(settings: settings, notices: notices)
    private lazy var preferences = PreferencesWindowController(settings: settings, hotkeys: hotkeys)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        statusItem = item
        coordinator.onIndicatorChange = { [weak self] in self?.refreshIndicator() }
        refreshIndicator()

        for action in HotkeyAction.allCases {
            hotkeys.setHandler(for: action) { [weak self] in self?.perform(action.mode) }
        }
        let failures = hotkeys.start()
        for (action, error) in failures {
            log.error("hotkey \(action.rawValue, privacy: .public) registration failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Menu bar

    /// Spec: Recording indicator. Idle: the app icon. Recording: red dot and time. Paused: pause icon and frozen time.
    private func refreshIndicator() {
        guard let button = statusItem?.button else { return }
        let state = coordinator.state
        let time = ElapsedTime.format(coordinator.elapsed)
        let symbol: String
        var title = ""
        var tint: NSColor?
        switch state {
        case .idle, .selecting:
            symbol = "record.circle"
        case .starting:
            symbol = "record.circle"
            title = " …"
        case .recording:
            symbol = "record.circle.fill"
            title = " \(time)"
            tint = .systemRed
        case .paused:
            symbol = "pause.circle.fill"
            title = " \(time)"
        case .finishing:
            symbol = "hourglass"
            title = " Saving…"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Recorder")
        image?.isTemplate = tint == nil
        button.image = tint.flatMap { image?.withSymbolConfiguration(.init(paletteColors: [$0])) } ?? image
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.attributedTitle = NSAttributedString(string: title, attributes: [.font: font])
        button.toolTip = state == .recording || state == .paused ? "Click to stop recording" : "Recorder"
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        switch coordinator.state {
        case .recording, .paused:
            coordinator.stop()
        case .idle:
            showMenu()
        case .selecting, .starting, .finishing:
            break
        }
    }

    private func showMenu() {
        guard let item = statusItem else { return }
        item.menu = buildMenu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        for action in HotkeyAction.allCases {
            let entry = NSMenuItem(title: action.title, action: #selector(recordChosen(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = action.rawValue
            // Display only: the shortcut is global; a removed shortcut shows nothing.
            if let combo = hotkeys.store.combo(for: action) {
                entry.title = "\(action.title)    \(combo.displayString)"
            }
            menu.addItem(entry)
        }
        menu.addItem(.separator())

        let resolution = NSMenuItem(title: "Resolution", action: nil, keyEquivalent: "")
        let resolutions = NSMenu()
        for value in Resolution.allCases {
            let entry = NSMenuItem(title: value.title, action: #selector(resolutionChosen(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = value.rawValue
            entry.state = settings.values.resolution == value ? .on : .off
            resolutions.addItem(entry)
        }
        resolution.submenu = resolutions
        menu.addItem(resolution)
        addToggle("Record Cursor", \.recordCursor, to: menu)
        addToggle("System Audio", \.systemAudio, to: menu)
        addToggle("Microphone", \.microphone, to: menu)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open Recordings Folder", action: #selector(openFolder), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let prefs = NSMenuItem(title: "Preferences\u{2026}", action: #selector(showPreferences), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Recorder", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func addToggle(_ title: String, _ keyPath: WritableKeyPath<SettingsValues, Bool>, to menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: #selector(toggleChosen(_:)), keyEquivalent: "")
        entry.target = self
        entry.representedObject = keyPath
        entry.state = settings.values[keyPath: keyPath] ? .on : .off
        menu.addItem(entry)
    }

    @objc private func recordChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = HotkeyAction(rawValue: raw) else { return }
        perform(action.mode)
    }

    @objc private func resolutionChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let value = Resolution(rawValue: raw) else { return }
        settings.values.resolution = value
    }

    @objc private func toggleChosen(_ sender: NSMenuItem) {
        guard let keyPath = sender.representedObject as? WritableKeyPath<SettingsValues, Bool> else { return }
        settings.values[keyPath: keyPath].toggle()
    }

    @objc private func openFolder() {
        let folder = settings.outputFolderURL
        do {
            try OutputFiles.prepareFolder(folder)
            NSWorkspace.shared.open(folder)
        } catch {
            notices.showError("Cannot open the recordings folder", detail: (folder.path as NSString).abbreviatingWithTildeInPath)
        }
    }

    @objc private func showPreferences() { preferences.show() }

    // MARK: Commands

    /// Starting needs Screen Recording permission (spec: permission onboarding); stopping a recording never does.
    private func perform(_ mode: RecordingMode) {
        log.notice("command: \(mode.rawValue, privacy: .public) state: \(String(describing: self.coordinator.state), privacy: .public)")
        guard coordinator.state == .idle, !access.isGranted else {
            coordinator.request(mode)
            return
        }
        Task {
            // The preflight answer can be stale, so ask ScreenCaptureKit before blocking.
            if await access.refresh() {
                coordinator.request(mode)
            } else {
                log.notice("blocked: Screen Recording permission missing")
                access.request()
                onboarding.show()
            }
        }
    }
}

extension HotkeyAction {
    var mode: RecordingMode {
        switch self {
        case .fullScreen: .fullScreen
        case .window: .window
        case .area: .area
        }
    }
}
