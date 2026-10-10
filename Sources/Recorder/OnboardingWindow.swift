import AppKit
import Selection
import SwiftUI

/// Explains the Screen Recording permission, links to System Settings, and reports when it is granted.
@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?
    private let access: ScreenCaptureAccess
    private var pollTask: Task<Void, Never>?
    private let model = OnboardingModel()

    init(access: ScreenCaptureAccess) {
        self.access = access
    }

    func show() {
        if let window {
            window.orderFrontRegardless()
            window.makeKey()
            NSApp.activate()
            return
        }
        model.granted = false
        let hosting = NSHostingView(rootView: OnboardingView(model: model) {
            NSWorkspace.shared.open(PermissionService.settingsURL)
        })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Screen Recording Permission"
        window.contentView = hosting
        window.isReleasedWhenClosed = false
        window.center()
        window.orderFrontRegardless()
        window.makeKey()
        NSApp.activate()
        self.window = window
        startPolling()
    }

    /// Checks once a second until the permission is granted (spec: Grant detected).
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if await self.access.refresh() {
                    self.model.granted = true
                    return
                }
            }
        }
    }
}

final class OnboardingModel: ObservableObject {
    @Published var granted = false
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(
                model.granted ? "Permission granted" : "Screen Recording permission needed",
                systemImage: model.granted ? "checkmark.circle.fill" : "record.circle"
            )
            .font(.title3.weight(.semibold))
            .foregroundStyle(model.granted ? Color.green : Color.primary)
            Text(model.granted
                 ? "Recording is now available. You can close this window."
                 : "Recorder reads the contents of your screen, which macOS protects with the Screen Recording permission. Turn on Recorder in System Settings > Privacy & Security > Screen & System Audio Recording.")
                .fixedSize(horizontal: false, vertical: true)
            if !model.granted {
                Button("Open System Settings", action: openSettings)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
    }
}
