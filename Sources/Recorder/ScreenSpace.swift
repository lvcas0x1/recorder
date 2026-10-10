import AppKit
import Recording

/// Conversions between AppKit screen coordinates (origin at the bottom-left of the main display, y up) and the
/// global top-left points used by the recording and annotation code.
enum ScreenSpace {
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func topLeft(fromAppKit rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKit(fromTopLeft rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func topLeft(fromAppKit point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    static var mouseLocation: CGPoint { topLeft(fromAppKit: NSEvent.mouseLocation) }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    /// The screen containing `point` (global top-left), or the main screen.
    static func screen(containing point: CGPoint) -> NSScreen {
        NSScreen.screens.first { topLeft(fromAppKit: $0.frame).contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    static func recordingDisplay(for screen: NSScreen) -> RecordingDisplay {
        RecordingDisplay(id: displayID(of: screen), frame: topLeft(fromAppKit: screen.frame), scale: screen.backingScaleFactor)
    }
}

/// A transparent, borderless panel that never takes focus and lets clicks through; used for the frame and editor chrome.
class PassivePanel: NSPanel {
    init(frame: CGRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum Levels {
    /// Annotation overlay and frame: above normal app windows.
    static let overlay = NSWindow.Level.floating
    /// Editor chrome just above the overlay.
    static let chrome = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
    /// Toolbox and its color panel above everything the recorder draws.
    static let toolbox = NSWindow.Level.statusBar
    /// The selection overlay covers everything while the user picks a target.
    static let selection = NSWindow.Level.screenSaver
}
