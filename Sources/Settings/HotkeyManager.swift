import Carbon.HIToolbox
import Foundation

/// Registers system-wide hotkeys. Abstracted so the manager's bookkeeping can be tested without Carbon.
public protocol HotkeyRegistrar: AnyObject {
    /// Called with the hotkey id when a registered hotkey is pressed.
    var onPress: ((UInt32) -> Void)? { get set }
    func register(_ combo: KeyCombo, id: UInt32) throws
    func unregister(id: UInt32)
}

/// Registers global hotkeys with the Carbon Event Manager.
public final class CarbonHotkeyRegistrar: HotkeyRegistrar {
    public var onPress: ((UInt32) -> Void)?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private static let signature: OSType = 0x5245_4344 // 'RECD'

    public init() {}

    deinit {
        refs.values.forEach { UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    public func register(_ combo: KeyCombo, id: UInt32) throws {
        try installEventHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { throw HotkeyError.registrationFailed(status) }
        refs[id] = ref
    }

    public func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
                )
                guard result == noErr else { return result }
                let registrar = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(userData).takeUnretainedValue()
                registrar.onPress?(hotKeyID.id)
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )
        guard status == noErr else { throw HotkeyError.registrationFailed(status) }
    }
}

/// Keeps the registered hotkeys in line with the store and dispatches presses to per-action handlers.
public final class HotkeyManager {
    public let store: HotkeyStore
    private let registrar: HotkeyRegistrar
    private var handlers: [HotkeyAction: () -> Void] = [:]
    public private(set) var registered: Set<HotkeyAction> = []

    public init(store: HotkeyStore, registrar: HotkeyRegistrar = CarbonHotkeyRegistrar()) {
        self.store = store
        self.registrar = registrar
        registrar.onPress = { [weak self] id in self?.fire(id: id) }
    }

    public func setHandler(for action: HotkeyAction, _ handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    /// Registers every action that has a shortcut; removed shortcuts are skipped. Returns the actions that failed.
    @discardableResult
    public func start() -> [HotkeyAction: Error] {
        var failures: [HotkeyAction: Error] = [:]
        for action in HotkeyAction.allCases {
            guard let combo = store.combo(for: action) else { continue }
            do { try register(action, combo: combo) } catch { failures[action] = error }
        }
        return failures
    }

    /// Rebinds `action`. On any failure the previous binding stays active and persisted.
    public func rebind(_ action: HotkeyAction, to combo: KeyCombo) throws {
        let previous = store.combo(for: action)
        unregister(action)
        do {
            try register(action, combo: combo)
        } catch {
            if let previous { try? register(action, combo: previous) }
            throw error
        }
        store.set(combo, for: action)
    }

    /// Removes the shortcut of `action`; the key combination then reaches the frontmost app.
    public func unbind(_ action: HotkeyAction) {
        unregister(action)
        store.set(nil, for: action)
    }

    public func restoreDefault(_ action: HotkeyAction) throws {
        guard let combo = KeyCombo.defaults[action] else { return }
        try rebind(action, to: combo)
    }

    private func register(_ action: HotkeyAction, combo: KeyCombo) throws {
        try registrar.register(combo, id: Self.id(for: action))
        registered.insert(action)
    }

    private func unregister(_ action: HotkeyAction) {
        registrar.unregister(id: Self.id(for: action))
        registered.remove(action)
    }

    private func fire(id: UInt32) {
        guard let action = HotkeyAction.allCases.first(where: { Self.id(for: $0) == id }) else { return }
        handlers[action]?()
    }

    static func id(for action: HotkeyAction) -> UInt32 {
        UInt32(HotkeyAction.allCases.firstIndex(of: action)! + 1)
    }
}
