import XCTest
@testable import Selection

final class GeometryTests: XCTestCase {
    private let retina = DisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1800, height: 1169), scale: 2)

    func testRetinaCropIsPointsTimesScale() {
        let crop = Geometry.cropRect(selection: CGRect(x: 10, y: 20, width: 200, height: 100), in: retina)
        XCTAssertEqual(crop, CGRect(x: 20, y: 40, width: 400, height: 200))
    }

    func testSelectionOutsideDisplayHasNoCrop() {
        XCTAssertNil(Geometry.cropRect(selection: CGRect(x: 2000, y: 0, width: 50, height: 50), in: retina))
    }

    func testSelectionIsClippedToDisplay() {
        let crop = Geometry.cropRect(selection: CGRect(x: 1700, y: 1100, width: 300, height: 300), in: retina)
        XCTAssertEqual(crop, CGRect(x: 3400, y: 2200, width: 200, height: 138))
    }

    func testFractionalPointsRoundToSharedPixelEdges() {
        let display = DisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 100, height: 100), scale: 2)
        let crop = try! XCTUnwrap(Geometry.cropRect(selection: CGRect(x: 0.25, y: 0, width: 10.5, height: 10), in: display))
        // minX 0.5 -> 1 (rounded), maxX 21.5 -> 22: width 21, no drift from independent rounding of width.
        XCTAssertEqual(crop.minX, 1)
        XCTAssertEqual(crop.maxX, 22)
    }

    func testAppKitToTopLeftConversion() {
        let rect = Geometry.topLeftRect(fromAppKit: CGRect(x: 100, y: 50, width: 200, height: 100), primaryDisplayHeight: 1000)
        XCTAssertEqual(rect, CGRect(x: 100, y: 850, width: 200, height: 100))
    }
}
