import AppKit

/// The 1 pt frame drawn just outside the recorded area in window and area modes. It belongs to this app, so the
/// capture filter leaves it out of the video (design D3/D5).
final class RecordingFrame {
    static let lineWidth: CGFloat = 1
    private let panel: PassivePanel

    /// - Parameter area: The recorded area in global top-left points.
    init(area: CGRect) {
        let outer = area.insetBy(dx: -Self.lineWidth, dy: -Self.lineWidth)
        panel = PassivePanel(frame: ScreenSpace.appKit(fromTopLeft: outer), level: Levels.overlay)
        panel.contentView = FrameView(frame: CGRect(origin: .zero, size: outer.size))
    }

    func show() { panel.orderFrontRegardless() }
    func close() { panel.orderOut(nil) }

    private final class FrameView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemRed.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: RecordingFrame.lineWidth / 2, dy: RecordingFrame.lineWidth / 2))
            path.lineWidth = RecordingFrame.lineWidth
            path.stroke()
        }
    }
}
