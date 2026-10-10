import CoreGraphics
import Foundation

/// What the user chose to record. Rectangles are global top-left points (origin at the main display's top-left).
public enum RecordingTarget: Equatable {
    case fullScreen
    case window(id: CGWindowID, frame: CGRect)
    case area(CGRect)
}

/// The display a recording runs on, in global top-left points.
public struct RecordingDisplay: Equatable {
    public let id: CGDirectDisplayID
    public let frame: CGRect
    /// Pixels per point.
    public let scale: CGFloat

    public init(id: CGDirectDisplayID, frame: CGRect, scale: CGFloat) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

public struct CaptureOptions: Equatable {
    public var box: CGSize
    public var systemAudio: Bool
    public var microphone: Bool
    public var showsCursor: Bool

    public init(box: CGSize, systemAudio: Bool, microphone: Bool, showsCursor: Bool) {
        self.box = box
        self.systemAudio = systemAudio
        self.microphone = microphone
        self.showsCursor = showsCursor
    }
}

/// Everything needed to build the stream for one recording (design D2/D3). Pure data; see `CaptureSetup` for the
/// ScreenCaptureKit objects.
public struct CapturePlan: Equatable {
    public enum Filter: Equatable {
        /// The whole display without this app's windows, except the annotation overlay.
        case displayExcludingOwnWindowsExceptOverlay
        /// Only the target window and the annotation overlay.
        case windowAndOverlay(windowID: CGWindowID)
    }

    public let displayID: CGDirectDisplayID
    public let filter: Filter
    /// The recorded area in global top-left points (where the overlay and frame go).
    public let area: CGRect
    /// The recorded area relative to the display's top-left, in points (`SCStreamConfiguration.sourceRect`).
    public let sourceRect: CGRect
    /// Output video size in pixels.
    public let outputSize: CGSize
    /// Whether a 1 pt frame is drawn around the area (window and area modes only).
    public let showsFrame: Bool
    public let capturesAudio: Bool
    public let capturesMicrophone: Bool
    public let showsCursor: Bool
    public let framesPerSecond: Int

    public static let framesPerSecond = 60

    /// `nil` when the target does not overlap the display.
    public static func make(target: RecordingTarget, display: RecordingDisplay, options: CaptureOptions) -> CapturePlan? {
        let area: CGRect
        let filter: Filter
        switch target {
        case .fullScreen:
            area = display.frame
            filter = .displayExcludingOwnWindowsExceptOverlay
        case .window(let id, let frame):
            area = frame.intersection(display.frame)
            filter = .windowAndOverlay(windowID: id)
        case .area(let rect):
            area = rect.standardized.intersection(display.frame)
            filter = .displayExcludingOwnWindowsExceptOverlay
        }
        guard !area.isNull, area.width >= 1, area.height >= 1 else { return nil }
        let native = CGSize(width: (area.width * display.scale).rounded(), height: (area.height * display.scale).rounded())
        return CapturePlan(
            displayID: display.id,
            filter: filter,
            area: area,
            sourceRect: area.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY),
            outputSize: OutputSize.fit(nativePixels: native, box: options.box),
            showsFrame: target != .fullScreen,
            capturesAudio: options.systemAudio,
            capturesMicrophone: options.microphone,
            showsCursor: options.showsCursor,
            framesPerSecond: framesPerSecond
        )
    }
}
