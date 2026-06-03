import SwiftUI

/// Presentational nav row: 32pt rounded icon tile + name (Hanken 700) + sub
/// (Geist Mono) + trailing chevron. Designed to be used as the *label* of a
/// `NavigationLink`, so the surrounding link owns the push + press feedback.
/// All colors/spacing from `Theme`.
struct NavRow: View {
    enum Glyph { case symbol(String), text(String) }

    let glyph: Glyph
    let tileColor: Color
    var glyphColor: Color? = nil
    let name: String
    let sub: String

    @Environment(Theme.self) private var theme

    var body: some View {
        HStack(spacing: theme.spacing[3]) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .pulseStyle(.rowName)
                    .foregroundStyle(theme.ink)
                Text(sub)
                    .pulseStyle(.rowSub)
                    .foregroundStyle(theme.inkSoft)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.inkSoft)
        }
        .padding(.horizontal, theme.spacing[3])
        .padding(.vertical, theme.spacing[2])
        .frame(maxWidth: .infinity)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
    }

    @ViewBuilder private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.spacing[0])
                .fill(tileColor)
                .frame(width: 32, height: 32)
            switch glyph {
            case .symbol(let n):
                Image(systemName: n)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(glyphColor ?? theme.onAccent)
            case .text(let t):
                Text(t)
                    .font(PulseFont.oswald("Oswald-Bold", size: 14))
                    .foregroundStyle(glyphColor ?? theme.onAccent)
            }
        }
    }
}

#Preview {
    let theme = Theme()
    return VStack(spacing: theme.spacing[0]) {
        NavRow(glyph: .symbol("chart.bar.fill"), tileColor: theme.accent,
               name: "Stats", sub: "Volume, PRs, charts")
        NavRow(glyph: .text("PR"), tileColor: theme.accent2,
               name: "Personal records", sub: "8 lifts tracked")
        NavRow(glyph: .text("H"), tileColor: theme.inkFaint, glyphColor: theme.ink,
               name: "Workout history", sub: "183 sessions logged")
    }
    .padding()
    .background(theme.bg)
    .environment(theme)
}
