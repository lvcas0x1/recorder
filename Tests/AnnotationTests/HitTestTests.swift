import XCTest
@testable import Annotation

/// Eraser hit testing per shape (design D6): within width/2 + tolerance hits, just outside misses.
final class HitTestTests: XCTestCase {
    private let style = StrokeStyle(color: AnnotationColor.palette[0], width: 4) // half width 2
    private let tolerance: CGFloat = 6 // reach 8 from the centre line

    func testRectangleOutline() {
        let rect = RectangleAnnotation(rect: CGRect(x: 0, y: 0, width: 100, height: 50), style: style)
        XCTAssertTrue(rect.hitTest(CGPoint(x: 50, y: 0), tolerance: tolerance), "on the top edge")
        XCTAssertTrue(rect.hitTest(CGPoint(x: 50, y: 7.9), tolerance: tolerance))
        XCTAssertFalse(rect.hitTest(CGPoint(x: 50, y: 8.1), tolerance: tolerance), "just inside the reach")
        XCTAssertFalse(rect.hitTest(CGPoint(x: 50, y: 25), tolerance: tolerance), "the interior is not a hit")
        XCTAssertFalse(rect.hitTest(CGPoint(x: 108.1, y: 25), tolerance: tolerance))
    }

    func testPolyline() {
        let line = PolylineAnnotation(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)], style: style)
        XCTAssertTrue(line.hitTest(CGPoint(x: 50, y: 0), tolerance: tolerance))
        XCTAssertTrue(line.hitTest(CGPoint(x: 92, y: 50), tolerance: tolerance))
        XCTAssertFalse(line.hitTest(CGPoint(x: 50, y: 8.1), tolerance: tolerance))
        XCTAssertFalse(line.hitTest(CGPoint(x: -8.1, y: 0), tolerance: tolerance), "beyond the end cap reach")
    }

    func testSinglePointStroke() {
        let dot = PolylineAnnotation(points: [CGPoint(x: 10, y: 10)], style: style)
        XCTAssertTrue(dot.hitTest(CGPoint(x: 15, y: 10), tolerance: tolerance))
        XCTAssertFalse(dot.hitTest(CGPoint(x: 18.1, y: 10), tolerance: tolerance))
    }

    func testArrowShaftAndHead() {
        let arrow = ArrowAnnotation(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), style: style)
        XCTAssertTrue(arrow.hitTest(CGPoint(x: 40, y: 7.9), tolerance: tolerance))
        XCTAssertFalse(arrow.hitTest(CGPoint(x: 40, y: 8.1), tolerance: tolerance))
        // Head length 16 from x = 84, half spread 16 * tan(28°) ≈ 8.5 there; at x = 85 the head is ±7.97 wide.
        XCTAssertTrue(arrow.hitTest(CGPoint(x: 85, y: 7.5), tolerance: 0), "inside the head, outside the shaft")
        XCTAssertFalse(arrow.hitTest(CGPoint(x: 86, y: 20), tolerance: tolerance))
    }

    func testRotatedText() {
        var text = TextAnnotation(text: "Hello world", center: CGPoint(x: 200, y: 200), color: AnnotationColor.palette[0])
        text.rotation = .pi / 2 // the long side now runs vertically
        let half = text.size.width / 2
        XCTAssertTrue(text.hitTest(CGPoint(x: 200, y: 200 + half - 2), tolerance: 0), "inside along the rotated long axis")
        XCTAssertFalse(text.hitTest(CGPoint(x: 200 + half - 2, y: 200), tolerance: 0), "outside: the box is narrow horizontally")
        XCTAssertFalse(text.hitTest(CGPoint(x: 200, y: 200 + half + 7), tolerance: 6))
    }

    func testEmptyTextNeverHits() {
        let text = TextAnnotation(text: "", center: .zero, color: AnnotationColor.palette[0])
        XCTAssertFalse(text.hitTest(.zero, tolerance: 10))
    }
}
