import SwiftUI

/// Two-column hero composition: a giant Oswald numeral (col 1, spans both rows),
/// a Geist Mono eyebrow + a bold Hanken sub-label (col 2). Used on accent cards,
/// so the numeral defaults to `onAccent`. Pass `failure: true` to render `∞`.
struct Lockup: View {
    let value: String          // the numeral, e.g. "7"
    var top: String = ""       // eyebrow (Geist Mono), defaults to accent2
    var bottom: String = ""    // sub-label (Hanken bold)
    var size: CGFloat = 116    // numeral point size
    var failure: Bool = false
    var numeralColor: Color? = nil   // defaults to onAccent
    var topColor: Color? = nil       // defaults to accent2
    var bottomColor: Color? = nil    // defaults to numeralColor

    @Environment(Theme.self) private var theme

    /// AC9: sub-label is ~0.2× the numeral size.
    static func subLabelSize(numeralSize: CGFloat) -> CGFloat { numeralSize * 0.2 }
    /// AC9: failure renders the numeral as ∞.
    static func numeralText(value: String, failure: Bool) -> String { failure ? "∞" : value }

    var body: some View {
        let numColor = numeralColor ?? theme.onAccent
        let subColor = bottomColor ?? numColor
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                Text(Lockup.numeralText(value: value, failure: failure))
                    .font(PulseFont.hero(size: size))
                    .tracking(-0.02 * size)
                    .foregroundStyle(numColor)
                    .lineLimit(1)
                    .fixedSize()
                    .gridCellAnchor(.topLeading)
                    .gridCellColumns(1)
                    // span both rows: place the col-2 stack alongside via a VStack cell
                VStack(alignment: .leading, spacing: 0) {
                    Text(top)
                        .pulseStyle(.eyebrow)
                        .foregroundStyle(topColor ?? theme.accent2)
                        .padding(.top, size * 0.08)
                    Text(bottom)
                        .font(PulseFont.hanken("HankenGrotesk-ExtraBold",
                                               size: Lockup.subLabelSize(numeralSize: size)))
                        .tracking(-0.02 * Lockup.subLabelSize(numeralSize: size))
                        .lineSpacing(-0.05 * Lockup.subLabelSize(numeralSize: size))
                        .foregroundStyle(subColor)
                }
            }
        }
    }
}

#Preview("Lockup") {
    let theme = Theme()
    return VStack(spacing: 24) {
        Lockup(value: "7", top: "DAY 23", bottom: "Chest & Tris.", size: 116)
            .padding(20)
            .background(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.ink, lineWidth: 2))
        Lockup(value: "0", top: "TO FAILURE", bottom: "Reps logged", size: 116, failure: true)
            .padding(20)
            .background(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.ink, lineWidth: 2))
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.bg)
    .environment(theme)
}
