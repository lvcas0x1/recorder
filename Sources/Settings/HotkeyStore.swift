import Foundation

/// Holds the action -> key combination bindings and persists them. A `nil` binding means the user removed the
/// shortcut; it stays removed across launches instead of falling back to the default.
public final class HotkeyStore {
    private struct Stored: Codable {
        var combo: KeyCombo?
    }

    private let defaults: UserDefaults
    private let storageKey: String
    public private(set) var bindings: [HotkeyAction: KeyCombo?]

    public init(defaults: UserDefaults = .standard, storageKey: String = "hotkeyBindings") {
        self.defaults = defaults
        self.storageKey = storageKey
        var loaded: [HotkeyAction: KeyCombo?] = KeyCombo.defaults.mapValues { $0 }
        if let data = defaults.data(forKey: storageKey),
           let stored = try? JSONDecoder().decode([String: Stored].self, from: data) {
            for (key, value) in stored {
                guard let action = HotkeyAction(rawValue: key) else { continue }
                loaded[action] = .some(value.combo)
            }
        }
        self.bindings = loaded
    }

    /// The current shortcut, or `nil` when it was removed.
    public func combo(for action: HotkeyAction) -> KeyCombo? {
        bindings[action] ?? nil
    }

    /// Sets (or, with `nil`, removes) the shortcut of `action`.
    public func set(_ combo: KeyCombo?, for action: HotkeyAction) {
        bindings[action] = .some(combo)
        persist()
    }

    private func persist() {
        let stored = Dictionary(uniqueKeysWithValues: bindings.map { ($0.key.rawValue, Stored(combo: $0.value)) })
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
