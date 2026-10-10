import SwiftUI

/// Rounded floating container on a system material; follows light/dark appearance automatically.
public struct FloatingToolbar<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: DS.Spacing.small) { content }
            .padding(DS.Spacing.medium)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.panel, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

/// Icon button with an accessibility label; the active state uses the system accent color.
public struct ToolbarButton: View {
    private let symbol: String
    private let label: String
    private let isActive: Bool
    private let isEnabled: Bool
    private let action: () -> Void

    public init(symbol: String, label: String, isActive: Bool = false, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.isActive = isActive
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 30, height: 28)
                .foregroundStyle(isActive ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                        .fill(isActive ? Color.accentColor : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
