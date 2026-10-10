import CoreGraphics
import ScreenCaptureKit

/// Screen Recording permission as seen by this process.
///
/// `CGPreflightScreenCaptureAccess()` keeps returning its first answer for the life of the process (observed on
/// macOS 27: after a grant in System Settings, the running app stopped asking tccd). So a grant made while the app runs
/// is detected with a live ScreenCaptureKit query instead, and remembered.
@MainActor
final class ScreenCaptureAccess {
    private var grantedLive = false

    var isGranted: Bool { grantedLive || CGPreflightScreenCaptureAccess() }

    /// Asks ScreenCaptureKit directly; listing shareable content succeeds only with the permission.
    @discardableResult
    func refresh() async -> Bool {
        if isGranted { return true }
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            grantedLive = true
        } catch {
            grantedLive = false
        }
        return grantedLive
    }

    /// Prompts if undetermined (the system shows its dialog once).
    func request() { CGRequestScreenCaptureAccess() }
}
