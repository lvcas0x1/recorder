import XCTest
@testable import Selection

final class SelectionModelTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)

    private func drag(_ model: SelectionModel, from a: CGPoint, to b: CGPoint) {
        model.mouseDown(at: a)
        model.mouseDragged(to: b)
        model.mouseUp(at: b)
    }

    func testDragInAnyDirectionNormalizesRect() {
        for (a, b) in [
            (CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 250)),
            (CGPoint(x: 300, y: 250), CGPoint(x: 100, y: 100)),
            (CGPoint(x: 100, y: 250), CGPoint(x: 300, y: 100)),
            (CGPoint(x: 300, y: 100), CGPoint(x: 100, y: 250)),
        ] {
            let model = SelectionModel(bounds: bounds)
            drag(model, from: a, to: b)
            XCTAssertEqual(model.rect, CGRect(x: 100, y: 100, width: 200, height: 150))
        }
    }

    func testClickWithoutDragCreatesNoSelectionAndReportsClick() {
        let model = SelectionModel(bounds: bounds)
        model.mouseDown(at: CGPoint(x: 50, y: 50))
        model.mouseDragged(to: CGPoint(x: 51, y: 51))
        XCTAssertTrue(model.mouseUp(at: CGPoint(x: 51, y: 51)))
        XCTAssertNil(model.rect)
    }

    func testDragIsClampedToBounds() {
        let model = SelectionModel(bounds: bounds)
        drag(model, from: CGPoint(x: 900, y: 700), to: CGPoint(x: 1500, y: 1200))
        XCTAssertEqual(model.rect, CGRect(x: 900, y: 700, width: 100, height: 100))
    }

    func testHitTest() {
        let model = SelectionModel(bounds: bounds)
        model.setRect(CGRect(x: 100, y: 100, width: 200, height: 100))
        XCTAssertEqual(model.hitTest(CGPoint(x: 101, y: 99)), .handle(.topLeft))
        XCTAssertEqual(model.hitTest(CGPoint(x: 200, y: 100)), .handle(.top))
        XCTAssertEqual(model.hitTest(CGPoint(x: 300, y: 200)), .handle(.bottomRight))
        XCTAssertEqual(model.hitTest(CGPoint(x: 150, y: 150)), .inside)
        XCTAssertEqual(model.hitTest(CGPoint(x: 600, y: 600)), .none)
    }

    func testResizeEachHandleMovesOnlyItsEdges() {
        let start = CGRect(x: 100, y: 100, width: 200, height: 100)
        let cases: [(ResizeHandle, CGPoint, CGRect)] = [
            (.topLeft, CGPoint(x: 80, y: 90), CGRect(x: 80, y: 90, width: 220, height: 110)),
            (.top, CGPoint(x: 999, y: 60), CGRect(x: 100, y: 60, width: 200, height: 140)),
            (.topRight, CGPoint(x: 320, y: 90), CGRect(x: 100, y: 90, width: 220, height: 110)),
            (.right, CGPoint(x: 350, y: 999), CGRect(x: 100, y: 100, width: 250, height: 100)),
            (.bottomRight, CGPoint(x: 350, y: 250), CGRect(x: 100, y: 100, width: 250, height: 150)),
            (.bottom, CGPoint(x: 0, y: 240), CGRect(x: 100, y: 100, width: 200, height: 140)),
            (.bottomLeft, CGPoint(x: 70, y: 240), CGRect(x: 70, y: 100, width: 230, height: 140)),
            (.left, CGPoint(x: 60, y: 0), CGRect(x: 60, y: 100, width: 240, height: 100)),
        ]
        for (handle, target, expected) in cases {
            let model = SelectionModel(bounds: bounds)
            model.setRect(start)
            model.mouseDown(at: handle.position(on: start))
            model.mouseDragged(to: target)
            model.mouseUp(at: target)
            XCTAssertEqual(model.rect, expected, "\(handle)")
        }
    }

    func testResizePastOppositeEdgeFlipsInsteadOfGoingNegative() {
        let model = SelectionModel(bounds: bounds)
        model.setRect(CGRect(x: 100, y: 100, width: 200, height: 100))
        model.mouseDown(at: CGPoint(x: 300, y: 150)) // right handle
        model.mouseDragged(to: CGPoint(x: 50, y: 150))
        XCTAssertEqual(model.rect, CGRect(x: 50, y: 100, width: 50, height: 100))
    }

    func testMoveKeepsSizeAndStaysInBounds() {
        let model = SelectionModel(bounds: bounds)
        model.setRect(CGRect(x: 100, y: 100, width: 200, height: 100))
        model.mouseDown(at: CGPoint(x: 200, y: 150))
        model.mouseDragged(to: CGPoint(x: 260, y: 190))
        XCTAssertEqual(model.rect, CGRect(x: 160, y: 140, width: 200, height: 100))
        model.mouseDragged(to: CGPoint(x: 5000, y: 5000))
        XCTAssertEqual(model.rect, CGRect(x: 800, y: 700, width: 200, height: 100))
    }

    func testClickOutsideExistingSelectionIsReported() {
        let model = SelectionModel(bounds: bounds)
        model.setRect(CGRect(x: 100, y: 100, width: 200, height: 100))
        model.mouseDown(at: CGPoint(x: 600, y: 600))
        XCTAssertTrue(model.mouseUp(at: CGPoint(x: 600, y: 600)))
        XCTAssertTrue(model.endedWithOutsideClick)
        XCTAssertNil(model.rect)
    }

    func testClickWithNoSelectionIsNotAnOutsideClick() {
        let model = SelectionModel(bounds: bounds)
        model.mouseDown(at: CGPoint(x: 600, y: 600))
        model.mouseUp(at: CGPoint(x: 600, y: 600))
        XCTAssertFalse(model.endedWithOutsideClick)
    }

    func testDragOutsideSelectionStartsNewSelectionInsteadOfCancelling() {
        let model = SelectionModel(bounds: bounds)
        model.setRect(CGRect(x: 100, y: 100, width: 200, height: 100))
        drag(model, from: CGPoint(x: 500, y: 500), to: CGPoint(x: 700, y: 650))
        XCTAssertFalse(model.endedWithOutsideClick)
        XCTAssertEqual(model.rect, CGRect(x: 500, y: 500, width: 200, height: 150))
    }

    func testClickInsideSelectionDoesNotCancel() {
        let model = SelectionModel(bounds: bounds)
        model.setRect(CGRect(x: 100, y: 100, width: 200, height: 100))
        model.mouseDown(at: CGPoint(x: 150, y: 150))
        model.mouseUp(at: CGPoint(x: 150, y: 150))
        XCTAssertFalse(model.endedWithOutsideClick)
        XCTAssertEqual(model.rect, CGRect(x: 100, y: 100, width: 200, height: 100))
    }
}
