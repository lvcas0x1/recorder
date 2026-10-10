import CoreGraphics
import Foundation

public enum ResizeHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

    var movesLeft: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesRight: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesTop: Bool { self == .topLeft || self == .top || self == .topRight }
    var movesBottom: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }

    /// The handle's position on `rect` (global top-left points).
    public func position(on rect: CGRect) -> CGPoint {
        let x: CGFloat = movesLeft ? rect.minX : (movesRight ? rect.maxX : rect.midX)
        let y: CGFloat = movesTop ? rect.minY : (movesBottom ? rect.maxY : rect.midY)
        return CGPoint(x: x, y: y)
    }
}

/// Selection state for a custom recording area, in global top-left points. Pure logic: no AppKit.
public final class SelectionModel {
    public enum Hit: Equatable {
        case handle(ResizeHandle)
        case inside
        case none
    }

    private enum Mode {
        case idle
        case creating(anchor: CGPoint)
        case resizing(handle: ResizeHandle, original: CGRect)
        case moving(grab: CGVector, size: CGSize)
    }

    /// Smallest drag (in points) that counts as a selection rather than a click.
    public static let minimumDrag: CGFloat = 3

    public let bounds: CGRect
    public let handleRadius: CGFloat
    public private(set) var rect: CGRect?
    private var mode: Mode = .idle
    private var dragStart: CGPoint = .zero
    public private(set) var didDrag = false
    private var hadSelectionOnMouseDown = false
    /// `true` after a `mouseUp` that ended a plain click outside an existing selection.
    public private(set) var endedWithOutsideClick = false

    public init(bounds: CGRect, handleRadius: CGFloat = 6) {
        self.bounds = bounds
        self.handleRadius = handleRadius
    }

    public func setRect(_ newRect: CGRect?) {
        rect = newRect.map { $0.intersection(bounds) }.flatMap { $0.isNull ? nil : $0 }
    }

    public func hitTest(_ point: CGPoint) -> Hit {
        guard let rect else { return .none }
        for handle in ResizeHandle.allCases {
            let p = handle.position(on: rect)
            if abs(p.x - point.x) <= handleRadius && abs(p.y - point.y) <= handleRadius { return .handle(handle) }
        }
        return rect.contains(point) ? .inside : .none
    }

    public func mouseDown(at raw: CGPoint) {
        let point = clamp(raw)
        dragStart = point
        didDrag = false
        endedWithOutsideClick = false
        hadSelectionOnMouseDown = rect != nil
        switch hitTest(point) {
        case .handle(let handle):
            mode = .resizing(handle: handle, original: rect!)
        case .inside:
            let r = rect!
            mode = .moving(grab: CGVector(dx: point.x - r.minX, dy: point.y - r.minY), size: r.size)
        case .none:
            mode = .creating(anchor: point)
            rect = nil
        }
    }

    public func mouseDragged(to raw: CGPoint) {
        let point = clamp(raw)
        if hypot(point.x - dragStart.x, point.y - dragStart.y) >= Self.minimumDrag { didDrag = true }
        switch mode {
        case .idle:
            break
        case .creating(let anchor):
            rect = Self.normalized(anchor, point)
        case .resizing(let handle, let original):
            var minX = original.minX, maxX = original.maxX, minY = original.minY, maxY = original.maxY
            if handle.movesLeft { minX = point.x }
            if handle.movesRight { maxX = point.x }
            if handle.movesTop { minY = point.y }
            if handle.movesBottom { maxY = point.y }
            rect = Self.normalized(CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY))
        case .moving(let grab, let size):
            var origin = CGPoint(x: point.x - grab.dx, y: point.y - grab.dy)
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
            rect = CGRect(origin: origin, size: size)
        }
    }

    /// Ends the drag. Returns `true` when the gesture was a click (no real drag) that did not create a selection.
    @discardableResult
    public func mouseUp(at raw: CGPoint) -> Bool {
        defer { mode = .idle }
        if case .creating = mode, !didDrag {
            rect = nil
            endedWithOutsideClick = hadSelectionOnMouseDown
            return true
        }
        if let r = rect, r.width < 1 || r.height < 1 { rect = nil }
        return false
    }

    public func clamp(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    static func normalized(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
