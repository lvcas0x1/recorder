import AVFoundation
import XCTest
@testable import Recording

private final class FakeMicrophone: MicrophoneAuthorizing {
    var status: AVAuthorizationStatus
    var answer: Bool
    private(set) var requests = 0

    init(status: AVAuthorizationStatus, answer: Bool = false) {
        self.status = status
        self.answer = answer
    }

    func request() async -> Bool {
        requests += 1
        return answer
    }
}

final class MicrophonePermissionTests: XCTestCase {
    func testNotWantedNeverAsks() async {
        let mic = FakeMicrophone(status: .notDetermined)
        let decision = await MicrophonePermission.decide(wanted: false, provider: mic)
        XCTAssertEqual(decision, .init(capturesMicrophone: false, showDeniedNotice: false))
        XCTAssertEqual(mic.requests, 0)
    }

    func testAuthorizedRecordsMicrophone() async {
        let decision = await MicrophonePermission.decide(wanted: true, provider: FakeMicrophone(status: .authorized))
        XCTAssertEqual(decision, .init(capturesMicrophone: true, showDeniedNotice: false))
    }

    func testUndeterminedAsksOnce() async {
        let granted = FakeMicrophone(status: .notDetermined, answer: true)
        let yes = await MicrophonePermission.decide(wanted: true, provider: granted)
        XCTAssertEqual(yes.capturesMicrophone, true)
        XCTAssertEqual(granted.requests, 1)

        let refused = FakeMicrophone(status: .notDetermined, answer: false)
        let no = await MicrophonePermission.decide(wanted: true, provider: refused)
        XCTAssertEqual(no, .init(capturesMicrophone: false, showDeniedNotice: true))
    }

    func testDeniedRecordsWithoutMicrophoneAndNotifies() async {
        for status in [AVAuthorizationStatus.denied, .restricted] {
            let mic = FakeMicrophone(status: status)
            let decision = await MicrophonePermission.decide(wanted: true, provider: mic)
            XCTAssertEqual(decision, .init(capturesMicrophone: false, showDeniedNotice: true))
            XCTAssertEqual(mic.requests, 0)
        }
    }
}
