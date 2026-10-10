import XCTest
@testable import Annotation

/// Operation history: additions and multi-item removals are each one undo step (design D6).
final class HistoryTests: XCTestCase {
    private func line(_ y: CGFloat) -> PolylineAnnotation {
        PolylineAnnotation(points: [CGPoint(x: 0, y: y), CGPoint(x: 100, y: y)], style: StrokeStyle(color: AnnotationColor.palette[0], width: 2))
    }

    private func ys(_ document: AnnotationDocument) -> [CGFloat] {
        document.items.map { ($0 as! PolylineAnnotation).points[0].y }
    }

    func testEntriesHaveStableDistinctIDs() {
        let document = AnnotationDocument()
        document.add(line(1))
        document.add(line(2))
        let ids = document.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, 2)
        document.undo()
        document.redo()
        XCTAssertEqual(document.entries.map(\.id), ids)
    }

    func testRemovingSeveralThenUndoRestoresOriginalOrder() {
        let document = AnnotationDocument()
        (1...5).forEach { document.add(line(CGFloat($0))) }
        let ids = Set([document.entries[1].id, document.entries[3].id, document.entries[4].id])
        document.remove(ids: ids)
        XCTAssertEqual(ys(document), [1, 3])
        document.undo()
        XCTAssertEqual(ys(document), [1, 2, 3, 4, 5])
        document.redo()
        XCTAssertEqual(ys(document), [1, 3])
    }

    func testRemoveIsOneUndoStep() {
        let document = AnnotationDocument()
        (1...3).forEach { document.add(line(CGFloat($0))) }
        document.remove(ids: Set(document.entries.map(\.id)))
        XCTAssertTrue(document.isEmpty)
        document.undo()
        XCTAssertEqual(document.items.count, 3)
        document.undo()
        XCTAssertEqual(document.items.count, 2, "the next undo reverts the last addition")
    }

    func testRemovingUnknownIDsRecordsNothing() {
        let document = AnnotationDocument()
        document.add(line(1))
        var changes = 0
        document.onChange = { changes += 1 }
        document.remove(ids: [UUID()])
        XCTAssertEqual(changes, 0)
        document.undo()
        XCTAssertTrue(document.isEmpty, "the only undo step is still the addition")
    }

    func testClearAllEmptiesRedoAfterRemoval() {
        let document = AnnotationDocument()
        (1...3).forEach { document.add(line(CGFloat($0))) }
        document.remove(ids: [document.entries[0].id])
        document.undo()
        document.clearAll()
        XCTAssertFalse(document.canUndo)
        XCTAssertFalse(document.canRedo)
    }

    func testDrawSkipsHiddenEntries() throws {
        let document = AnnotationDocument()
        document.add(line(5))
        let base = CGContext(
            data: nil, width: 100, height: 10, bitsPerComponent: 8, bytesPerRow: 400,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        base.setFillColor(CGColor(gray: 1, alpha: 1))
        base.fill(CGRect(x: 0, y: 0, width: 100, height: 10))
        let context = AnnotationRenderContext(context: base, scale: 1, origin: .zero)
        document.draw(in: context, hidden: [document.entries[0].id])
        let image = try XCTUnwrap(base.makeImage())
        let data = try XCTUnwrap(image.dataProvider?.data as Data?)
        XCTAssertTrue(data.allSatisfy { $0 == 255 }, "a hidden entry draws nothing")
    }
}
