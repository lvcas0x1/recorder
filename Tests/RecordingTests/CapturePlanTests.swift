import XCTest
@testable import Recording

final class CapturePlanTests: XCTestCase {
    private let main = RecordingDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
    private let secondary = RecordingDisplay(id: 2, frame: CGRect(x: 1440, y: -200, width: 1920, height: 1080), scale: 1)
    private let options = CaptureOptions(box: CGSize(width: 1920, height: 1080), systemAudio: true, microphone: false, showsCursor: true)

    func testFullScreenRecordsWholeDisplayWithoutFrame() throws {
        let plan = try XCTUnwrap(CapturePlan.make(target: .fullScreen, display: secondary, options: options))
        XCTAssertEqual(plan.displayID, 2)
        XCTAssertEqual(plan.filter, .displayExcludingOwnWindowsExceptOverlay)
        XCTAssertEqual(plan.area, secondary.frame)
        XCTAssertEqual(plan.sourceRect, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(plan.outputSize, CGSize(width: 1920, height: 1080))
        XCTAssertFalse(plan.showsFrame)
    }

    func testWindowIncludesOnlyTargetAndOverlay() throws {
        let frame = CGRect(x: 100, y: 50, width: 800, height: 600)
        let plan = try XCTUnwrap(CapturePlan.make(target: .window(id: 42, frame: frame), display: main, options: options))
        XCTAssertEqual(plan.filter, .windowAndOverlay(windowID: 42))
        XCTAssertEqual(plan.sourceRect, frame)
        XCTAssertEqual(plan.outputSize, CGSize(width: 1440, height: 1080), "1600x1200 native fits 1080p as 1440x1080")
        XCTAssertTrue(plan.showsFrame)
    }

    func testAreaOnSecondaryDisplayIsDisplayRelative() throws {
        let area = CGRect(x: 1540, y: -100, width: 400, height: 300)
        let plan = try XCTUnwrap(CapturePlan.make(target: .area(area), display: secondary, options: options))
        XCTAssertEqual(plan.filter, .displayExcludingOwnWindowsExceptOverlay)
        XCTAssertEqual(plan.area, area)
        XCTAssertEqual(plan.sourceRect, CGRect(x: 100, y: 100, width: 400, height: 300))
        XCTAssertEqual(plan.outputSize, CGSize(width: 400, height: 300), "never upscaled")
        XCTAssertTrue(plan.showsFrame)
    }

    func testAreaIsClippedToDisplay() throws {
        let plan = try XCTUnwrap(CapturePlan.make(target: .area(CGRect(x: 1400, y: 800, width: 200, height: 200)), display: main, options: options))
        XCTAssertEqual(plan.area, CGRect(x: 1400, y: 800, width: 40, height: 100))
    }

    func testTargetOffDisplayGivesNoPlan() {
        XCTAssertNil(CapturePlan.make(target: .area(CGRect(x: 5000, y: 0, width: 10, height: 10)), display: main, options: options))
    }

    func testFlagsFollowOptions() throws {
        let custom = CaptureOptions(box: CGSize(width: 1280, height: 720), systemAudio: false, microphone: true, showsCursor: false)
        let plan = try XCTUnwrap(CapturePlan.make(target: .fullScreen, display: main, options: custom))
        XCTAssertFalse(plan.capturesAudio)
        XCTAssertTrue(plan.capturesMicrophone)
        XCTAssertFalse(plan.showsCursor)
        XCTAssertEqual(plan.outputSize, CGSize(width: 1152, height: 720))
        XCTAssertEqual(plan.framesPerSecond, 60)
    }
}
