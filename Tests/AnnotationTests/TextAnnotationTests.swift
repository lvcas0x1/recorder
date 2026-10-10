import XCTest
@testable import Annotation

private enum Canvas {
    static func white(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// RGBA buffer, row 0 = top.
    static func pixels(_ image: CGImage) -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(
            data: &buffer, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }

    /// Bounding box (pixels) of non-white pixels, or nil.
    static func inkBounds(_ pixels: [UInt8], width: Int, height: Int) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                if pixels[i] < 200 || pixels[i + 1] < 200 || pixels[i + 2] < 200 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    static func inkCount(_ pixels: [UInt8], width: Int, rows: Range<Int>, columns: Range<Int>) -> Int {
        var count = 0
        for y in rows { for x in columns where pixels[(y * width + x) * 4] < 128 { count += 1 } }
        return count
    }
}

final class TextAnnotationTests: XCTestCase {
    private let black = AnnotationColor(red: 0, green: 0, blue: 0)

    private func render(_ item: TextAnnotation, width: Int = 400, height: Int = 300, scale: CGFloat = 1) throws -> (pixels: [UInt8], image: CGImage) {
        let document = AnnotationDocument()
        document.add(item)
        let image = try XCTUnwrap(document.flatten(base: Canvas.white(width: width, height: height), scale: scale, origin: .zero))
        return (Canvas.pixels(image), image)
    }

    // MARK: Layout

    func testSizeGrowsWithTextAndLines() {
        let one = TextAnnotation(text: "Hi", center: .zero, color: black)
        let wide = TextAnnotation(text: "Hello world", center: .zero, color: black)
        let two = TextAnnotation(text: "Hi\nthere", center: .zero, color: black)
        XCTAssertGreaterThan(wide.size.width, one.size.width)
        XCTAssertEqual(two.size.height - 2 * TextAnnotation.padding, 2 * (one.size.height - 2 * TextAnnotation.padding), accuracy: 0.5)
    }

    func testEmptyTextStillHasAVisibleBox() {
        let empty = TextAnnotation(text: "", center: .zero, color: black)
        XCTAssertGreaterThan(empty.size.width, 2 * TextAnnotation.padding)
        XCTAssertGreaterThan(empty.size.height, 2 * TextAnnotation.padding)
    }

    func testSizeScalesWithFontSize() {
        let small = TextAnnotation(text: "Scale", center: .zero, fontSize: 20, color: black)
        let large = TextAnnotation(text: "Scale", center: .zero, fontSize: 40, color: black)
        XCTAssertEqual((large.size.width - 8) / (small.size.width - 8), 2, accuracy: 0.1)
    }

    // MARK: Geometry

    func testCornersAndRotationHandleWithoutRotation() {
        let box = TextAnnotation(text: "Hi", center: CGPoint(x: 100, y: 100), color: black)
        let w = box.size.width, h = box.size.height
        XCTAssertEqual(box.point(of: .topLeft).x, 100 - w / 2, accuracy: 0.001)
        XCTAssertEqual(box.point(of: .topLeft).y, 100 - h / 2, accuracy: 0.001)
        XCTAssertEqual(box.point(of: .bottomRight).x, 100 + w / 2, accuracy: 0.001)
        XCTAssertEqual(box.point(of: .rotate).x, 100, accuracy: 0.001)
        XCTAssertEqual(box.point(of: .rotate).y, 100 - h / 2 - TextAnnotation.rotationHandleOffset, accuracy: 0.001)
    }

    func testRotationHandleFollowsRotation() {
        var box = TextAnnotation(text: "Hi", center: CGPoint(x: 100, y: 100), color: black)
        box.rotation = .pi / 2 // clockwise quarter turn: the top edge now faces right
        let handle = box.point(of: .rotate)
        XCTAssertEqual(handle.x, 100 + box.size.height / 2 + TextAnnotation.rotationHandleOffset, accuracy: 0.001)
        XCTAssertEqual(handle.y, 100, accuracy: 0.001)
    }

    func testHitTestingHandles() {
        let box = TextAnnotation(text: "Hi", center: CGPoint(x: 100, y: 100), color: black)
        XCTAssertEqual(box.handle(at: box.point(of: .topLeft)), .topLeft)
        XCTAssertEqual(box.handle(at: box.point(of: .bottomRight)), .bottomRight)
        XCTAssertEqual(box.handle(at: CGPoint(x: box.point(of: .rotate).x + 3, y: box.point(of: .rotate).y - 3)), .rotate)
        XCTAssertNil(box.handle(at: CGPoint(x: 100, y: 100)), "box center is not a handle")
        XCTAssertNil(box.handle(at: CGPoint(x: 500, y: 500)))
    }

    func testTypingKeepsTheTopLeftAnchored() {
        var box = TextAnnotation(text: "A", center: CGPoint(x: 100, y: 100), color: black)
        box.rotation = 0.6
        let before = box.point(of: .topLeft)
        let longer = box.settingText("A much longer line\nand a second one")
        let after = longer.point(of: .topLeft)
        XCTAssertEqual(before.x, after.x, accuracy: 0.001)
        XCTAssertEqual(before.y, after.y, accuracy: 0.001)
        XCTAssertGreaterThan(longer.size.width, box.size.width)
    }

    func testCaretSitsAtTheEndOfTheLastLine() {
        let box = TextAnnotation(text: "ab\ncd", center: CGPoint(x: 100, y: 100), color: black)
        let caret = box.caret
        XCTAssertEqual(caret.top.x, caret.bottom.x, accuracy: 0.001)
        XCTAssertGreaterThan(caret.bottom.y, caret.top.y)
        XCTAssertGreaterThan(caret.top.y, box.point(of: .topLeft).y + 5, "caret is on the second line")
    }

    // MARK: Rendering

    func testTextIsUprightAndNotMirrored() throws {
        // "L": vertical stroke on the left, horizontal bar along the bottom.
        let box = TextAnnotation(text: "L", center: CGPoint(x: 200, y: 150), fontSize: 120, color: black)
        let (pixels, _) = try render(box)
        let ink = try XCTUnwrap(Canvas.inkBounds(pixels, width: 400, height: 300))
        let thirdH = Int(ink.height / 3), thirdW = Int(ink.width / 3)
        let top = Int(ink.minY), bottom = Int(ink.maxY) - thirdH
        let left = Int(ink.minX), right = Int(ink.maxX) - thirdW
        let topRows = Canvas.inkCount(pixels, width: 400, rows: top..<(top + thirdH), columns: Int(ink.minX)..<Int(ink.maxX))
        let bottomRows = Canvas.inkCount(pixels, width: 400, rows: bottom..<(bottom + thirdH), columns: Int(ink.minX)..<Int(ink.maxX))
        XCTAssertGreaterThan(bottomRows, topRows * 2, "the foot of an upright L is at the bottom")
        let midRows = Int(ink.midY - 5)..<Int(ink.midY + 5)
        let leftCols = Canvas.inkCount(pixels, width: 400, rows: midRows, columns: left..<(left + thirdW))
        let rightCols = Canvas.inkCount(pixels, width: 400, rows: midRows, columns: right..<(right + thirdW))
        XCTAssertGreaterThan(leftCols, rightCols * 2, "the stem of a non-mirrored L is on the left")
    }

    func testTextAppearsAroundTheCenterAndUsesTheColor() throws {
        let red = AnnotationColor(red: 1, green: 0, blue: 0)
        let box = TextAnnotation(text: "Hello", center: CGPoint(x: 200, y: 150), fontSize: 40, color: red)
        let (pixels, _) = try render(box)
        let ink = try XCTUnwrap(Canvas.inkBounds(pixels, width: 400, height: 300))
        XCTAssertEqual(ink.midX, 200, accuracy: 15)
        XCTAssertEqual(ink.midY, 150, accuracy: 15)
        // A fully covered pixel is pure red.
        var foundRed = false
        for y in 0..<300 { for x in 0..<400 {
            let i = (y * 400 + x) * 4
            if pixels[i] == 255, pixels[i + 1] == 0, pixels[i + 2] == 0 { foundRed = true }
        } }
        XCTAssertTrue(foundRed)
    }

    func testRenderedTextRespectsRetinaScale() throws {
        let box = TextAnnotation(text: "Hello", center: CGPoint(x: 100, y: 75), fontSize: 30, color: black)
        let (p1, _) = try render(box, width: 200, height: 150, scale: 1)
        let (p2, _) = try render(box, width: 400, height: 300, scale: 2)
        let b1 = try XCTUnwrap(Canvas.inkBounds(p1, width: 200, height: 150))
        let b2 = try XCTUnwrap(Canvas.inkBounds(p2, width: 400, height: 300))
        XCTAssertEqual(b2.width, b1.width * 2, accuracy: 4)
        XCTAssertEqual(b2.height, b1.height * 2, accuracy: 4)
    }

    func testRotatedTextTurnsTheWordOnItsSide() throws {
        var box = TextAnnotation(text: "WIDE WORD", center: CGPoint(x: 200, y: 150), fontSize: 40, color: black)
        let flat = try XCTUnwrap(Canvas.inkBounds(try render(box).pixels, width: 400, height: 300))
        XCTAssertGreaterThan(flat.width, flat.height * 3)
        box.rotation = .pi / 2
        let turned = try XCTUnwrap(Canvas.inkBounds(try render(box).pixels, width: 400, height: 300))
        XCTAssertGreaterThan(turned.height, turned.width * 3, "a quarter turn swaps width and height")
    }

    func testEmptyTextDrawsNothing() throws {
        let (pixels, _) = try render(TextAnnotation(text: "", center: CGPoint(x: 100, y: 100), color: black))
        XCTAssertNil(Canvas.inkBounds(pixels, width: 400, height: 300))
    }

    func testJapaneseTextRenders() throws {
        let (pixels, _) = try render(TextAnnotation(text: "日本語", center: CGPoint(x: 200, y: 150), fontSize: 48, color: black))
        let ink = try XCTUnwrap(Canvas.inkBounds(pixels, width: 400, height: 300))
        XCTAssertGreaterThan(ink.width, 80)
    }

    // MARK: Rotation snapping

    func testSnapsToRightAnglesWithinTolerance() {
        let deg: (CGFloat) -> CGFloat = { $0 * .pi / 180 }
        XCTAssertEqual(TextAnnotation.snappedRotation(deg(5)), 0, accuracy: 1e-9)
        XCTAssertEqual(TextAnnotation.snappedRotation(deg(-7)), 0, accuracy: 1e-9)
        XCTAssertEqual(TextAnnotation.snappedRotation(deg(84)), .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(TextAnnotation.snappedRotation(deg(97)), .pi / 2, accuracy: 1e-9)
        XCTAssertEqual(TextAnnotation.snappedRotation(deg(-88)), -.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(TextAnnotation.snappedRotation(deg(176)), .pi, accuracy: 1e-9)
        XCTAssertEqual(TextAnnotation.snappedRotation(deg(-174)), -.pi, accuracy: 1e-9)
    }

    func testDoesNotSnapOutsideTolerance() {
        let deg: (CGFloat) -> CGFloat = { $0 * .pi / 180 }
        for angle in [deg(12), deg(30), deg(45), deg(60), deg(78), deg(-30), deg(120), deg(-150)] {
            XCTAssertEqual(TextAnnotation.snappedRotation(angle), angle, accuracy: 1e-9)
        }
    }

    func testToleranceIsAdjustableAndInclusive() {
        let deg: (CGFloat) -> CGFloat = { $0 * .pi / 180 }
        XCTAssertEqual(TextAnnotation.snappedRotation(deg(15), toleranceDegrees: 15), 0, accuracy: 1e-9)
        XCTAssertEqual(TextAnnotation.snappedRotation(deg(16), toleranceDegrees: 15), deg(16), accuracy: 1e-9)
    }
}
