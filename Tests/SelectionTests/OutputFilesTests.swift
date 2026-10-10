import XCTest
@testable import Selection

final class OutputFilesTests: XCTestCase {
    // 2026-10-10 14:03:22 UTC
    private let date = Date(timeIntervalSince1970: 1_791_641_002)
    private let utc = TimeZone(identifier: "UTC")!

    private func makeTempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OutputFilesTests-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testBaseNameMatchesSpec() {
        XCTAssertEqual(OutputFiles.baseName(for: date, timeZone: utc), "Recording 2026-10-10 14.03.22")
    }

    func testUniqueURLUsesMP4() {
        let folder = makeTempFolder()
        let url = OutputFiles.uniqueURL(folder: folder, baseName: "Recording 2026-10-10 14.03.22")
        XCTAssertEqual(url.lastPathComponent, "Recording 2026-10-10 14.03.22.mp4")
    }

    func testNameCollisionNeverOverwrites() throws {
        let folder = makeTempFolder()
        try OutputFiles.prepareFolder(folder)
        let first = OutputFiles.uniqueURL(folder: folder, baseName: "A")
        try Data([1]).write(to: first)
        let second = OutputFiles.uniqueURL(folder: folder, baseName: "A")
        try Data([2]).write(to: second)
        let third = OutputFiles.uniqueURL(folder: folder, baseName: "A")
        XCTAssertEqual([first, second, third].map(\.lastPathComponent), ["A.mp4", "A 2.mp4", "A 3.mp4"])
        XCTAssertEqual(try Data(contentsOf: first), Data([1]))
    }

    func testPrepareFolderCreatesMissingFolders() throws {
        let folder = makeTempFolder().appendingPathComponent("nested/deeper")
        try OutputFiles.prepareFolder(folder)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func testReadOnlyFolderIsReported() throws {
        let folder = makeTempFolder()
        try OutputFiles.prepareFolder(folder)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        addTeardownBlock { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        XCTAssertThrowsError(try OutputFiles.prepareFolder(folder)) { error in
            XCTAssertEqual(error as? OutputFilesError, .folderNotWritable(folder.path))
        }
    }

    func testSegmentBaseIsHiddenInFolder() {
        let folder = URL(fileURLWithPath: "/tmp/out")
        XCTAssertEqual(OutputFiles.segmentBase(folder: folder, baseName: "Recording X").path, "/tmp/out/.Recording X.segment")
    }
}
