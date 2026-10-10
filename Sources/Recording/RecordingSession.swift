import Foundation
import Selection

/// What `RecordingSession` needs from an engine; `RecordingEngine` is the real one, tests use a fake.
@MainActor
public protocol RecordingEngineType: AnyObject {
    var elapsed: ElapsedTime { get }
    var segments: [URL] { get }
    var showsCursor: Bool { get }
    var onFailure: ((Error) -> Void)? { get set }
    func start() async throws
    func pause() async throws
    func resume() async throws
    func setShowsCursor(_ shows: Bool) async throws
    func stop() async throws -> [URL]
}

extension RecordingEngine: RecordingEngineType {}

public enum RecordingSessionError: Error {
    /// The segments could not be joined; they are kept in the output folder (design D11).
    case joinFailed(segments: [URL], underlying: Error)
}

public enum RecordingMode: String, CaseIterable, Sendable {
    case fullScreen, window, area
}

/// The recording state machine (design D2/D11): idle → selecting → starting → recording ⇄ paused → finishing → idle.
/// UI and ScreenCaptureKit specifics are injected so the transitions can be tested.
@MainActor
public final class RecordingSession {
    public enum State: Equatable {
        case idle
        case selecting(RecordingMode)
        case starting
        case recording
        case paused
        case finishing
    }

    /// Builds (but does not start) the engine for `target`, writing segments under `segmentBase`. The app shows the
    /// overlay, frame, and toolbox here, before the capture filter is built.
    public typealias EngineFactory = (_ target: RecordingTarget, _ segmentBase: URL) async throws -> RecordingEngineType
    public typealias Joiner = (_ segments: [URL], _ destination: URL) async throws -> Void

    public private(set) var state: State = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    public var onStateChange: ((State) -> Void)?
    /// The UI must show the selection for the mode, then call `selectionCompleted` or `selectionCancelled`.
    /// Full screen mode goes straight to `selectionCompleted(.fullScreen)`.
    public var onBeginSelection: ((RecordingMode) -> Void)?
    /// The recording ended (saved or failed): remove the frame, toolbox, and annotations.
    public var onEnded: (() -> Void)?
    public var onSaved: ((URL) -> Void)?
    public var onError: ((Error) -> Void)?

    private let outputFolder: () -> URL
    private let now: () -> Date
    private let makeEngine: EngineFactory
    private let join: Joiner
    private var engine: RecordingEngineType?
    private var destination: URL?

    public init(
        outputFolder: @escaping () -> URL,
        now: @escaping () -> Date = Date.init,
        makeEngine: @escaping EngineFactory,
        join: @escaping Joiner = { try await SegmentJoiner.join($0, to: $1) }
    ) {
        self.outputFolder = outputFolder
        self.now = now
        self.makeEngine = makeEngine
        self.join = join
    }

    public var elapsed: TimeInterval { engine?.elapsed.value(at: now()) ?? 0 }
    public var showsCursor: Bool? { engine?.showsCursor }

    /// A mode shortcut or menu item. Starts a selection when idle, stops a running or paused recording, and is
    /// ignored while a selection, start, or finish is in progress.
    public func request(_ mode: RecordingMode) async {
        switch state {
        case .idle:
            state = .selecting(mode)
            onBeginSelection?(mode)
        case .recording, .paused:
            await stop()
        case .selecting, .starting, .finishing:
            break
        }
    }

    public func selectionCancelled() {
        guard case .selecting = state else { return }
        state = .idle
    }

    public func selectionCompleted(_ target: RecordingTarget) async {
        guard case .selecting = state else { return }
        state = .starting
        let folder = outputFolder()
        do {
            try OutputFiles.prepareFolder(folder)
        } catch {
            fail(error, cleanUp: true)
            return
        }
        let baseName = OutputFiles.baseName(for: now())
        destination = OutputFiles.uniqueURL(folder: folder, baseName: baseName)
        do {
            let engine = try await makeEngine(target, OutputFiles.segmentBase(folder: folder, baseName: baseName))
            self.engine = engine
            engine.onFailure = { [weak self] error in
                Task { @MainActor in await self?.engineFailed(error) }
            }
            try await engine.start()
            state = .recording
        } catch {
            engine = nil
            fail(error, cleanUp: true)
        }
    }

    public func togglePause() async {
        guard let engine else { return }
        do {
            switch state {
            case .recording:
                try await engine.pause()
                state = .paused
            case .paused:
                try await engine.resume()
                state = .recording
            default:
                return
            }
        } catch {
            await engineFailed(error)
        }
    }

    public func setShowsCursor(_ shows: Bool) async {
        guard let engine, state == .recording || state == .paused else { return }
        do {
            try await engine.setShowsCursor(shows)
        } catch {
            await engineFailed(error)
        }
    }

    public func stop() async {
        guard state == .recording || state == .paused, let engine else { return }
        state = .finishing
        var stopError: Error?
        do { _ = try await engine.stop() } catch { stopError = error }
        await finish(segments: engine.segments, error: stopError)
    }

    // MARK: Ending

    /// The stream or a recording output failed: keep whatever was written, then report the error.
    private func engineFailed(_ error: Error) async {
        guard state == .recording || state == .paused, let engine else { return }
        state = .finishing
        _ = try? await engine.stop()
        await finish(segments: engine.segments, error: error)
    }

    private func finish(segments: [URL], error: Error?) async {
        var reported = error
        if let destination, !segments.isEmpty {
            do {
                try await join(segments, destination)
                onSaved?(destination)
            } catch {
                reported = reported ?? RecordingSessionError.joinFailed(segments: segments, underlying: error)
            }
        }
        engine = nil
        destination = nil
        state = .idle
        onEnded?()
        if let reported { onError?(reported) }
    }

    private func fail(_ error: Error, cleanUp: Bool) {
        destination = nil
        state = .idle
        if cleanUp { onEnded?() }
        onError?(error)
    }
}
