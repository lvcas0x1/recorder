import AVFoundation
import Foundation
import ScreenCaptureKit
import os

public enum RecordingEngineError: Error, Equatable {
    case unsupportedFileType
    case unsupportedCodec
    case notRunning
    case alreadyRunning
    /// ScreenCaptureKit did not report the recording output starting or finishing in time.
    case timedOut
}

/// Records one `SCStream` into MP4 segments with `SCRecordingOutput`.
///
/// `SCRecordingOutput` has no pause, so every pause (and every configuration change, which stops a recording output)
/// finishes the current segment; resuming adds a new recording output writing the next segment. The caller joins the
/// segments when the session ends (see `SegmentJoiner`).
///
/// Main-actor isolated; ScreenCaptureKit delegate callbacks are forwarded to the main actor. Callbacks can arrive
/// before the engine starts waiting for them, so each one is recorded in `OutputEvents` first.
@MainActor
public final class RecordingEngine: NSObject {
    public enum State: Equatable {
        case idle, recording, paused, stopped
    }

    /// How long to wait for ScreenCaptureKit to report that a recording output started or finished.
    static let callbackTimeout: TimeInterval = 5

    private struct OutputEvents {
        var started = false
        var finished = false
        var error: Error?
    }

    private enum Wait { case start, finish }

    private let log = Logger(subsystem: "dev.lvcas0x1.recorder", category: "engine")
    private let filter: SCContentFilter
    private var configuration: SCStreamConfiguration
    private let segmentBase: URL
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private var events = OutputEvents()
    private var waiter: (kind: Wait, continuation: CheckedContinuation<Void, Error>)?

    public private(set) var state: State = .idle
    /// Finished segment files, in recording order.
    public private(set) var segments: [URL] = []
    public private(set) var elapsed = ElapsedTime()
    /// Called on the main thread when the stream or a recording output fails outside of a call to this engine.
    public var onFailure: ((Error) -> Void)?
    /// Called when the microphone could not be started (for example, access was just denied) and the recording went
    /// ahead without it (spec: Microphone denied).
    public var onMicrophoneUnavailable: (() -> Void)?

    /// - Parameter segmentBase: Path prefix for segment files; segment n is written to `<segmentBase>-<n>.mp4`.
    public init(filter: SCContentFilter, configuration: SCStreamConfiguration, segmentBase: URL) {
        self.filter = filter
        self.configuration = configuration
        self.segmentBase = segmentBase
    }

    public var showsCursor: Bool { configuration.showsCursor }

    public func start() async throws {
        guard state == .idle else { throw RecordingEngineError.alreadyRunning }
        do {
            try await startStream()
        } catch where configuration.captureMicrophone {
            // The microphone is the usual cause (access denied in the system prompt): retry once without it.
            log.error("start failed with microphone: \(String(describing: error), privacy: .public); retrying without")
            await discardStream()
            configuration.captureMicrophone = false
            try await startStream()
            onMicrophoneUnavailable?()
        }
        state = .recording
        elapsed.resume(at: Date())
    }

    /// Creates the stream, adds the first recording output, starts capture, and waits for the output to start.
    private func startStream() async throws {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        let output = try makeOutput()
        // Added before startCapture so the first captured sample is written (SCStream.h, addRecordingOutput).
        try stream.addRecordingOutput(output)
        self.output = output
        try await stream.startCapture()
        log.notice("capture started")
        try await wait(for: .start)
    }

    private func discardStream() async {
        if let stream {
            if let output { try? stream.removeRecordingOutput(output) }
            try? await stream.stopCapture()
        }
        stream = nil
        output = nil
        try? FileManager.default.removeItem(at: segmentURL(segments.count))
    }

    public func pause() async throws {
        guard state == .recording else { throw RecordingEngineError.notRunning }
        try await finishSegment()
        state = .paused
    }

    public func resume() async throws {
        guard state == .paused, let stream else { throw RecordingEngineError.notRunning }
        let output = try makeOutput()
        try stream.addRecordingOutput(output)
        self.output = output
        try await wait(for: .start)
        state = .recording
        elapsed.resume(at: Date())
    }

    /// Changes whether the cursor is captured. A configuration update stops a running recording output
    /// (SCStream.h, removeRecordingOutput), so a running recording is split into a new segment around the update.
    public func setShowsCursor(_ shows: Bool) async throws {
        guard configuration.showsCursor != shows else { return }
        configuration.showsCursor = shows
        guard let stream else { return }
        let wasRecording = state == .recording
        if wasRecording { try await finishSegment() }
        try await stream.updateConfiguration(configuration)
        if wasRecording {
            state = .paused
            try await resume()
        }
    }

    /// Finishes the last segment and stops the stream. Returns the finished segments.
    @discardableResult
    public func stop() async throws -> [URL] {
        guard state == .recording || state == .paused, let stream else { throw RecordingEngineError.notRunning }
        var finishError: Error?
        if state == .recording {
            do { try await finishSegment() } catch { finishError = error }
        }
        state = .stopped
        try? await stream.stopCapture()
        self.stream = nil
        if let finishError { throw finishError }
        return segments
    }

    // MARK: Segments

    private func makeOutput() throws -> SCRecordingOutput {
        let config = SCRecordingOutputConfiguration()
        guard config.availableOutputFileTypes.contains(.mp4) else { throw RecordingEngineError.unsupportedFileType }
        guard config.availableVideoCodecTypes.contains(.h264) else { throw RecordingEngineError.unsupportedCodec }
        config.outputFileType = .mp4
        config.videoCodecType = .h264
        config.mixesAudioWithMicrophone = true
        config.outputURL = segmentURL(segments.count)
        try? FileManager.default.removeItem(at: config.outputURL)
        events = OutputEvents()
        return SCRecordingOutput(configuration: config, delegate: self)
    }

    private func segmentURL(_ index: Int) -> URL {
        segmentBase.deletingLastPathComponent()
            .appendingPathComponent("\(segmentBase.lastPathComponent)-\(index).mp4")
    }

    /// Removes the current recording output and keeps its file as a segment. A missing finish callback does not hang
    /// the session: after the timeout the file is kept if it exists.
    private func finishSegment() async throws {
        guard let stream, let output else { return }
        let duration = output.recordedDuration
        var finishError: Error?
        do {
            try stream.removeRecordingOutput(output)
            try await wait(for: .finish)
        } catch {
            log.error("finishing segment: \(String(describing: error), privacy: .public)")
            finishError = error
        }
        let measured = duration.isValid && duration.seconds > 0 ? duration.seconds : nil
        elapsed.pause(at: Date(), measured: measured)
        let url = segmentURL(segments.count)
        if FileManager.default.fileExists(atPath: url.path) { segments.append(url) }
        self.output = nil
        if let finishError, segments.isEmpty { throw finishError }
    }

    // MARK: Waiting for callbacks

    private func wait(for kind: Wait) async throws {
        if let error = events.error { throw error }
        switch kind {
        case .start where events.started: return
        case .finish where events.finished: return
        default: break
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            waiter = (kind, continuation)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.callbackTimeout * 1_000_000_000))
                self?.resolveWaiter(kind: kind, error: RecordingEngineError.timedOut)
            }
        }
    }

    /// Resumes the waiter for `kind` (any waiter when `kind` is nil). Returns whether a waiter was resumed.
    @discardableResult
    private func resolveWaiter(kind: Wait?, error: Error?) -> Bool {
        guard let current = waiter, kind == nil || current.kind == kind else { return false }
        waiter = nil
        if let error { current.continuation.resume(throwing: error) } else { current.continuation.resume() }
        return true
    }

    private func outputStarted() {
        log.notice("recording output started")
        events.started = true
        resolveWaiter(kind: .start, error: nil)
    }

    private func outputFinished() {
        log.notice("recording output finished")
        events.finished = true
        resolveWaiter(kind: .finish, error: nil)
    }

    private func outputFailed(_ error: Error) {
        log.error("recording output failed: \(String(describing: error), privacy: .public)")
        events.error = error
        if !resolveWaiter(kind: nil, error: error), state == .recording {
            onFailure?(error)
        }
    }

    private func streamStopped(_ error: Error) {
        log.error("stream stopped: \(String(describing: error), privacy: .public)")
        if !resolveWaiter(kind: nil, error: error), state == .recording || state == .paused {
            onFailure?(error)
        }
    }
}

extension RecordingEngine: SCRecordingOutputDelegate {
    nonisolated public func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.outputStarted() }
    }

    nonisolated public func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.outputFailed(error) }
    }

    nonisolated public func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.outputFinished() }
    }
}

extension RecordingEngine: SCStreamDelegate {
    nonisolated public func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.streamStopped(error) }
    }
}
