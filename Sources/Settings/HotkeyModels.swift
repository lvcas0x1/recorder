import Carbon.HIToolbox
import Foundation

/// The global shortcuts: one per recording mode.
public enum HotkeyAction: String, CaseIterable, Codable, Sendable {
    case fullScreen, window, area

    public var title: String {
        switch self {
        case .fullScreen: "Record Full Screen"
        case .window: "Record Window"
        case .area: "Record Area"
        }
    }
}

/// A key combination expressed in Carbon terms (virtual key code + Carbon modifier mask).
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Control-Shift-1/2/3 (design D7): avoids the system's Shift-Command-3/4/5 and Option-only combinations.
    public static let defaults: [HotkeyAction: KeyCombo] = [
        .fullScreen: KeyCombo(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(controlKey | shiftKey)),
        .window: KeyCombo(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(controlKey | shiftKey)),
        .area: KeyCombo(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(controlKey | shiftKey)),
    ]
}

public enum HotkeyError: Error, Equatable {
    case registrationFailed(OSStatus)
}
