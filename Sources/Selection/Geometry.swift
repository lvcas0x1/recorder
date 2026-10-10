import CoreGraphics
import Foundation

/// A display's placement in global screen points (origin at the top-left of the main display, y grows downward).
public struct DisplayGeometry: Equatable {
    public let id: UInt32
    public let frame: CGRect
    /// Pixels per point (2 on Retina).
    public let scale: CGFloat

    public init(id: UInt32, frame: CGRect, scale: CGFloat) {
        self.id = id
        self.frame = frame
        self.scale = scale
    }
}

public enum Geometry {
    /// Rounds a point-space interval to whole pixels so adjacent rects share edges and sizes never drift.
    static func pixelRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let minX = (rect.minX * scale).rounded()
        let minY = (rect.minY * scale).rounded()
        let maxX = (rect.maxX * scale).rounded()
        let maxY = (rect.maxY * scale).rounded()
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Converts an AppKit rect (origin at the bottom-left of the main display) to global top-left points.
    public static func topLeftRect(fromAppKit rect: CGRect, primaryDisplayHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryDisplayHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Pixel rectangle of `selection` within one display's image, or `nil` when they do not overlap.
    public static func cropRect(selection: CGRect, in display: DisplayGeometry) -> CGRect? {
        let overlap = selection.intersection(display.frame)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return nil }
        let local = overlap.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        let crop = pixelRect(local, scale: display.scale)
        return crop.width > 0 && crop.height > 0 ? crop : nil
    }
}
