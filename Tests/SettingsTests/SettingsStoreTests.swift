import XCTest
@testable import Settings

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "SettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaults() {
        let values = SettingsStore(defaults: defaults).values
        XCTAssertEqual(values.resolution, .p1080)
        XCTAssertTrue(values.systemAudio)
        XCTAssertFalse(values.microphone)
        XCTAssertTrue(values.recordCursor)
        XCTAssertEqual(values.outputFolder, (NSHomeDirectory() as NSString).appendingPathComponent("Movies/Recorder"))
    }

    func testPersistenceRoundTrip() {
        let first = SettingsStore(defaults: defaults)
        first.values.resolution = .p2160
        first.values.systemAudio = false
        first.values.microphone = true
        first.values.recordCursor = false
        first.values.outputFolder = "/tmp/rec"
        XCTAssertEqual(SettingsStore(defaults: defaults).values, first.values)
    }

    func testMissingFieldsFallBackToDefaults() {
        defaults.set(Data(#"{"microphone":true}"#.utf8), forKey: "settingsValues")
        let values = SettingsStore(defaults: defaults).values
        XCTAssertTrue(values.microphone)
        XCTAssertTrue(values.recordCursor)
        XCTAssertEqual(values.resolution, .p1080)
    }

    func testResolutionBoxes() {
        XCTAssertEqual(Resolution.p720.box, CGSize(width: 1280, height: 720))
        XCTAssertEqual(Resolution.p1080.box, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(Resolution.p2160.box, CGSize(width: 3840, height: 2160))
    }
}
