import AppKit
import SwiftUI

/// Resolves the user's interface font choice. `nil` or an unknown family means the system font.
public enum InterfaceFont {
    public static func isAvailable(_ family: String) -> Bool {
        NSFontManager.shared.availableFontFamilies.contains(family)
    }

    /// The family to use, or `nil` for the system font.
    public static func resolvedFamily(_ requested: String?) -> String? {
        guard let requested, !requested.isEmpty, isAvailable(requested) else { return nil }
        return requested
    }

    public static func font(family: String?, size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let family = resolvedFamily(family) {
            return .custom(family, size: size).weight(weight)
        }
        return .system(size: size, weight: weight)
    }
}

private struct InterfaceFontFamilyKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

public extension EnvironmentValues {
    var interfaceFontFamily: String? {
        get { self[InterfaceFontFamilyKey.self] }
        set { self[InterfaceFontFamilyKey.self] = newValue }
    }
}

private struct InterfaceFontModifier: ViewModifier {
    @Environment(\.interfaceFontFamily) private var family
    let size: CGFloat
    let weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(InterfaceFont.font(family: family, size: size, weight: weight))
    }
}

public extension View {
    /// Applies the user-selected interface font (or the system font) at `size`.
    func interfaceFont(size: CGFloat = 13, weight: Font.Weight = .regular) -> some View {
        modifier(InterfaceFontModifier(size: size, weight: weight))
    }
}
