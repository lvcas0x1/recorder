import AppKit
import Annotation
import DesignSystem
import Recording
import SwiftUI

/// Everything the toolbox shows or does. The coordinator keeps it in sync with the session and drawing state.
final class ToolboxModel: ObservableObject {
    @Published var isPaused = false
    @Published var isFinishing = false
    @Published var elapsed: TimeInterval = 0
    @Published var tool: DrawingTool?
    @Published var baseColor = AnnotationColor.palette[0]
    @Published var alpha: CGFloat = 1
    @Published var width: CGFloat = 3
    @Published var canUndo = false
    @Published var canRedo = false
    @Published var hasAnnotations = false
    @Published var showsCursor = true
    /// Whether the style row is shown above the main row (when the toolbox sits in the lower half of the screen).
    @Published var styleRowAbove = false

    var togglePause: () -> Void = {}
    var stop: () -> Void = {}
    var selectTool: (DrawingTool) -> Void = { _ in }
    var undo: () -> Void = {}
    var redo: () -> Void = {}
    var clearAll: () -> Void = {}
    var toggleCursor: () -> Void = {}
    var setColor: (AnnotationColor) -> Void = { _ in }
    var setAlpha: (CGFloat) -> Void = { _ in }
    var setWidth: (CGFloat) -> Void = { _ in }
    var openColorPanel: () -> Void = {}
}

/// Row 1: drag grip, the fixed recording controls (Pause/Resume, Stop, time), tools, history, cursor toggle.
/// Row 2 (while a drawing tool is active): color, width, alpha. Spec: Toolbox while recording, Pause/Resume and Stop.
struct ToolboxView: View {
    static let outerPadding: CGFloat = 14

    @ObservedObject var model: ToolboxModel

    private static let tools: [(tool: DrawingTool, symbol: String, label: String)] = [
        (.rectangle, "rectangle", "Rectangle"),
        (.line, "line.diagonal", "Line (Tab: arrow)"),
        (.arrow, "arrow.up.right", "Arrow (Tab: line)"),
        (.pencil, "pencil.tip", "Pencil"),
        (.marker, "highlighter", "Marker"),
        (.text, "textformat", "Text"),
        (.eraser, "eraser", "Eraser"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.styleRowAbove, model.tool?.usesStrokeStyle == true {
                StyleRow(model: model)
            }
            FloatingToolbar {
                WindowDragHandle()
                    .frame(width: 14, height: 28)
                    .overlay(Image(systemName: "line.3.horizontal").font(.system(size: 11)).foregroundStyle(.secondary).allowsHitTesting(false))
                ToolbarButton(
                    symbol: model.isPaused ? "play.fill" : "pause.fill",
                    label: model.isPaused ? "Resume" : "Pause",
                    isEnabled: !model.isFinishing,
                    action: model.togglePause
                )
                ToolbarButton(symbol: "stop.fill", label: "Stop", isEnabled: !model.isFinishing, action: model.stop)
                    .foregroundStyle(.red)
                Text(ElapsedTime.format(model.elapsed))
                    .monospacedDigit()
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(model.isPaused ? Color.secondary : Color.red)
                    .frame(width: 46)
                Divider().frame(height: 18)
                ForEach(Self.tools, id: \.tool) { entry in
                    ToolbarButton(symbol: entry.symbol, label: entry.label, isActive: model.tool == entry.tool) {
                        model.selectTool(entry.tool)
                    }
                }
                Divider().frame(height: 18)
                ToolbarButton(symbol: "arrow.uturn.backward", label: "Undo (\u{2318}Z)", isEnabled: model.canUndo, action: model.undo)
                ToolbarButton(symbol: "arrow.uturn.forward", label: "Redo (\u{2318}Y)", isEnabled: model.canRedo, action: model.redo)
                ToolbarButton(symbol: "trash", label: "Clear All (\u{21E7}\u{2318}Z)", isEnabled: model.hasAnnotations || model.canUndo, action: model.clearAll)
                Divider().frame(height: 18)
                ToolbarButton(
                    symbol: model.showsCursor ? "cursorarrow" : "cursorarrow.slash",
                    label: model.showsCursor ? "Cursor is recorded (click to hide)" : "Cursor is hidden (click to record)",
                    isActive: model.showsCursor,
                    isEnabled: !model.isFinishing,
                    action: model.toggleCursor
                )
            }
            if !model.styleRowAbove, model.tool?.usesStrokeStyle == true {
                StyleRow(model: model)
            }
        }
        .padding(Self.outerPadding)
        .fixedSize()
    }
}

private struct StyleRow: View {
    @ObservedObject var model: ToolboxModel

    var body: some View {
        FloatingToolbar {
            ForEach(Array(AnnotationColor.palette.enumerated()), id: \.offset) { _, color in
                Swatch(color: color, isSelected: color.sameHue(as: model.baseColor)) {
                    model.setColor(color.withAlpha(model.alpha))
                }
            }
            ToolbarButton(symbol: "paintpalette", label: "Custom Color\u{2026}", action: model.openColorPanel)
            Divider().frame(height: 18)
            if model.tool?.usesStrokeWidth == true {
                Image(systemName: "lineweight").foregroundStyle(.secondary).accessibilityHidden(true)
                // No `step`: a stepped Slider draws one tick per step, which turns the 0-255 alpha track into a dark band.
                Slider(
                    value: Binding(get: { Double(model.width) }, set: { model.setWidth(CGFloat($0.rounded())) }),
                    in: Double(DrawingController.widthRange.lowerBound)...Double(DrawingController.widthRange.upperBound)
                )
                .frame(width: 90)
                Text("\(Int(model.width))pt").monospacedDigit().font(.system(size: 11)).frame(width: 34, alignment: .leading)
            }
            Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary).accessibilityHidden(true)
            Slider(
                value: Binding(get: { Double(model.alpha * 255) }, set: { model.setAlpha(CGFloat($0.rounded()) / 255) }),
                in: 0...255
            )
            .frame(width: 90)
            Text("\(Int((model.alpha * 255).rounded()))").monospacedDigit().font(.system(size: 11)).frame(width: 26, alignment: .leading)
        }
    }
}

private struct Swatch: View {
    let color: AnnotationColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                .padding(3)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0))
        }
        .buttonStyle(.plain)
    }
}

extension AnnotationColor {
    /// Same red, green, and blue; alpha is ignored.
    func sameHue(as other: AnnotationColor) -> Bool {
        red == other.red && green == other.green && blue == other.blue
    }
}

/// Dragging this view moves its window (the toolbox can be placed anywhere; spec: Move toolbox).
private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    }
}

/// Fills the fixed-size toolbox panel and pins the toolbox to its top (style row below) or bottom (style row above),
/// so showing or hiding the style row never resizes or moves the window.
struct ToolboxContainer: View {
    @ObservedObject var model: ToolboxModel
    let size: CGSize

    var body: some View {
        ToolboxView(model: model)
            .frame(width: size.width, height: size.height, alignment: model.styleRowAbove ? .bottomLeading : .topLeading)
    }
}

/// The floating, non-activating window that hosts the toolbox. It belongs to this app, so the capture leaves it out.
///
/// The panel is sized once for the main row plus the style row and never resized: toggling the style row only redraws
/// inside it (no flicker). Its transparent part lets clicks through to the apps below.
final class ToolboxPanel: NSPanel {
    private let model: ToolboxModel
    /// The toolbox with the main row only, and the panel size (room for both rows).
    private let mainSize: CGSize
    private let panelSize: CGSize
    /// The recorded area (window and area modes); the style row avoids covering it when it can.
    private var avoid: CGRect?

    init(model: ToolboxModel) {
        self.model = model
        mainSize = Self.measure(tool: nil)
        let full = Self.measure(tool: .pencil)
        panelSize = CGSize(width: max(mainSize.width, full.width), height: full.height)
        super.init(contentRect: CGRect(origin: .zero, size: panelSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = Levels.toolbox
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = NSHostingView(rootView: ToolboxContainer(model: model, size: panelSize))
        NotificationCenter.default.addObserver(self, selector: #selector(didMove), name: NSWindow.didMoveNotification, object: self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Size of the toolbox for `tool` (a drawing tool adds the style row with the width slider, its widest form).
    private static func measure(tool: DrawingTool?) -> CGSize {
        let probe = ToolboxModel()
        probe.tool = tool
        let view = NSHostingView(rootView: ToolboxView(model: probe))
        view.layoutSubtreeIfNeeded()
        return view.fittingSize
    }

    /// The main row's frame in global top-left points.
    private var mainFrame: CGRect {
        let panel = ScreenSpace.topLeft(fromAppKit: frame)
        let y = model.styleRowAbove ? panel.maxY - mainSize.height : panel.minY
        return CGRect(x: panel.minX, y: y, width: mainSize.width, height: mainSize.height)
    }

    /// Which side the style row goes for a main row at `main`: a side that fits on the screen and does not cover the
    /// recorded area, preferring below; else a side that fits on the screen.
    private func styleRowAbove(for main: CGRect, visible: CGRect) -> Bool {
        let extra = panelSize.height - mainSize.height
        let below = CGRect(x: main.minX, y: main.maxY, width: panelSize.width, height: extra)
        let above = CGRect(x: main.minX, y: main.minY - extra, width: panelSize.width, height: extra)
        func fits(_ r: CGRect) -> Bool { r.minY >= visible.minY && r.maxY <= visible.maxY }
        func clear(_ r: CGRect) -> Bool { avoid.map { !$0.intersects(r) } ?? true }
        if fits(below) && clear(below) { return false }
        if fits(above) && clear(above) { return true }
        return !fits(below)
    }

    /// Puts the panel so the main row is at `main` (top-left points), with the style row on the side chosen by
    /// `styleRowAbove(for:visible:)`.
    private func setMainFrame(_ main: CGRect, visible: CGRect) {
        let above = styleRowAbove(for: main, visible: visible)
        if model.styleRowAbove != above { model.styleRowAbove = above }
        var x = main.minX
        x = min(max(x, visible.minX), visible.maxX - panelSize.width)
        let y = above ? main.maxY - panelSize.height : main.minY
        setFrame(ScreenSpace.appKit(fromTopLeft: CGRect(x: x, y: y, width: panelSize.width, height: panelSize.height)), display: true)
    }

    private var visibleFrame: CGRect {
        let main = mainFrame
        let screen = ScreenSpace.screen(containing: CGPoint(x: main.midX, y: main.midY))
        return ScreenSpace.topLeft(fromAppKit: screen.visibleFrame)
    }

    /// After the user drags the toolbox, choose the style row side again for the new position. Done only while the
    /// style row is hidden, so nothing visible moves.
    @objc private func didMove() {
        guard model.tool?.usesStrokeStyle != true else { return }
        let main = mainFrame
        let above = styleRowAbove(for: main, visible: visibleFrame)
        guard above != model.styleRowAbove else { return }
        setMainFrame(main, visible: visibleFrame)
    }

    /// Window and area modes: right-aligned with the area, below it when both rows fit there, else above it when both
    /// rows fit there (the style row then opens away from the area), else wherever the main row fits, else inside its
    /// bottom-right corner. Full screen mode: bottom center of the visible frame.
    func place(near area: CGRect, fullScreen: Bool) {
        let screen = ScreenSpace.screen(containing: CGPoint(x: area.midX, y: area.midY))
        let visible = ScreenSpace.topLeft(fromAppKit: screen.visibleFrame)
        let size = mainSize
        let inset = ToolboxView.outerPadding
        let extra = panelSize.height - mainSize.height
        avoid = fullScreen ? nil : area
        var origin: CGPoint
        if fullScreen {
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 8)
        } else {
            // The bar's visible right edge lines up with the area's right edge (the panel has `inset` padding).
            let rightAligned = area.maxX - size.width + inset
            let belowY = area.maxY - inset + 6
            let aboveY = area.minY - size.height + inset - 6
            if belowY + size.height + extra <= visible.maxY {
                origin = CGPoint(x: rightAligned, y: belowY)
            } else if aboveY - extra >= visible.minY {
                origin = CGPoint(x: rightAligned, y: aboveY)
            } else if belowY + size.height <= visible.maxY {
                origin = CGPoint(x: rightAligned, y: belowY)
            } else if aboveY >= visible.minY {
                origin = CGPoint(x: rightAligned, y: aboveY)
            } else {
                origin = CGPoint(x: area.maxX - size.width - 8, y: area.maxY - size.height - 8)
            }
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        setMainFrame(CGRect(origin: origin, size: size), visible: visible)
    }
}
