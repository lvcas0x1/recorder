import AVFoundation

public protocol MicrophoneAuthorizing {
    var status: AVAuthorizationStatus { get }
    func request() async -> Bool
}

public struct SystemMicrophoneAuthorization: MicrophoneAuthorizing {
    public init() {}
    public var status: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .audio) }
    public func request() async -> Bool { await AVCaptureDevice.requestAccess(for: .audio) }
}

/// Decides whether the microphone can be recorded (design D8). Asks once when undetermined; when access is denied the
/// recording goes ahead without the microphone and the caller shows a notice.
public enum MicrophonePermission {
    public struct Decision: Equatable {
        public let capturesMicrophone: Bool
        /// The user wanted the microphone but access is denied or restricted.
        public let showDeniedNotice: Bool
    }

    public static func decide(wanted: Bool, provider: MicrophoneAuthorizing = SystemMicrophoneAuthorization()) async -> Decision {
        guard wanted else { return Decision(capturesMicrophone: false, showDeniedNotice: false) }
        switch provider.status {
        case .authorized:
            return Decision(capturesMicrophone: true, showDeniedNotice: false)
        case .notDetermined:
            let granted = await provider.request()
            return Decision(capturesMicrophone: granted, showDeniedNotice: !granted)
        default:
            return Decision(capturesMicrophone: false, showDeniedNotice: true)
        }
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
}
