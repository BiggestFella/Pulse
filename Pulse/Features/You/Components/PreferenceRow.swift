import SwiftUI

/// A value row inside the Preferences card: label + value text + chevron.
/// Display-only in v1 (units/rest editing is out of scope; tapping is inert).
struct PreferenceValueRow: View {
    let label: String
    let value: String

    @Environment(Theme.self) private var theme

    var body: some View {
        HStack {
            Text(label)
                .font(PulseFont.hanken("HankenGrotesk-Medium", size: 15))
                .foregroundStyle(theme.ink)
            Spacer()
            Text(value)
                .pulseStyle(.rowSub)
                .foregroundStyle(theme.inkSoft)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.ink.opacity(0.4))
                .padding(.leading, theme.spacing[0])
        }
        .padding(.horizontal, theme.spacing[3])
        .padding(.vertical, theme.spacing[2])
    }
}

/// A toggle row inside the Preferences card: label + pill switch (`on` = accent).
struct PreferenceToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    @Environment(Theme.self) private var theme

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(PulseFont.hanken("HankenGrotesk-Medium", size: 15))
                .foregroundStyle(theme.ink)
        }
        .tint(theme.accent)
        .padding(.horizontal, theme.spacing[3])
        .padding(.vertical, theme.spacing[1])
    }
}

#Preview {
    @Previewable @State var auto = true
    let theme = Theme()
    return VStack(spacing: 0) {
        PreferenceValueRow(label: "Units", value: "KG · METRIC")
        PreferenceValueRow(label: "Default rest timer", value: "90s")
        PreferenceToggleRow(label: "Auto-progress weight", isOn: $auto)
    }
    .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
    .overlay(RoundedRectangle(cornerRadius: theme.radiusCard).stroke(theme.inkFaint, lineWidth: 1.5))
    .padding()
    .background(theme.bg)
    .environment(theme)
}
