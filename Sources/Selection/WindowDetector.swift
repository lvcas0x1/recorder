import CoreGraphics
import Foundation

public struct WindowInfo: Equatable {
    public let id: UInt32
    public let ownerPID: Int32
    /// Window bounds in global top-left points.
    public let frame: CGRect
    public let layer: Int

    public init(id: UInt32, ownerPID: Int32, frame: CGRect, layer: Int) {
        self.id = id
        self.ownerPID = ownerPID
        self.frame = frame
        self.layer = layer
    }
}

public enum WindowDetector {
    /// Windows smaller than this (in either dimension) are never offered for selection.
    public static let minimumSide: CGFloat = 10

    /// Snapshot of on-screen windows ordered front to back (as documented for `kCGWindowListOptionOnScreenOnly`).
    public static func snapshot(excludingPID: Int32 = ProcessInfo.processInfo.processIdentifier) -> [WindowInfo] {
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return parse(raw, excludingPID: excludingPID)
    }

    /// Converts raw window dictionaries to `WindowInfo`, dropping windows that should not be selectable.
    public static func parse(_ dictionaries: [[String: Any]], excludingPID: Int32) -> [WindowInfo] {
        dictionaries.compactMap { dict in
            guard let id = (dict[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (dict[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (dict[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            let alpha = (dict[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard pid != excludingPID,
                  layer >= 0,
                  alpha > 0,
                  frame.width >= minimumSide,
                  frame.height >= minimumSide
            else { return nil }
            return WindowInfo(id: id, ownerPID: pid, frame: frame, layer: layer)
        }
    }

    /// The frontmost window containing `point`. `windows` must be ordered front to back.
    public static func hit(_ point: CGPoint, in windows: [WindowInfo]) -> WindowInfo? {
        windows.first { $0.frame.contains(point) }
    }
}
