import XCTest
@testable import Recording

final class SegmentJoinerTests: XCTestCase {
    private func tempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SegmentJoinerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testNoSegmentsIsAnError() async {
        do {
            try await SegmentJoiner.join([], to: tempFolder().appendingPathComponent("out.mp4"))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? SegmentJoinerError, .noSegments)
        }
    }

    func testSingleSegmentIsMoved() async throws {
        let folder = tempFolder()
        let segment = folder.appendingPathComponent(".x.segment-0.mp4")
        try Data([1, 2, 3]).write(to: segment)
        let destination = folder.appendingPathComponent("Recording.mp4")
        try await SegmentJoiner.join([segment], to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), Data([1, 2, 3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: segment.path))
    }

    func testUnreadableSegmentsAreKeptOnFailure() async throws {
        let folder = tempFolder()
        let segments = (0..<2).map { folder.appendingPathComponent(".x.segment-\($0).mp4") }
        for url in segments { try Data("not a movie".utf8).write(to: url) }
        let destination = folder.appendingPathComponent("Recording.mp4")
        do {
            try await SegmentJoiner.join(segments, to: destination)
            XCTFail("expected an error")
        } catch {}
        XCTAssertTrue(segments.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "segments survive a failed join")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }
}
