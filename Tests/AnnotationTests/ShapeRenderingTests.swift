import XCTest
@testable import Annotation

private enum Pixels {
    static func white(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

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

final class ShapeRenderingTests: XCTestCase {
    private let red = AnnotationColor(red: 1, green: 0, blue: 0)
    private let white: [UInt8] = [255, 255, 255, 255]
    private let redPixel: [UInt8] = [255, 0, 0, 255]

    private func render(_ item: any Annotation, size: Int = 200, scale: CGFloat = 2) throws -> CGImage {
        let document = AnnotationDocument()
        document.add(item)
        return try XCTUnwrap(document.flatten(base: Pixels.white(width: size, height: size), scale: scale, origin: .zero))
    }

    func testRectangleDrawsOutlineOnly() throws {
        let image = try render(RectangleAnnotation(rect: CGRect(x: 10, y: 10, width: 60, height: 40), style: StrokeStyle(color: red, width: 4)))
        // 2x: outline centred on x=20px with 8px thickness -> covers 16..24px.
        XCTAssertEqual(Pixels.rgba(image, x: 20, y: 60), redPixel)
        XCTAssertEqual(Pixels.rgba(image, x: 60, y: 20), redPixel)
        XCTAssertEqual(Pixels.rgba(image, x: 70, y: 50), white, "interior stays untouched")
        XCTAssertEqual(Pixels.rgba(image, x: 5, y: 5), white)
    }

    func testRectangleNormalizesNegativeSizes() {
        let rect = RectangleAnnotation(rect: CGRect(x: 50, y: 50, width: -30, height: -20), style: StrokeStyle(color: red, width: 1))
        XCTAssertEqual(rect.rect, CGRect(x: 20, y: 30, width: 30, height: 20))
    }

    func testPolylineConnectsAllPoints() throws {
        let item = PolylineAnnotation(
            points: [CGPoint(x: 10, y: 10), CGPoint(x: 60, y: 10), CGPoint(x: 60, y: 60)],
            style: StrokeStyle(color: red, width: 4)
        )
        let image = try render(item)
        XCTAssertEqual(Pixels.rgba(image, x: 70, y: 20), redPixel)   // first segment midpoint (35pt,10pt)
        XCTAssertEqual(Pixels.rgba(image, x: 120, y: 70), redPixel)  // second segment midpoint (60pt,35pt)
        XCTAssertEqual(Pixels.rgba(image, x: 70, y: 70), white)
    }

    func testSinglePointPolylineIsADot() throws {
        let image = try render(PolylineAnnotation(points: [CGPoint(x: 50, y: 50)], style: StrokeStyle(color: red, width: 10)))
        XCTAssertEqual(Pixels.rgba(image, x: 100, y: 100), redPixel)
        XCTAssertEqual(Pixels.rgba(image, x: 130, y: 100), white)
    }

    func testTranslucentStrokeDoesNotDarkenWhereItCrossesItself() throws {
        let color = AnnotationColor(red: 1, green: 0, blue: 0, alpha: 0.5)
        // Path that crosses itself at (50, 50): horizontal then vertical then back across the middle.
        let item = PolylineAnnotation(
            points: [CGPoint(x: 20, y: 50), CGPoint(x: 80, y: 50), CGPoint(x: 80, y: 20), CGPoint(x: 50, y: 20), CGPoint(x: 50, y: 80)],
            style: StrokeStyle(color: color, width: 6)
        )
        let image = try render(item)
        let crossing = Pixels.rgba(image, x: 100, y: 100) // (50pt, 50pt)
        let plain = Pixels.rgba(image, x: 60, y: 100)     // (30pt, 50pt) on one pass only
        XCTAssertEqual(crossing, plain, "single stroked path must not double-blend at self-intersections")
        XCTAssertLessThan(plain[1], 200)
        XCTAssertGreaterThan(plain[1], 100)
    }

    func testMarkerStrokeLetsTheBaseShowThrough() throws {
        let style = StrokeStyle(color: AnnotationColor(red: 1, green: 0.8, blue: 0, alpha: 0.4), width: 12)
        let image = try render(PolylineAnnotation(points: [CGPoint(x: 10, y: 50), CGPoint(x: 90, y: 50)], style: style, lineCap: .butt))
        let pixel = Pixels.rgba(image, x: 100, y: 100)
        XCTAssertEqual(pixel[3], 255)
        XCTAssertGreaterThan(pixel[2], 100, "blue channel keeps part of the white base: not fully yellow")
        XCTAssertLessThan(pixel[2], 250)
    }

    func testArrowHeadGeometry() throws {
        let head = try XCTUnwrap(ArrowGeometry.head(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), width: 3))
        XCTAssertEqual(head.tip, CGPoint(x: 100, y: 0))
        XCTAssertEqual(head.base.x, 88, accuracy: 0.0001) // head length = max(10, width * 4) = 12
        XCTAssertEqual(head.left.x, head.right.x, accuracy: 0.0001)
        XCTAssertEqual(head.left.y, -head.right.y, accuracy: 0.0001)
        XCTAssertGreaterThan(abs(head.left.y), 0)
    }

    func testArrowHeadScalesWithWidthAndIsCappedByLength() throws {
        let thick = try XCTUnwrap(ArrowGeometry.head(from: .zero, to: CGPoint(x: 200, y: 0), width: 10))
        XCTAssertEqual(200 - thick.base.x, 40, accuracy: 0.0001)
        let short = try XCTUnwrap(ArrowGeometry.head(from: .zero, to: CGPoint(x: 10, y: 0), width: 10))
        XCTAssertEqual(10 - short.base.x, 6, accuracy: 0.0001)
        XCTAssertNil(ArrowGeometry.head(from: .zero, to: .zero, width: 3))
    }

    func testArrowRendersShaftAndHeadButNotBeyondTheTip() throws {
        let image = try render(ArrowAnnotation(from: CGPoint(x: 10, y: 50), to: CGPoint(x: 90, y: 50), style: StrokeStyle(color: red, width: 4)))
        XCTAssertEqual(Pixels.rgba(image, x: 60, y: 100), redPixel)  // shaft
        XCTAssertEqual(Pixels.rgba(image, x: 170, y: 100), redPixel) // inside the head
        XCTAssertEqual(Pixels.rgba(image, x: 190, y: 100), white)    // past the tip (95pt)
    }
}
