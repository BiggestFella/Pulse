import SwiftUI

/// Uppercase set-type pill. `working` = solid accent fill + accent text on the
/// light pill; every other type = transparent with a white-40% border (it sits
/// on the accent hero card, so its text is `onAccent`).
struct SetTypePill: View {
    let label: String
    let isWorking: Bool
    @Environment(Theme.self) private var theme

    var body: some View {
        Text(label)
            .font(.system(.caption2, design: .monospaced)).fontWeight(.semibold)
            .tracking(2)
            .padding(.horizontal, theme.spacing[1])
            .padding(.vertical, 2)
            .foregroundStyle(isWorking ? theme.accent : theme.onAccent)
            .background(isWorking ? theme.onAccent : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(isWorking ? .clear : Color.white.opacity(0.4), lineWidth: 1.5))
            .accessibilityIdentifier("active.setTypePill")
    }
}
