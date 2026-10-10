import XCTest
@testable import Recording

/// Spec screen-recording, Requirement: Output resolution.
final class OutputSizeTests: XCTestCase {
    private let p720 = CGSize(width: 1280, height: 720)
    private let p1080 = CGSize(width: 1920, height: 1080)
    private let p2160 = CGSize(width: 3840, height: 2160)

    func testSixteenByNineDisplayAt1080p() {
        XCTAssertEqual(OutputSize.fit(nativePixels: CGSize(width: 2880, height: 1620), box: p1080), CGSize(width: 1920, height: 1080))
    }

    func testNonSixteenByNineAreaAt720p() {
        XCTAssertEqual(OutputSize.fit(nativePixels: CGSize(width: 1600, height: 1200), box: p720), CGSize(width: 960, height: 720))
    }

    func testNoUpscaling() {
        XCTAssertEqual(OutputSize.fit(nativePixels: CGSize(width: 1000, height: 500), box: p2160), CGSize(width: 1000, height: 500))
    }

    func testOddNativeSizeGivesEvenOutput() {
        let size = OutputSize.fit(nativePixels: CGSize(width: 1001, height: 777), box: p2160)
        XCTAssertEqual(size, CGSize(width: 1000, height: 776))
    }

    func testOddScaledSizeGivesEvenOutput() {
        // 3600x2338 at 1080p: factor = min(1920/3600, 1080/2338) = 0.46193 -> 1662.96 x 1080 -> 1662 x 1080.
        let size = OutputSize.fit(nativePixels: CGSize(width: 3600, height: 2338), box: p1080)
        XCTAssertEqual(size.height, 1080)
        XCTAssertEqual(size.width.truncatingRemainder(dividingBy: 2), 0)
        XCTAssertLessThanOrEqual(size.width, 1920)
    }

    func testTallAreaIsLimitedByHeight() {
        XCTAssertEqual(OutputSize.fit(nativePixels: CGSize(width: 1000, height: 4000), box: p1080), CGSize(width: 270, height: 1080))
    }

    func testDegenerateSizes() {
        XCTAssertEqual(OutputSize.fit(nativePixels: .zero, box: p1080), .zero)
        XCTAssertEqual(OutputSize.fit(nativePixels: CGSize(width: 1, height: 1), box: p1080), CGSize(width: 2, height: 2))
    }
}
