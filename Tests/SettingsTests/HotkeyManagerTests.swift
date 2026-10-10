import Carbon.HIToolbox
import XCTest
@testable import Settings

private final class FakeRegistrar: HotkeyRegistrar {
    var onPress: ((UInt32) -> Void)?
    var active: [UInt32: KeyCombo] = [:]
    var refused: Set<KeyCombo> = []

    func register(_ combo: KeyCombo, id: UInt32) throws {
        if refused.contains(combo) { throw HotkeyError.registrationFailed(-9878) }
        active[id] = combo
    }

    func unregister(id: UInt32) { active[id] = nil }
}

final class HotkeyManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private let custom = KeyCombo(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey))

    override func setUp() {
        suiteName = "HotkeyManagerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStartRegistersAllDefaults() {
        let registrar = FakeRegistrar()
        let manager = HotkeyManager(store: HotkeyStore(defaults: defaults), registrar: registrar)
        XCTAssertTrue(manager.start().isEmpty)
        XCTAssertEqual(manager.registered, Set(HotkeyAction.allCases))
        XCTAssertEqual(Set(registrar.active.values), Set(KeyCombo.defaults.values))
    }

    func testRemovedActionIsNotRegistered() {
        HotkeyStore(defaults: defaults).set(nil, for: .fullScreen)
        let registrar = FakeRegistrar()
        let manager = HotkeyManager(store: HotkeyStore(defaults: defaults), registrar: registrar)
        manager.start()
        XCTAssertEqual(manager.registered, [.window, .area])
        XCTAssertFalse(registrar.active.values.contains(KeyCombo.defaults[.fullScreen]!))
    }

    func testUnbindUnregistersAndPersists() {
        let registrar = FakeRegistrar()
        let manager = HotkeyManager(store: HotkeyStore(defaults: defaults), registrar: registrar)
        manager.start()
        manager.unbind(.window)
        XCTAssertFalse(manager.registered.contains(.window))
        XCTAssertNil(HotkeyStore(defaults: defaults).combo(for: .window))
    }

    func testRebindReplacesOldCombo() throws {
        let registrar = FakeRegistrar()
        let manager = HotkeyManager(store: HotkeyStore(defaults: defaults), registrar: registrar)
        manager.start()
        try manager.rebind(.area, to: custom)
        XCTAssertTrue(registrar.active.values.contains(custom))
        XCTAssertFalse(registrar.active.values.contains(KeyCombo.defaults[.area]!))
        XCTAssertEqual(HotkeyStore(defaults: defaults).combo(for: .area), custom)
    }

    func testFailedRebindKeepsPreviousCombo() {
        let registrar = FakeRegistrar()
        registrar.refused = [custom]
        let manager = HotkeyManager(store: HotkeyStore(defaults: defaults), registrar: registrar)
        manager.start()
        XCTAssertThrowsError(try manager.rebind(.area, to: custom))
        XCTAssertTrue(registrar.active.values.contains(KeyCombo.defaults[.area]!))
        XCTAssertEqual(HotkeyStore(defaults: defaults).combo(for: .area), KeyCombo.defaults[.area])
    }

    func testRestoreDefaultAfterUnbind() throws {
        let registrar = FakeRegistrar()
        let manager = HotkeyManager(store: HotkeyStore(defaults: defaults), registrar: registrar)
        manager.start()
        manager.unbind(.fullScreen)
        try manager.restoreDefault(.fullScreen)
        XCTAssertTrue(manager.registered.contains(.fullScreen))
        XCTAssertEqual(HotkeyStore(defaults: defaults).combo(for: .fullScreen), KeyCombo.defaults[.fullScreen])
    }

    func testPressDispatchesToHandler() {
        let registrar = FakeRegistrar()
        let manager = HotkeyManager(store: HotkeyStore(defaults: defaults), registrar: registrar)
        var fired: [HotkeyAction] = []
        HotkeyAction.allCases.forEach { action in manager.setHandler(for: action) { fired.append(action) } }
        manager.start()
        registrar.onPress?(HotkeyManager.id(for: .window))
        XCTAssertEqual(fired, [.window])
    }

    func testStartReportsFailuresPerAction() {
        let registrar = FakeRegistrar()
        registrar.refused = [KeyCombo.defaults[.window]!]
        let manager = HotkeyManager(store: HotkeyStore(defaults: defaults), registrar: registrar)
        let failures = manager.start()
        XCTAssertEqual(Array(failures.keys), [.window])
        XCTAssertEqual(manager.registered, [.fullScreen, .area])
    }

    func testCarbonRegistrarRegistersAndUnregisters() throws {
        // The real Carbon path: register an unusual combination, then release it.
        let registrar = CarbonHotkeyRegistrar()
        let combo = KeyCombo(keyCode: UInt32(kVK_F19), modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey))
        try registrar.register(combo, id: 99)
        registrar.unregister(id: 99)
        try registrar.register(combo, id: 99)
        registrar.unregister(id: 99)
    }
}
