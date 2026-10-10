import CoreGraphics
import Foundation

/// An annotation with a stable identity, so removals and their undo do not depend on shifting indices.
public struct AnnotationEntry {
    public let id: UUID
    public let item: any Annotation

    public init(id: UUID = UUID(), item: any Annotation) {
        self.id = id
        self.item = item
    }
}

/// The annotations of one recording, with an undoable history of additions and removals, and flattening onto an image.
public final class AnnotationDocument {
    private enum Operation {
        case add(AnnotationEntry)
        /// Removed entries with the index each had, ascending.
        case remove([(index: Int, entry: AnnotationEntry)])
    }

    public private(set) var entries: [AnnotationEntry] = []
    private var undoStack: [Operation] = []
    private var redoStack: [Operation] = []

    /// Called after every change, so views can redraw.
    public var onChange: (() -> Void)?

    public init() {}

    public var items: [any Annotation] { entries.map(\.item) }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    public var isEmpty: Bool { entries.isEmpty }

    /// Adds an annotation. Anything that was undone can no longer be redone.
    public func add(_ item: any Annotation) {
        let entry = AnnotationEntry(item: item)
        entries.append(entry)
        undoStack.append(.add(entry))
        redoStack.removeAll()
        onChange?()
    }

    /// Removes the entries with `ids` as one undoable step. Does nothing (and records nothing) when none match.
    public func remove(ids: Set<UUID>) {
        let removed = entries.enumerated()
            .filter { ids.contains($0.element.id) }
            .map { (index: $0.offset, entry: $0.element) }
        guard !removed.isEmpty else { return }
        entries.removeAll { ids.contains($0.id) }
        undoStack.append(.remove(removed))
        redoStack.removeAll()
        onChange?()
    }

    public func undo() {
        guard let operation = undoStack.popLast() else { return }
        switch operation {
        case .add(let entry):
            entries.removeAll { $0.id == entry.id }
        case .remove(let removed):
            // Ascending order restores every entry at its original position.
            for (index, entry) in removed { entries.insert(entry, at: min(index, entries.count)) }
        }
        redoStack.append(operation)
        onChange?()
    }

    public func redo() {
        guard let operation = redoStack.popLast() else { return }
        switch operation {
        case .add(let entry):
            entries.append(entry)
        case .remove(let removed):
            let ids = Set(removed.map(\.entry.id))
            entries.removeAll { ids.contains($0.id) }
        }
        undoStack.append(operation)
        onChange?()
    }

    /// Removes every annotation. This cannot be undone: the undo and redo history is discarded as well.
    public func clearAll() {
        guard !entries.isEmpty || !undoStack.isEmpty || !redoStack.isEmpty else { return }
        entries.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        onChange?()
    }

    /// IDs of the annotations within `tolerance` of `point`.
    public func hits(at point: CGPoint, tolerance: CGFloat) -> Set<UUID> {
        Set(entries.filter { $0.item.hitTest(point, tolerance: tolerance) }.map(\.id))
    }

    /// Draws all annotations onto a copy of `base`, producing an image of the same pixel size.
    /// - Parameters:
    ///   - scale: Output pixels per point of `base`.
    ///   - origin: Global top-left point of `base`'s top-left pixel (the snip's origin).
    public func flatten(base: CGImage, scale: CGFloat, origin: CGPoint) -> CGImage? {
        guard !items.isEmpty else { return base }
        guard scale > 0,
              let context = Self.makeContext(width: base.width, height: base.height, matching: base)
        else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        context.draw(base, in: bounds)

        // Pixel space is bottom-left based; annotations use global points with a top-left origin.
        context.translateBy(x: 0, y: CGFloat(base.height))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -origin.x, y: -origin.y)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        draw(in: AnnotationRenderContext(context: context, scale: scale, base: base, origin: origin))
        return context.makeImage()
    }

    /// Draws every annotation, then `draft` (the in-progress shape) on top, each in an isolated graphics state.
    /// `context.context` must already map user space to global top-left points.
    /// Entries in `hidden` are skipped (the eraser previews its pending removals this way).
    public func draw(in context: AnnotationRenderContext, draft: (any Annotation)? = nil, hidden: Set<UUID> = []) {
        let visible = entries.filter { !hidden.contains($0.id) }.map(\.item)
        for item in visible + (draft.map { [$0] } ?? []) {
            context.context.saveGState()
            item.render(in: context)
            context.context.restoreGState()
        }
    }

    private static func makeContext(width: Int, height: Int, matching base: CGImage) -> CGContext? {
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        if let space = base.colorSpace, space.model == .rgb,
           let context = CGContext(
               data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
               space: space, bitmapInfo: bitmapInfo
           ) {
            return context
        }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: srgb, bitmapInfo: bitmapInfo
        )
    }
}
