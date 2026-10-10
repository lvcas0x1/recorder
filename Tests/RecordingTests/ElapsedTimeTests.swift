import XCTest
@testable import Recording

final class ElapsedTimeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    func testRunningTimeExcludesPauses() {
        var elapsed = ElapsedTime()
        elapsed.resume(at: t0)
        elapsed.pause(at: t0 + 20)
        XCTAssertEqual(elapsed.value(at: t0 + 50), 20, "time does not advance while paused")
        elapsed.resume(at: t0 + 50)
        XCTAssertEqual(elapsed.value(at: t0 + 55), 25)
    }

    func testMeasuredDurationWinsOverWallClock() {
        var elapsed = ElapsedTime()
        elapsed.resume(at: t0)
        elapsed.pause(at: t0 + 10, measured: 9.8)
        XCTAssertEqual(elapsed.completed, 9.8)
    }

    func testDoubleResumeAndPauseAreIgnored() {
        var elapsed = ElapsedTime()
        elapsed.resume(at: t0)
        elapsed.resume(at: t0 + 5)
        elapsed.pause(at: t0 + 10)
        elapsed.pause(at: t0 + 20)
        XCTAssertEqual(elapsed.completed, 10)
        XCTAssertFalse(elapsed.isRunning)
    }

    func testFormat() {
        XCTAssertEqual(ElapsedTime.format(75), "01:15")
        XCTAssertEqual(ElapsedTime.format(20.9), "00:20")
        XCTAssertEqual(ElapsedTime.format(6000), "100:00")
    }
}
