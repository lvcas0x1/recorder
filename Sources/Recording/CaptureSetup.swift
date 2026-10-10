import AppKit
import ScreenCaptureKit

public enum CaptureSetupError: Error, Equatable {
    case displayNotFound
    case windowNotFound
    case overlayNotFound
}

/// Turns a `CapturePlan` into ScreenCaptureKit objects. The overlay window must already be on screen, so it can be
/// found in the shareable content and included in the capture (design D3).
public enum CaptureSetup {
    @MainActor
    public static func make(plan: CapturePlan, overlayWindowNumber: Int) async throws -> (SCContentFilter, SCStreamConfiguration) {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == plan.displayID }) else {
            throw CaptureSetupError.displayNotFound
        }
        guard let overlay = content.windows.first(where: { $0.windowID == CGWindowID(overlayWindowNumber) }) else {
            throw CaptureSetupError.overlayNotFound
        }
        let filter: SCContentFilter
        switch plan.filter {
        case .displayExcludingOwnWindowsExceptOverlay:
            let pid = ProcessInfo.processInfo.processIdentifier
            let me = content.applications.filter { $0.processID == pid }
            filter = SCContentFilter(display: display, excludingApplications: me, exceptingWindows: [overlay])
        case .windowAndOverlay(let windowID):
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureSetupError.windowNotFound
            }
            filter = SCContentFilter(display: display, including: [window, overlay])
        }

        let configuration = SCStreamConfiguration()
        configuration.width = Int(plan.outputSize.width)
        configuration.height = Int(plan.outputSize.height)
        configuration.sourceRect = plan.sourceRect
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(plan.framesPerSecond))
        configuration.showsCursor = plan.showsCursor
        configuration.capturesAudio = plan.capturesAudio
        configuration.excludesCurrentProcessAudio = true
        configuration.captureMicrophone = plan.capturesMicrophone
        configuration.microphoneCaptureDeviceID = nil
        return (filter, configuration)
    }
}
