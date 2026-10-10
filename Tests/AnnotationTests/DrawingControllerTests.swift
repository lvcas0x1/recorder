import XCTest
@testable import Annotation

final class DrawingControllerTests: XCTestCase {
    private func makeController(tool: DrawingTool?) -> DrawingController {
        let controller = DrawingController(document: AnnotationDocument())
        controller.tool = tool
        return controller
    }

    private func drag(_ c: DrawingController, from a: CGPoint, through mid: [CGPoint] = [], to b: CGPoint) {
        c.pointerDown(at: a)
        mid.forEach { c.pointerDragged(to: $0) }
        c.pointerDragged(to: b)
        c.pointerUp(at: b)
    }

    private func click(_ c: DrawingController, at p: CGPoint) {
        c.pointerDown(at: p)
        c.pointerUp(at: p)
    }

    // MARK: Rectangle

    func testRectangleDragAddsNormalizedRectangleWithCurrentStyle() throws {
        let c = makeController(tool: .rectangle)
        drag(c, from: CGPoint(x: 100, y: 80), to: CGPoint(x: 20, y: 10))
        let rect = try XCTUnwrap(c.document.items.first as? RectangleAnnotation)
        XCTAssertEqual(rect.rect, CGRect(x: 20, y: 10, width: 80, height: 70))
        XCTAssertEqual(rect.style, StrokeStyle(color: AnnotationColor.palette[0], width: 3))
    }

    func testTinyRectangleIsDiscarded() {
        let c = makeController(tool: .rectangle)
        drag(c, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 11, y: 10))
        XCTAssertTrue(c.document.isEmpty)
    }

    func testNoToolMeansNothingIsDrawn() {
        let c = makeController(tool: nil)
        drag(c, from: .zero, to: CGPoint(x: 50, y: 50))
        XCTAssertTrue(c.document.isEmpty)
        XCTAssertFalse(c.isEditing)
    }

    // MARK: Line and arrow

    func testLineDragAddsSingleSegment() throws {
        let c = makeController(tool: .line)
        drag(c, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 60, y: 40))
        let line = try XCTUnwrap(c.document.items.first as? PolylineAnnotation)
        XCTAssertEqual(line.points, [CGPoint(x: 0, y: 0), CGPoint(x: 60, y: 40)])
    }

    func testLineStripBuiltByClicksAndFinishedByRightClick() throws {
        let c = makeController(tool: .line)
        click(c, at: CGPoint(x: 10, y: 10))
        click(c, at: CGPoint(x: 50, y: 10))
        click(c, at: CGPoint(x: 50, y: 60))
        XCTAssertTrue(c.document.isEmpty, "nothing is committed until the strip is finished")
        c.finishDraft()
        let strip = try XCTUnwrap(c.document.items.first as? PolylineAnnotation)
        XCTAssertEqual(strip.points, [CGPoint(x: 10, y: 10), CGPoint(x: 50, y: 10), CGPoint(x: 50, y: 60)])
        XCTAssertFalse(c.isDraftActive)
    }

    func testStripWithASinglePointIsDiscarded() {
        let c = makeController(tool: .line)
        click(c, at: CGPoint(x: 10, y: 10))
        c.finishDraft()
        XCTAssertTrue(c.document.isEmpty)
    }

    func testStripDraftFollowsTheCursor() throws {
        let c = makeController(tool: .line)
        click(c, at: CGPoint(x: 10, y: 10))
        click(c, at: CGPoint(x: 50, y: 10))
        c.pointerMoved(to: CGPoint(x: 70, y: 30))
        let draft = try XCTUnwrap(c.draft as? PolylineAnnotation)
        XCTAssertEqual(draft.points.last, CGPoint(x: 70, y: 30))
        XCTAssertEqual(draft.points.count, 3)
    }

    func testArrowDragAddsArrowAndClickDoesNothing() throws {
        let c = makeController(tool: .arrow)
        click(c, at: CGPoint(x: 5, y: 5))
        XCTAssertTrue(c.document.isEmpty)
        XCTAssertFalse(c.isDraftActive)
        drag(c, from: CGPoint(x: 5, y: 5), to: CGPoint(x: 105, y: 5))
        let arrow = try XCTUnwrap(c.document.items.first as? ArrowAnnotation)
        XCTAssertEqual(arrow.from, CGPoint(x: 5, y: 5))
        XCTAssertEqual(arrow.to, CGPoint(x: 105, y: 5))
    }

    func testTabSwitchesBetweenLineAndArrowOnly() {
        let c = makeController(tool: .line)
        XCTAssertTrue(c.toggleLineArrow())
        XCTAssertEqual(c.tool, .arrow)
        XCTAssertTrue(c.toggleLineArrow())
        XCTAssertEqual(c.tool, .line)
        c.tool = .rectangle
        XCTAssertFalse(c.toggleLineArrow())
        XCTAssertEqual(c.tool, .rectangle)
    }

    func testChangingToolDiscardsAnUnfinishedStrip() {
        let c = makeController(tool: .line)
        click(c, at: CGPoint(x: 10, y: 10))
        click(c, at: CGPoint(x: 50, y: 10))
        c.tool = .arrow
        XCTAssertFalse(c.isDraftActive)
        XCTAssertTrue(c.document.isEmpty)
    }

    // MARK: Pencil and marker

    func testPencilCollectsThePointerPath() throws {
        let c = makeController(tool: .pencil)
        drag(c, from: CGPoint(x: 0, y: 0), through: [CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 0)], to: CGPoint(x: 30, y: 5))
        let stroke = try XCTUnwrap(c.document.items.first as? PolylineAnnotation)
        XCTAssertEqual(stroke.points, [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 0), CGPoint(x: 30, y: 5), CGPoint(x: 30, y: 5)])
        XCTAssertEqual(stroke.lineCap, .round)
    }

    func testMarkerIsWiderAndMoreTransparentThanThePen() throws {
        let c = makeController(tool: .marker)
        c.setWidth(4)
        c.setAlpha(1)
        drag(c, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 80, y: 0))
        let marker = try XCTUnwrap(c.document.items.first as? PolylineAnnotation)
        XCTAssertEqual(marker.style.width, 12)
        XCTAssertEqual(marker.style.color.alpha, 0.4, accuracy: 0.0001)
        XCTAssertEqual(marker.lineCap, .butt)
    }

    // MARK: Style

    func testWidthIsClampedAndAdjustable() {
        let c = makeController(tool: .pencil)
        c.adjustWidth(by: 2)
        XCTAssertEqual(c.width, 5)
        c.adjustWidth(by: -100)
        XCTAssertEqual(c.width, 1)
        c.adjustWidth(by: 1000)
        XCTAssertEqual(c.width, 24)
    }

    func testCustomColorWithAlphaIsSplitIntoBaseAndAlpha() {
        let c = makeController(tool: .pencil)
        c.setColor(AnnotationColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 128.0 / 255))
        XCTAssertEqual(c.baseColor, AnnotationColor(red: 0.1, green: 0.2, blue: 0.3))
        XCTAssertEqual(c.alpha, 128.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(c.color.alpha, 128.0 / 255, accuracy: 0.0001)
    }

    func testNewAnnotationsUseTheCurrentStyleButExistingOnesKeepTheirs() throws {
        let c = makeController(tool: .rectangle)
        drag(c, from: .zero, to: CGPoint(x: 20, y: 20))
        c.setWidth(10)
        c.setColor(AnnotationColor.palette[1])
        drag(c, from: .zero, to: CGPoint(x: 30, y: 30))
        let first = try XCTUnwrap(c.document.items[0] as? RectangleAnnotation)
        let second = try XCTUnwrap(c.document.items[1] as? RectangleAnnotation)
        XCTAssertEqual(first.style.width, 3)
        XCTAssertEqual(second.style.width, 10)
        XCTAssertNotEqual(first.style.color, second.style.color)
    }

    func testUndoRemovesTheLastDrawnShape() {
        let c = makeController(tool: .rectangle)
        drag(c, from: .zero, to: CGPoint(x: 20, y: 20))
        drag(c, from: .zero, to: CGPoint(x: 40, y: 40))
        c.document.undo()
        XCTAssertEqual(c.document.items.count, 1)
    }

    func testDrawingToolsUseStrokeStyle() {
        XCTAssertTrue(DrawingTool.rectangle.usesStrokeStyle)
        XCTAssertTrue(DrawingTool.marker.usesStrokeStyle)
    }

    // MARK: Text tool

    private func textController() -> DrawingController { makeController(tool: .text) }

    private func tap(_ c: DrawingController, at p: CGPoint, shift: Bool = false) {
        c.pointerDown(at: p, shift: shift)
        c.pointerUp(at: p)
    }

    func testClickCreatesAnEmptyDraftWithItsTopLeftAtTheClick() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 50, y: 60))
        let draft = try XCTUnwrap(c.textDraft)
        XCTAssertEqual(draft.point(of: .topLeft).x, 50, accuracy: 0.001)
        XCTAssertEqual(draft.point(of: .topLeft).y, 60, accuracy: 0.001)
        XCTAssertTrue(c.isEditingText)
        XCTAssertTrue(c.document.isEmpty)
    }

    func testTypingBuildsTextAndKeepsTheTopLeftFixed() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 50, y: 60))
        c.insertText("Hel")
        c.insertText("lo")
        c.insertNewline()
        c.insertText("世界")
        let draft = try XCTUnwrap(c.textDraft)
        XCTAssertEqual(draft.text, "Hello\n世界")
        XCTAssertEqual(draft.point(of: .topLeft).x, 50, accuracy: 0.001)
        XCTAssertEqual(draft.point(of: .topLeft).y, 60, accuracy: 0.001)
    }

    func testDeleteBackwardRemovesTheLastCharacter() throws {
        let c = textController()
        tap(c, at: .zero)
        c.insertText("abc")
        c.deleteBackward()
        XCTAssertEqual(c.textDraft?.text, "ab")
        c.deleteBackward(); c.deleteBackward(); c.deleteBackward()
        XCTAssertEqual(c.textDraft?.text, "")
    }

    func testMarkedTextIsShownButReplacedByEachComposition() throws {
        let c = textController()
        tap(c, at: .zero)
        c.insertText("a")
        c.setMarkedText("に")
        XCTAssertEqual(c.textDraft?.text, "aに")
        c.setMarkedText("にほ")
        XCTAssertEqual(c.textDraft?.text, "aにほ")
        c.insertText("日本") // the input method confirms its conversion
        XCTAssertEqual(c.textDraft?.text, "a日本")
    }

    func testCommitAddsTheTextAndEmptyTextIsDiscarded() throws {
        let c = textController()
        tap(c, at: .zero)
        c.insertText("Hello")
        c.commitText()
        XCTAssertFalse(c.isEditingText)
        let item = try XCTUnwrap(c.document.items.first as? TextAnnotation)
        XCTAssertEqual(item.text, "Hello")

        tap(c, at: CGPoint(x: 10, y: 100))
        c.insertText("   ")
        c.commitText()
        XCTAssertEqual(c.document.items.count, 1, "whitespace-only text is discarded")
    }

    func testClickingElsewhereCommitsAndStartsANewText() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 20, y: 20))
        c.insertText("first")
        tap(c, at: CGPoint(x: 300, y: 200))
        XCTAssertEqual(c.document.items.count, 1)
        XCTAssertEqual((c.document.items[0] as? TextAnnotation)?.text, "first")
        XCTAssertEqual(c.textDraft?.text, "")
        XCTAssertEqual(c.textDraft?.point(of: .topLeft).x ?? 0, 300, accuracy: 0.001)
    }

    func testChangingToolCommitsTheText() {
        let c = textController()
        tap(c, at: .zero)
        c.insertText("keep me")
        c.tool = .rectangle
        XCTAssertFalse(c.isEditingText)
        XCTAssertEqual((c.document.items.first as? TextAnnotation)?.text, "keep me")
    }

    func testCancelTextDiscardsTheDraft() {
        let c = textController()
        tap(c, at: .zero)
        c.insertText("nope")
        c.cancelText()
        XCTAssertFalse(c.isEditingText)
        XCTAssertTrue(c.document.isEmpty)
    }

    func testDraggingACornerOutwardEnlargesTheTextProportionally() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 100, y: 100))
        c.insertText("Scale me")
        let box = try XCTUnwrap(c.textDraft)
        let corner = box.point(of: .bottomRight)
        let center = box.center
        // Pull the corner to twice its distance from the center, in the same direction.
        let target = CGPoint(x: center.x + (corner.x - center.x) * 2, y: center.y + (corner.y - center.y) * 2)
        c.pointerDown(at: corner)
        c.pointerDragged(to: target)
        c.pointerUp(at: target)
        let scaled = try XCTUnwrap(c.textDraft)
        XCTAssertEqual(scaled.fontSize, box.fontSize * 2, accuracy: 0.01)
        XCTAssertEqual(scaled.center.x, box.center.x, accuracy: 0.5, "scaling is about the center")
    }

    func testFontSizeIsClamped() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 100, y: 100))
        c.insertText("x")
        let box = try XCTUnwrap(c.textDraft)
        let corner = box.point(of: .bottomRight)
        c.pointerDown(at: corner)
        c.pointerDragged(to: CGPoint(x: box.center.x + 100_000, y: box.center.y))
        XCTAssertEqual(c.textDraft?.fontSize, TextAnnotation.fontSizeRange.upperBound)
        c.pointerDragged(to: CGPoint(x: box.center.x + 0.01, y: box.center.y))
        XCTAssertEqual(c.textDraft?.fontSize, TextAnnotation.fontSizeRange.lowerBound)
    }

    func testDraggingTheTopHandleToTheRightRotatesAQuarterTurn() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 100, y: 100))
        c.insertText("Spin")
        let box = try XCTUnwrap(c.textDraft)
        let handle = box.point(of: .rotate)
        c.pointerDown(at: handle)
        c.pointerDragged(to: CGPoint(x: box.center.x + 80, y: box.center.y))
        c.pointerUp(at: .zero)
        XCTAssertEqual(c.textDraft?.rotation ?? 0, .pi / 2, accuracy: 0.0001)
        c.pointerDown(at: c.textDraft!.point(of: .rotate))
        c.pointerDragged(to: CGPoint(x: box.center.x, y: box.center.y + 80)) // straight down
        XCTAssertEqual(abs(c.textDraft?.rotation ?? 0), .pi, accuracy: 0.0001)
    }

    func testShiftOnACornerLevelsRotatedText() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 100, y: 100))
        c.insertText("Level")
        let upright = try XCTUnwrap(c.textDraft)
        c.pointerDown(at: upright.point(of: .rotate))
        c.pointerDragged(to: CGPoint(x: upright.center.x + 60, y: upright.center.y - 40))
        c.pointerUp(at: .zero)
        let tilted = try XCTUnwrap(c.textDraft)
        XCTAssertNotEqual(tilted.rotation, 0, accuracy: 0.05)

        let corner = tilted.point(of: .bottomRight)
        c.pointerDown(at: corner, shift: true)
        c.pointerDragged(to: corner)
        c.pointerUp(at: corner)
        XCTAssertEqual(c.textDraft?.rotation ?? 1, 0, accuracy: 0.0001)
    }

    func testCornerWithoutShiftKeepsTheRotation() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 100, y: 100))
        c.insertText("Keep")
        let box = try XCTUnwrap(c.textDraft)
        c.pointerDown(at: box.point(of: .rotate))
        c.pointerDragged(to: CGPoint(x: box.center.x + 60, y: box.center.y - 40))
        c.pointerUp(at: .zero)
        let tilted = try XCTUnwrap(c.textDraft)
        let corner = tilted.point(of: .topRight)
        c.pointerDown(at: corner)
        c.pointerDragged(to: corner)
        XCTAssertEqual(c.textDraft?.rotation ?? 0, tilted.rotation, accuracy: 0.0001)
    }

    func testTextDraftFollowsColorChanges() {
        let c = textController()
        tap(c, at: .zero)
        c.insertText("Colorful")
        c.setColor(AnnotationColor(red: 0, green: 0, blue: 1, alpha: 0.5))
        XCTAssertEqual(c.textDraft?.color, AnnotationColor(red: 0, green: 0, blue: 1, alpha: 0.5))
        c.commitText()
        XCTAssertEqual((c.document.items.first as? TextAnnotation)?.color, AnnotationColor(red: 0, green: 0, blue: 1, alpha: 0.5))
    }

    func testTextToolUsesColorButNotPenWidth() {
        XCTAssertTrue(DrawingTool.text.usesStrokeStyle)
        XCTAssertFalse(DrawingTool.text.usesStrokeWidth)
        XCTAssertTrue(DrawingTool.pencil.usesStrokeWidth)
    }

    // MARK: Rotation snapping with Shift

    private func rotate(_ c: DrawingController, toDegreesFromUp degrees: CGFloat, shift: Bool) throws {
        let box = try XCTUnwrap(c.textDraft)
        let radians = degrees * .pi / 180
        // Pointer position at the given clockwise angle from straight up, 100 pt from the center.
        let target = CGPoint(x: box.center.x + sin(radians) * 100, y: box.center.y - cos(radians) * 100)
        c.pointerDown(at: box.point(of: .rotate))
        c.pointerDragged(to: target, shift: shift)
        c.pointerUp(at: target)
    }

    func testShiftSnapsRotationNearARightAngle() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 100, y: 100))
        c.insertText("Snap")
        try rotate(c, toDegreesFromUp: 86, shift: true)
        XCTAssertEqual(c.textDraft?.rotation ?? 0, .pi / 2, accuracy: 1e-9)
    }

    func testWithoutShiftRotationIsFree() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 100, y: 100))
        c.insertText("Free")
        try rotate(c, toDegreesFromUp: 86, shift: false)
        XCTAssertEqual(c.textDraft?.rotation ?? 0, 86 * .pi / 180, accuracy: 1e-6)
    }

    func testShiftDoesNotSnapFarFromARightAngle() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 100, y: 100))
        c.insertText("Far")
        try rotate(c, toDegreesFromUp: 50, shift: true)
        XCTAssertEqual(c.textDraft?.rotation ?? 0, 50 * .pi / 180, accuracy: 1e-6)
    }

    func testShiftSnapWorksForUpsideDownAndLeft() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 100, y: 100))
        c.insertText("Turn")
        try rotate(c, toDegreesFromUp: 183, shift: true)
        XCTAssertEqual(abs(c.textDraft?.rotation ?? 0), .pi, accuracy: 1e-9)
        try rotate(c, toDegreesFromUp: -92, shift: true)
        XCTAssertEqual(c.textDraft?.rotation ?? 0, -.pi / 2, accuracy: 1e-9)
    }

    func testShiftIsReadOnEveryDragSoItCanBeHeldOrReleasedMidDrag() throws {
        let c = textController()
        tap(c, at: CGPoint(x: 100, y: 100))
        c.insertText("Mid")
        let box = try XCTUnwrap(c.textDraft)
        c.pointerDown(at: box.point(of: .rotate))
        let near = CGPoint(x: box.center.x + sin(86 * .pi / 180) * 100, y: box.center.y - cos(86 * .pi / 180) * 100)
        c.pointerDragged(to: near, shift: true)
        XCTAssertEqual(c.textDraft?.rotation ?? 0, .pi / 2, accuracy: 1e-9)
        c.pointerDragged(to: near, shift: false)
        XCTAssertEqual(c.textDraft?.rotation ?? 0, 86 * .pi / 180, accuracy: 1e-6)
    }
}
