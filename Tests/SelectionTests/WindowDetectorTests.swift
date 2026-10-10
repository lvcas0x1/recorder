import XCTest
@testable import Selection

final class WindowDetectorTests: XCTestCase {
    private func dict(id: Int, pid: Int, layer: Int = 0, alpha: Double = 1, x: Int, y: Int, w: Int, h: Int) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: ["X": x, "Y": y, "Width": w, "Height": h],
        ]
    }

    func testFiltersOwnTransparentTinyAndDesktopWindows() {
        let raw = [
            dict(id: 1, pid: 99, x: 0, y: 0, w: 500, h: 400),          // own app
            dict(id: 2, pid: 10, alpha: 0, x: 0, y: 0, w: 500, h: 400), // transparent
            dict(id: 3, pid: 10, x: 0, y: 0, w: 5, h: 500),             // too narrow
            dict(id: 4, pid: 10, layer: -2_147_483_623, x: 0, y: 0, w: 1800, h: 1100), // desktop level
            dict(id: 5, pid: 10, x: 100, y: 100, w: 300, h: 200),       // kept
            dict(id: 6, pid: 11, layer: 25, x: 0, y: 0, w: 1800, h: 30), // menu bar kept
        ]
        let windows = WindowDetector.parse(raw, excludingPID: 99)
        XCTAssertEqual(windows.map(\.id), [5, 6])
        XCTAssertEqual(windows[0].frame, CGRect(x: 100, y: 100, width: 300, height: 200))
    }

    func testMalformedEntriesAreSkipped() {
        let raw: [[String: Any]] = [[kCGWindowNumber as String: 1], [:]]
        XCTAssertTrue(WindowDetector.parse(raw, excludingPID: 0).isEmpty)
    }

    func testFrontmostWindowWinsAtOverlap() {
        let front = WindowInfo(id: 1, ownerPID: 1, frame: CGRect(x: 100, y: 100, width: 200, height: 200), layer: 0)
        let back = WindowInfo(id: 2, ownerPID: 2, frame: CGRect(x: 0, y: 0, width: 500, height: 500), layer: 0)
        XCTAssertEqual(WindowDetector.hit(CGPoint(x: 150, y: 150), in: [front, back])?.id, 1)
        XCTAssertEqual(WindowDetector.hit(CGPoint(x: 400, y: 400), in: [front, back])?.id, 2)
        XCTAssertNil(WindowDetector.hit(CGPoint(x: 900, y: 900), in: [front, back]))
    }
}
