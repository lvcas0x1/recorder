import AppKit
import Settings
import SwiftUI

@MainActor
final class PreferencesWindowController {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let hotkeys: HotkeyManager

    init(settings: SettingsStore, hotkeys: HotkeyManager) {
        self.settings = settings
        self.hotkeys = hotkeys
    }

    func show() {
        if window == nil {
            let hosting = NSHostingView(rootView: PreferencesView(settings: settings, hotkeys: hotkeys))
            hosting.layoutSubtreeIfNeeded()
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Recorder Preferences"
            window.contentView = hosting
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // Activation can be declined (cooperative activation), so bring the window up regardless.
        window?.orderFrontRegardless()
        window?.makeKey()
        NSApp.activate()
    }
}

/// Spec app-shell: Preferences, Change shortcuts, Remove shortcuts.
struct PreferencesView: View {
    @ObservedObject var settings: SettingsStore
    let hotkeys: HotkeyManager
    @State private var revision = 0
    @State private var errors: [HotkeyAction: String] = [:]

    var body: some View {
        Form {
            Section("Shortcuts") {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        HStack(spacing: 6) {
                            HotkeyRecorder(combo: hotkeys.store.combo(for: action)) { combo in record(combo, for: action) }
                                .frame(width: 130, height: 24)
                            Button {
                                hotkeys.unbind(action)
                                errors[action] = nil
                                revision += 1
                            } label: { Image(systemName: "xmark.circle") }
                                .buttonStyle(.borderless)
                                .help("Remove shortcut")
                                .disabled(hotkeys.store.combo(for: action) == nil)
                            Button("Restore Default") { restoreDefault(action) }
                                .disabled(hotkeys.store.combo(for: action) == KeyCombo.defaults[action])
                        }
                        .id(revision)
                    }
                    if let message = errors[action] {
                        Text(message).foregroundStyle(.red).font(.callout)
                    }
                }
                Text("Press a shortcut again while recording to stop.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Recording") {
                Picker("Resolution", selection: $settings.values.resolution) {
                    ForEach(Resolution.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Record cursor", isOn: $settings.values.recordCursor)
                Toggle("System audio", isOn: $settings.values.systemAudio)
                Toggle("Microphone", isOn: $settings.values.microphone)
                FolderRow(title: "Save to", path: $settings.values.outputFolder)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
    }

    private func record(_ combo: KeyCombo, for action: HotkeyAction) {
        defer { revision += 1 }
        guard combo.hasRequiredModifier else {
            errors[action] = "Include Control, Option, or Command."
            return
        }
        do {
            try hotkeys.rebind(action, to: combo)
            errors[action] = nil
        } catch {
            errors[action] = "Could not register \(combo.displayString). The previous shortcut is still active."
        }
    }

    private func restoreDefault(_ action: HotkeyAction) {
        defer { revision += 1 }
        do {
            try hotkeys.restoreDefault(action)
            errors[action] = nil
        } catch {
            errors[action] = "Could not register the default shortcut."
        }
    }
}

private struct FolderRow: View {
    let title: String
    @Binding var path: String

    var body: some View {
        LabeledContent(title) {
            HStack {
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Button("Choose\u{2026}") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url { path = url.path }
                }
            }
        }
    }
}
