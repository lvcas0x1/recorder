import CoreGraphics
import Foundation

/// Output video size (design D4): keep the aspect ratio, fit inside the resolution box, never upscale, even sides.
public enum OutputSize {
    /// - Parameters:
    ///   - nativePixels: The recorded area in pixels (points times the display scale).
    ///   - box: The resolution box, e.g. 1920x1080.
    public static func fit(nativePixels: CGSize, box: CGSize) -> CGSize {
        guard nativePixels.width > 0, nativePixels.height > 0 else { return .zero }
        let factor = min(1, box.width / nativePixels.width, box.height / nativePixels.height)
        return CGSize(width: even(nativePixels.width * factor), height: even(nativePixels.height * factor))
    }

    /// Rounds down to an even number, at least 2.
    static func even(_ value: CGFloat) -> CGFloat {
        max(2, (value.rounded(.down) / 2).rounded(.down) * 2)
    }
}
