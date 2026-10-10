import XCTest
@testable import Annotation

/// Fills a rectangle given in global top-left points.
private struct FilledRect: Annotation {
    let rect: CGRect
    let red: CGFloat, green: CGFloat, blue: CGFloat

    func render(in context: AnnotationRenderContext) {
        context.context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.context.fill(rect)
    }
}

/// Records what it was given instead of drawing.
private final class Probe: Annotation {
    private(set) var seenBase: CGImage?
    private(set) var seenBounds: CGRect?
    func render(in context: AnnotationRenderContext) {
        seenBase = context.base
        seenBounds = context.bounds
    }
}

private enum Pixels {
    static func solid(width: Int, height: Int, gray: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: gray, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// RGBA of the pixel at (x, y) counted from the top-left.
    static func rgba(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &buffer, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
        return buffer
    }
}

final class AnnotationDocumentTests: XCTestCase {
    private func rect(_ n: CGFloat) -> FilledRect { FilledRect(rect: CGRect(x: n, y: n, width: 1, height: 1), red: 1, green: 0, blue: 0) }

    // MARK: History

    func testUndoRemovesLastAndRedoRestoresIt() {
        let document = AnnotationDocument()
        document.add(rect(1))
        document.add(rect(2))
        document.undo()
        XCTAssertEqual(document.items.count, 1)
        XCTAssertTrue(document.canRedo)
        document.redo()
        XCTAssertEqual(document.items.count, 2)
        XCTAssertFalse(document.canRedo)
    }

    func testUndoAndRedoOnEmptyHistoryDoNothing() {
        let document = AnnotationDocument()
        document.undo()
        document.redo()
        XCTAssertTrue(document.isEmpty)
        XCTAssertFalse(document.canUndo)
        XCTAssertFalse(document.canRedo)
    }

    func testAddingAfterUndoDiscardsRedoHistory() {
        let document = AnnotationDocument()
        document.add(rect(1))
        document.undo()
        document.add(rect(2))
        XCTAssertFalse(document.canRedo)
        document.redo()
        XCTAssertEqual(document.items.count, 1)
    }

    func testClearAllCannotBeUndoneOrRedone() {
        let document = AnnotationDocument()
        (1...3).forEach { document.add(rect(CGFloat($0))) }
        document.undo()
        document.clearAll()
        XCTAssertTrue(document.isEmpty)
        XCTAssertFalse(document.canUndo)
        XCTAssertFalse(document.canRedo)
        document.undo()
        document.redo()
        XCTAssertTrue(document.isEmpty)
    }

    func testOnChangeFiresForEveryMutation() {
        let document = AnnotationDocument()
        var count = 0
        document.onChange = { count += 1 }
        document.add(rect(1))      // 1
        document.undo()            // 2
        document.redo()            // 3
        document.clearAll()        // 4
        document.clearAll()        // no change -> no event
        document.undo()            // no change -> no event
        XCTAssertEqual(count, 4)
    }

    // MARK: Flattening

    func testEmptyDocumentReturnsTheBaseImageUnchanged() {
        let base = Pixels.solid(width: 20, height: 10, gray: 1)
        XCTAssertTrue(AnnotationDocument().flatten(base: base, scale: 2, origin: .zero) === base)
    }

    func testFlattenKeepsNativePixelSize() throws {
        let document = AnnotationDocument()
        document.add(rect(1))
        let base = Pixels.solid(width: 400, height: 200, gray: 1) // 200x100 pt at 2x
        let result = try XCTUnwrap(document.flatten(base: base, scale: 2, origin: .zero))
        XCTAssertEqual(result.width, 400)
        XCTAssertEqual(result.height, 200)
    }

    func testAnnotationLandsAtScaledPositionFromTheTopLeft() throws {
        let document = AnnotationDocument()
        // 10x10 pt red square at (20, 5) pt in a 2x snip.
        document.add(FilledRect(rect: CGRect(x: 20, y: 5, width: 10, height: 10), red: 1, green: 0, blue: 0))
        let base = Pixels.solid(width: 200, height: 100, gray: 1)
        let result = try XCTUnwrap(document.flatten(base: base, scale: 2, origin: .zero))
        XCTAssertEqual(Pixels.rgba(result, x: 50, y: 20), [255, 0, 0, 255])   // inside: (25pt, 10pt) -> (50px, 20px)
        XCTAssertEqual(Pixels.rgba(result, x: 39, y: 20), [255, 255, 255, 255]) // just left of 40px
        XCTAssertEqual(Pixels.rgba(result, x: 50, y: 9), [255, 255, 255, 255])  // just above 10px
        XCTAssertEqual(Pixels.rgba(result, x: 50, y: 31), [255, 255, 255, 255]) // just below 30px
    }

    func testOriginOffsetsGlobalCoordinatesIntoTheSnip() throws {
        let document = AnnotationDocument()
        // Global (1100, 305) pt with the snip's origin at global (1000, 300) pt -> local (100, 5) pt.
        document.add(FilledRect(rect: CGRect(x: 1100, y: 305, width: 10, height: 10), red: 0, green: 0, blue: 1))
        let base = Pixels.solid(width: 240, height: 60, gray: 1) // 120x30 pt at 2x
        let result = try XCTUnwrap(document.flatten(base: base, scale: 2, origin: CGPoint(x: 1000, y: 300)))
        XCTAssertEqual(Pixels.rgba(result, x: 210, y: 20), [0, 0, 255, 255])
        XCTAssertEqual(Pixels.rgba(result, x: 10, y: 20), [255, 255, 255, 255])
    }

    func testAnnotationsDrawInOrderSoLaterOnesCoverEarlierOnes() throws {
        let document = AnnotationDocument()
        let area = CGRect(x: 0, y: 0, width: 10, height: 10)
        document.add(FilledRect(rect: area, red: 1, green: 0, blue: 0))
        document.add(FilledRect(rect: area, red: 0, green: 1, blue: 0))
        let result = try XCTUnwrap(document.flatten(base: Pixels.solid(width: 20, height: 20, gray: 1), scale: 1, origin: .zero))
        XCTAssertEqual(Pixels.rgba(result, x: 5, y: 5), [0, 255, 0, 255])
    }

    func testUndoneAnnotationsAreNotFlattened() throws {
        let document = AnnotationDocument()
        document.add(FilledRect(rect: CGRect(x: 0, y: 0, width: 10, height: 10), red: 1, green: 0, blue: 0))
        document.undo()
        let base = Pixels.solid(width: 20, height: 20, gray: 1)
        XCTAssertTrue(document.flatten(base: base, scale: 1, origin: .zero) === base)
    }

    func testAnnotationsReceiveTheOriginalBaseImageAndItsBounds() throws {
        let document = AnnotationDocument()
        let probe = Probe()
        document.add(probe)
        let base = Pixels.solid(width: 400, height: 200, gray: 0.5)
        _ = document.flatten(base: base, scale: 2, origin: CGPoint(x: 30, y: 40))
        XCTAssertTrue(probe.seenBase === base)
        XCTAssertEqual(probe.seenBounds, CGRect(x: 30, y: 40, width: 200, height: 100))
    }

    func testDrawingStateDoesNotLeakBetweenAnnotations() throws {
        struct ClipAndTint: Annotation {
            func render(in context: AnnotationRenderContext) {
                context.context.clip(to: CGRect(x: 0, y: 0, width: 1, height: 1))
                context.context.setAlpha(0.1)
            }
        }
        let document = AnnotationDocument()
        document.add(ClipAndTint())
        document.add(FilledRect(rect: CGRect(x: 0, y: 0, width: 10, height: 10), red: 1, green: 0, blue: 0))
        let result = try XCTUnwrap(document.flatten(base: Pixels.solid(width: 20, height: 20, gray: 1), scale: 1, origin: .zero))
        XCTAssertEqual(Pixels.rgba(result, x: 8, y: 8), [255, 0, 0, 255])
    }
}
