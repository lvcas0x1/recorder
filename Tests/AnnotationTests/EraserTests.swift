import XCTest
@testable import Annotation

/// Spec live-annotation, Requirement: Eraser.
final class EraserTests: XCTestCase {
    private func controller() -> DrawingController {
        let c = DrawingController(document: AnnotationDocument())
        let style = StrokeStyle(color: AnnotationColor.palette[0], width: 3)
        c.document.add(PolylineAnnotation(points: [CGPoint(x: 0, y: 10), CGPoint(x: 200, y: 10)], style: style))
        c.document.add(PolylineAnnotation(points: [CGPoint(x: 0, y: 50), CGPoint(x: 200, y: 50)], style: style))
        c.document.add(RectangleAnnotation(rect: CGRect(x: 20, y: 80, width: 60, height: 40), style: style))
        c.document.add(ArrowAnnotation(from: CGPoint(x: 300, y: 300), to: CGPoint(x: 400, y: 300), style: style))
        c.tool = .eraser
        return c
    }

    func testEraseByClick() {
        let c = controller()
        c.pointerDown(at: CGPoint(x: 350, y: 301))
        c.pointerUp(at: CGPoint(x: 350, y: 301))
        XCTAssertEqual(c.document.items.count, 3)
        XCTAssertFalse(c.document.items.contains { $0 is ArrowAnnotation })
    }

    func testEraseByDragRemovesEverythingCrossed() {
        let c = controller()
        // Vertical drag at x = 50 crosses both strokes and the rectangle's top and bottom edges.
        c.pointerDown(at: CGPoint(x: 50, y: 0))
        c.pointerDragged(to: CGPoint(x: 50, y: 60))
        c.pointerDragged(to: CGPoint(x: 50, y: 130))
        c.pointerUp(at: CGPoint(x: 50, y: 130))
        XCTAssertEqual(c.document.items.count, 1)
        XCTAssertTrue(c.document.items.first is ArrowAnnotation)
    }

    func testFastDragDoesNotSkipThinMarks() {
        let c = controller()
        // One big jump from above the first stroke to below the second: the path is sampled in between.
        c.pointerDown(at: CGPoint(x: 150, y: 0))
        c.pointerDragged(to: CGPoint(x: 150, y: 70))
        c.pointerUp(at: CGPoint(x: 150, y: 70))
        XCTAssertEqual(c.document.items.count, 2)
    }

    func testUndoEraseRestoresAllInOneStep() {
        let c = controller()
        c.pointerDown(at: CGPoint(x: 50, y: 0))
        c.pointerDragged(to: CGPoint(x: 50, y: 130))
        c.pointerUp(at: CGPoint(x: 50, y: 130))
        XCTAssertEqual(c.document.items.count, 1)
        c.document.undo()
        XCTAssertEqual(c.document.items.count, 4)
    }

    func testNothingUnderEraserAddsNoUndoStep() {
        let c = controller()
        c.document.undo() // leaves 3 items and one redo step
        c.pointerDown(at: CGPoint(x: 600, y: 600))
        c.pointerUp(at: CGPoint(x: 600, y: 600))
        XCTAssertEqual(c.document.items.count, 3)
        XCTAssertTrue(c.document.canRedo, "an empty erase must not discard the redo history")
    }

    func testPendingErasureIsPreviewedThenCleared() {
        let c = controller()
        c.pointerDown(at: CGPoint(x: 100, y: 10))
        XCTAssertEqual(c.pendingErasure.count, 1)
        XCTAssertEqual(c.document.items.count, 4, "nothing is removed before pointer up")
        c.pointerUp(at: CGPoint(x: 100, y: 10))
        XCTAssertTrue(c.pendingErasure.isEmpty)
    }

    func testLeavingTheToolCancelsPendingErasure() {
        let c = controller()
        c.pointerDown(at: CGPoint(x: 100, y: 10))
        c.tool = nil
        XCTAssertTrue(c.pendingErasure.isEmpty)
        XCTAssertEqual(c.document.items.count, 4)
    }

    func testEraserHasNoStyle() {
        XCTAssertFalse(DrawingTool.eraser.usesStrokeStyle)
        XCTAssertFalse(DrawingTool.eraser.usesStrokeWidth)
        XCTAssertNil(controller().draft)
    }
}
