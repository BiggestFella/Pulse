import SwiftUI

/// The hero card. When `card == nil` (rest/empty day) it renders the rest
/// treatment with no Start button (AC #10).
struct TodayHeroCard: View {
    @Environment(Theme.self) private var theme
    let card: TodayWorkoutCard?
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let card {
                Eyebrow(card.eyebrow, emphasis: 0.85)
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                lockup(card)
                footer(card)
            } else {
                Eyebrow("TODAY · REST DAY", emphasis: 0.85)
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                Text("Rest day.")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(theme.onAccent)
                Text("No workout scheduled — recover and come back tomorrow.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.onAccent.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("today.hero")
    }

    private func lockup(_ card: TodayWorkoutCard) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PosterNumeral(value: card.exerciseCount, size: 72, color: theme.onAccent)
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(card.dayLabel, emphasis: 0.85)
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                Text(card.name)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(theme.onAccent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.hero.name")
            }
        }
    }

    private func footer(_ card: TodayWorkoutCard) -> some View {
        HStack(alignment: .center) {
            Eyebrow(card.footerEyebrow, emphasis: 0.85)
                .foregroundStyle(theme.onAccent.opacity(0.85))
            Spacer()
            Button(action: onStart) {
                HStack(spacing: 6) {
                    Text("Start").font(.system(size: 14, weight: .bold))
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: 999))
                .overlay(RoundedRectangle(cornerRadius: 999).strokeBorder(theme.ink, lineWidth: 2))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("today.hero.start")
        }
    }
}

#Preview("Workout") {
    @Previewable @State var theme = Theme()
    return TodayHeroCard(card: .sampleCard, onStart: {})
        .padding().background(theme.bg).environment(theme)
}

#Preview("Rest day") {
    @Previewable @State var theme = Theme()
    return TodayHeroCard(card: nil, onStart: {})
        .padding().background(theme.bg).environment(theme)
}
