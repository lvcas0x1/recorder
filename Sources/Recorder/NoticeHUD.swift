import AppKit
import SwiftUI

/// A small panel under the menu bar for short notices: the saved file (with Show in Finder), a microphone notice, or
/// an error. It closes itself after a few seconds (design D8; no notification permission is needed).
@MainActor
final class NoticeHUD {
    static let lifetime: TimeInterval = 5

    private var panel: NSPanel?
    private var closeTask: Task<Void, Never>?

    func showSaved(_ url: URL) {
        show(Notice(
            symbol: "checkmark.circle.fill", tint: .green, title: "Recording saved", detail: url.lastPathComponent,
            actionTitle: "Show in Finder", action: { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        ))
    }

    func showMessage(_ title: String, detail: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        show(Notice(symbol: "exclamationmark.triangle.fill", tint: .orange, title: title, detail: detail, actionTitle: actionTitle, action: action))
    }

    func showError(_ title: String, detail: String) {
        show(Notice(symbol: "xmark.octagon.fill", tint: .red, title: title, detail: detail, actionTitle: nil, action: nil))
    }

    private func show(_ notice: Notice) {
        close()
        let view = NoticeView(notice: notice) { [weak self] in
            notice.action?()
            self?.close()
        }
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = Levels.toolbox
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = hosting
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 8))
        panel.orderFrontRegardless()
        self.panel = panel
        closeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.lifetime * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    func close() {
        closeTask?.cancel()
        closeTask = nil
        panel?.orderOut(nil)
        panel = nil
    }

    var isVisible: Bool { panel != nil }
}

private struct Notice {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let actionTitle: String?
    let action: (() -> Void)?
}

private struct NoticeView: View {
    let notice: Notice
    let perform: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: notice.symbol).foregroundStyle(notice.tint).font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title).font(.system(size: 13, weight: .semibold))
                Text(notice.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).frame(maxWidth: 280, alignment: .leading)
            }
            if let actionTitle = notice.actionTitle {
                Button(actionTitle, action: perform)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
        .padding(10)
        .fixedSize()
    }
}
