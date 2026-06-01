import SwiftUI

/// Tappable recap of the most recent prior session → pushes Session Detail (stub).
struct YesterdayRow: View {
    @Environment(Theme.self) private var theme
    let recap: SessionRecap
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recap.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.ink)
                    Text(recap.subline)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(theme.inkSoft)
            }
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .opacity(0.85)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("today.yesterday")
    }
}

#Preview {
    @Previewable @State var theme = Theme()
    return YesterdayRow(recap: TodaySnapshot.sampleRecap, onTap: {})
        .padding().background(theme.bg).environment(theme)
}
