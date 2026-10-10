import AppKit
import Carbon.HIToolbox

public extension KeyCombo {
    /// Carbon modifier mask for the modifiers held in `flags`.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask = 0
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.shift) { mask |= shiftKey }
        if flags.contains(.command) { mask |= cmdKey }
        return UInt32(mask)
    }

    /// A combination is usable as a global hotkey only if it includes Control, Option, or Command.
    var hasRequiredModifier: Bool {
        modifiers & UInt32(controlKey | optionKey | cmdKey) != 0
    }

    var displayString: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "\u{2303}" }
        if modifiers & UInt32(optionKey) != 0 { text += "\u{2325}" }
        if modifiers & UInt32(shiftKey) != 0 { text += "\u{21E7}" }
        if modifiers & UInt32(cmdKey) != 0 { text += "\u{2318}" }
        return text + Self.keyName(for: keyCode)
    }

    private static let specialKeys: [Int: String] = [
        kVK_Return: "\u{21A9}", kVK_Tab: "\u{21E5}", kVK_Space: "Space", kVK_Delete: "\u{232B}",
        kVK_Escape: "\u{238B}", kVK_LeftArrow: "\u{2190}", kVK_RightArrow: "\u{2192}",
        kVK_UpArrow: "\u{2191}", kVK_DownArrow: "\u{2193}",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(for keyCode: UInt32) -> String {
        if let name = specialKeys[Int(keyCode)] { return name }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        let layout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars
        )
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}
