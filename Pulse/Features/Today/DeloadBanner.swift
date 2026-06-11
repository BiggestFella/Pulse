import SwiftUI

/// Advisory, dismissible "consider a deload" banner. Display-only — it never
/// changes the program. Eyebrow uses Geist Mono via `.pulseStyle(.eyebrow)`.
struct DeloadBanner: View {
    @Environment(Theme.self) private var theme
    let suggestion: DeloadSuggestion
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing[2]) {
            VStack(alignment: .leading, spacing: theme.spacing[0]) {
                Text("FATIGUE")
                    .pulseStyle(.eyebrow)
                    .foregroundStyle(theme.inkSoft)
                Text(suggestion.title)
                    .pulseStyle(.rowName)
                    .foregroundStyle(theme.ink)
                Text(suggestion.message)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark").foregroundStyle(theme.inkSoft)
            }
            .accessibilityIdentifier("today.deload.dismiss")
        }
        .padding(theme.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: theme.radiusCard)
            .strokeBorder(theme.accent2, lineWidth: 2))
        .accessibilityIdentifier("today.deloadBanner")
    }
}
