import CoreGraphics
import Foundation

public protocol ScreenCapturePermissionProviding {
    /// Current authorization, without prompting.
    var isGranted: Bool { get }
    /// Prompts if undetermined. A previously denied process is not re-prompted.
    @discardableResult func request() -> Bool
}

public struct SystemScreenCapturePermission: ScreenCapturePermissionProviding {
    public init() {}
    public var isGranted: Bool { CGPreflightScreenCaptureAccess() }
    @discardableResult public func request() -> Bool { CGRequestScreenCaptureAccess() }
}

public final class PermissionService {
    public static let settingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!

    private let provider: ScreenCapturePermissionProviding

    public init(provider: ScreenCapturePermissionProviding = SystemScreenCapturePermission()) {
        self.provider = provider
    }

    public var isGranted: Bool { provider.isGranted }

    /// Runs `action` only when permission is granted; otherwise runs `onDenied`. Never starts a capture without permission.
    public func guarded(_ action: () -> Void, onDenied: () -> Void) {
        if provider.isGranted { action() } else { onDenied() }
    }

    @discardableResult public func requestAccess() -> Bool { provider.request() }
}

/// Polls permission state until it becomes granted, then calls `onGranted` once.
public final class PermissionMonitor {
    private let provider: ScreenCapturePermissionProviding
    private let interval: TimeInterval
    private var timer: Timer?

    public init(provider: ScreenCapturePermissionProviding = SystemScreenCapturePermission(), interval: TimeInterval = 1) {
        self.provider = provider
        self.interval = interval
    }

    public func start(onGranted: @escaping () -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self, self.provider.isGranted else { return }
            self.stop()
            onGranted()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}
