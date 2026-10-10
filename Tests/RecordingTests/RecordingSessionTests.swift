import XCTest
@testable import Recording

@MainActor
private final class FakeEngine: RecordingEngineType {
    var elapsed = ElapsedTime()
    var segments: [URL] = []
    var showsCursor = true
    var onFailure: ((Error) -> Void)?
    var calls: [String] = []
    var startError: Error?
    let base: URL

    init(base: URL) { self.base = base }

    private func newSegment() { segments.append(base.appendingPathExtension("\(segments.count)")) }

    func start() async throws {
        calls.append("start")
        if let startError { throw startError }
    }
    func pause() async throws { calls.append("pause"); newSegment() }
    func resume() async throws { calls.append("resume") }
    func setShowsCursor(_ shows: Bool) async throws { calls.append("cursor \(shows)"); showsCursor = shows }
    func stop() async throws -> [URL] { calls.append("stop"); newSegment(); return segments }
}

private struct TestError: Error, Equatable {}

@MainActor
final class RecordingSessionTests: XCTestCase {
    private var folder: URL!
    private var engine: FakeEngine?
    private var joined: [([URL], URL)] = []
    private var events: [String] = []
    private var engineStartError: Error?

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingSessionTests-\(UUID().uuidString)")
        joined = []
        events = []
        engine = nil
        engineStartError = nil
    }

    override func tearDown() async throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }

    private var joinError: Error?

    private func makeSession() -> RecordingSession {
        let date = Date(timeIntervalSince1970: 1_791_641_002)
        let session = RecordingSession(
            outputFolder: { [unowned self] in self.folder },
            now: { date },
            makeEngine: { [unowned self] _, base in
                let engine = FakeEngine(base: base)
                engine.startError = self.engineStartError
                self.engine = engine
                return engine
            },
            join: { [unowned self] segments, destination in
                if let error = self.joinError { throw error }
                self.joined.append((segments, destination))
            }
        )
        session.onBeginSelection = { [unowned self] mode in self.events.append("select \(mode.rawValue)") }
        session.onEnded = { [unowned self] in self.events.append("ended") }
        session.onSaved = { [unowned self] url in self.events.append("saved \(url.lastPathComponent)") }
        session.onError = { [unowned self] error in self.events.append("error \(error)") }
        return session
    }

    private func startRecording(_ session: RecordingSession, mode: RecordingMode = .area) async {
        await session.request(mode)
        await session.selectionCompleted(.area(CGRect(x: 0, y: 0, width: 100, height: 100)))
    }

    func testRequestStartsSelectionThenRecording() async {
        let session = makeSession()
        await session.request(.window)
        XCTAssertEqual(session.state, .selecting(.window))
        XCTAssertEqual(events, ["select window"])
        await session.selectionCompleted(.window(id: 7, frame: CGRect(x: 0, y: 0, width: 10, height: 10)))
        XCTAssertEqual(session.state, .recording)
        XCTAssertEqual(engine?.calls, ["start"])
    }

    func testCancelSelectionReturnsToIdleWithoutFile() async {
        let session = makeSession()
        await session.request(.area)
        session.selectionCancelled()
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(engine)
        XCTAssertTrue(joined.isEmpty)
    }

    func testOneRecordingAtATime() async {
        let session = makeSession()
        await session.request(.area)
        await session.request(.window)
        XCTAssertEqual(session.state, .selecting(.area), "a second start during selection is ignored")
        XCTAssertEqual(events, ["select area"])
    }

    func testShortcutStopsRecording() async {
        let session = makeSession()
        await startRecording(session)
        await session.request(.fullScreen)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(engine?.calls, ["start", "stop"])
        XCTAssertEqual(events.filter { $0.hasPrefix("select") }, ["select area"], "no new recording starts")
        XCTAssertEqual(joined.count, 1)
    }

    func testShortcutStopsPausedRecording() async {
        let session = makeSession()
        await startRecording(session)
        await session.togglePause()
        XCTAssertEqual(session.state, .paused)
        await session.request(.window)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(engine?.calls, ["start", "pause", "stop"])
    }

    func testPauseResumeAndJoinAllSegments() async {
        let session = makeSession()
        await startRecording(session)
        await session.togglePause()
        await session.togglePause()
        XCTAssertEqual(session.state, .recording)
        await session.togglePause()
        await session.togglePause()
        await session.stop()
        XCTAssertEqual(engine?.calls, ["start", "pause", "resume", "pause", "resume", "stop"])
        XCTAssertEqual(joined.first?.0.count, 3)
        XCTAssertEqual(joined.first?.1.lastPathComponent, "Recording 2026-10-10 \(hourString()).03.22.mp4")
        XCTAssertTrue(events.contains { $0.hasPrefix("saved Recording 2026-10-10") })
        XCTAssertEqual(events.last, "ended")
    }

    func testStopWhilePausedSaves() async {
        let session = makeSession()
        await startRecording(session)
        await session.togglePause()
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(joined.count, 1)
    }

    func testCursorToggleIsForwarded() async {
        let session = makeSession()
        await startRecording(session)
        await session.setShowsCursor(false)
        XCTAssertEqual(session.showsCursor, false)
        XCTAssertEqual(engine?.calls, ["start", "cursor false"])
    }

    func testReadOnlyFolderReportsErrorWithoutStarting() async throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        let session = makeSession()
        await startRecording(session)
        XCTAssertEqual(session.state, .idle)
        XCTAssertNil(engine, "no engine is built")
        XCTAssertTrue(events.contains { $0.contains("folderNotWritable") && $0.contains(folder.lastPathComponent) })
    }

    func testEngineStartFailureEndsSession() async {
        engineStartError = TestError()
        let session = makeSession()
        await startRecording(session)
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(events.suffix(2), ["ended", "error TestError()"])
    }

    func testEngineFailureKeepsWrittenPartAndReportsError() async throws {
        let session = makeSession()
        await startRecording(session)
        await session.togglePause()
        await session.togglePause()
        engine?.onFailure?(TestError())
        for _ in 0..<20 where session.state != .idle { await Task.yield() }
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(joined.count, 1, "the segments written so far are joined")
        XCTAssertTrue(events.contains { $0.hasPrefix("saved") })
        XCTAssertEqual(events.last, "error TestError()")
    }

    func testFailedJoinReportsErrorAndDoesNotClaimSaved() async {
        joinError = TestError()
        let session = makeSession()
        await startRecording(session)
        await session.togglePause()
        await session.togglePause()
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        XCTAssertFalse(events.contains { $0.hasPrefix("saved") })
        XCTAssertEqual(events.dropLast().last, "ended")
        XCTAssertTrue(events.last?.hasPrefix("error joinFailed") == true, "the error carries the kept segments")
    }

    func testPauseIgnoredWhenIdle() async {
        let session = makeSession()
        await session.togglePause()
        await session.stop()
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(events.isEmpty)
    }

    private func hourString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        return formatter.string(from: Date(timeIntervalSince1970: 1_791_641_002))
    }
}
