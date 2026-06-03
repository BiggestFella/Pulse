import SwiftUI

/// A flat `surface` card: Geist Mono eyebrow + Oswald numeral + optional small
/// Hanken unit. Color treatment per the spec — STREAK → accent2 eyebrow+numeral;
/// VOLUME → accent eyebrow, ink numeral; SESSIONS → inkSoft eyebrow, ink numeral.
/// All colors/spacing from `Theme`.
struct MiniStat: View {
    enum Tint { case accent, accent2, neutral }

    let label: String
    let value: String
    var unit: String = ""
    var tint: Tint = .neutral

    @Environment(Theme.self) private var theme

    private var eyebrowColor: Color {
        switch tint {
        case .accent: return theme.accent
        case .accent2: return theme.accent2
        case .neutral: return theme.inkSoft
        }
    }
    private var numeralColor: Color {
        tint == .accent2 ? theme.accent2 : theme.ink
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[0]) {
            Text(label)
                .pulseStyle(.eyebrow)
                .foregroundStyle(eyebrowColor)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(PulseFont.oswald("Oswald-Bold", size: 24))
                    .foregroundStyle(numeralColor)
                if !unit.isEmpty {
                    Text(unit)
                        .font(PulseFont.hanken("HankenGrotesk-Bold", size: 11))
                        .foregroundStyle(theme.ink.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing[2])
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusChip))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)\(unit)")
    }
}

#Preview {
    let theme = Theme()
    return HStack(spacing: theme.spacing[0]) {
        MiniStat(label: "STREAK", value: "27", unit: "d", tint: .accent2)
        MiniStat(label: "SESSIONS", value: "183")
        MiniStat(label: "VOLUME", value: "2.1", unit: "M", tint: .accent)
    }
    .padding()
    .background(theme.bg)
    .environment(theme)
}
