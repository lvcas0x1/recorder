import Carbon.HIToolbox
import XCTest
@testable import Settings

final class HotkeyStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "HotkeyStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsAreControlShiftOneTwoThree() {
        let store = HotkeyStore(defaults: defaults)
        let expected: [HotkeyAction: Int] = [.fullScreen: kVK_ANSI_1, .window: kVK_ANSI_2, .area: kVK_ANSI_3]
        for action in HotkeyAction.allCases {
            let combo = store.combo(for: action)
            XCTAssertEqual(combo?.keyCode, UInt32(expected[action]!))
            XCTAssertEqual(combo?.modifiers, UInt32(controlKey | shiftKey))
            XCTAssertEqual(combo?.hasRequiredModifier, true)
        }
        XCTAssertEqual(store.combo(for: .fullScreen)?.displayString, "\u{2303}\u{21E7}1")
    }

    func testRebindPersistsAcrossInstances() {
        let combo = KeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey))
        HotkeyStore(defaults: defaults).set(combo, for: .area)
        XCTAssertEqual(HotkeyStore(defaults: defaults).combo(for: .area), combo)
        XCTAssertEqual(HotkeyStore(defaults: defaults).combo(for: .window), KeyCombo.defaults[.window], "others keep defaults")
    }

    func testRemovedStaysRemovedAfterReload() {
        HotkeyStore(defaults: defaults).set(nil, for: .fullScreen)
        let reloaded = HotkeyStore(defaults: defaults)
        XCTAssertNil(reloaded.combo(for: .fullScreen))
        XCTAssertEqual(reloaded.combo(for: .area), KeyCombo.defaults[.area])
    }

    func testRestoreDefaultAfterRemoval() {
        let store = HotkeyStore(defaults: defaults)
        store.set(nil, for: .window)
        store.set(KeyCombo.defaults[.window], for: .window)
        XCTAssertEqual(HotkeyStore(defaults: defaults).combo(for: .window), KeyCombo.defaults[.window])
    }

    func testUndecodableDataFallsBackToDefaults() {
        defaults.set(Data("not json".utf8), forKey: "hotkeyBindings")
        XCTAssertEqual(HotkeyStore(defaults: defaults).combo(for: .area), KeyCombo.defaults[.area])
    }
}

final class KeyComboDisplayTests: XCTestCase {
    func testModifierRequirement() {
        XCTAssertFalse(KeyCombo(keyCode: 0, modifiers: UInt32(shiftKey)).hasRequiredModifier)
        XCTAssertFalse(KeyCombo(keyCode: 0, modifiers: 0).hasRequiredModifier)
        XCTAssertTrue(KeyCombo(keyCode: 0, modifiers: UInt32(cmdKey)).hasRequiredModifier)
    }

    func testDisplayStringOrdersModifiers() {
        let combo = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey))
        XCTAssertEqual(combo.displayString, "\u{2303}\u{2325}\u{21E7}\u{2318}Space")
    }

    func testCarbonModifierMapping() {
        XCTAssertEqual(KeyCombo.carbonModifiers(from: [.command, .option]), UInt32(cmdKey | optionKey))
    }
}
