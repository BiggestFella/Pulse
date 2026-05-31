import SwiftUI

/// You → Palette: a horizontal swatch row. Each swatch previews a palette's
/// accent / accent2 / surface; the active one wears a 2px accent2 ring. Tapping
/// re-skins the whole app instantly with NO background animation (AC3/AC12).
struct PaletteView: View {
    @Environment(Theme.self) private var theme
    private var model: PaletteModel { PaletteModel(theme: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PALETTE").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
            HStack(spacing: 12) {
                ForEach(model.available, id: \.self) { palette in
                    swatch(palette)
                }
            }
        }
        .accessibilityIdentifier("palette-picker")
    }

    private func swatch(_ palette: Palette) -> some View {
        let isSelected = model.selected == palette
        let tokens = palette.tokens
        return Button {
            // No withAnimation — instant re-skin (AC3).
            model.select(palette)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: theme.radiusChip)
                    .fill(Color(hex: tokens.surface))
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: tokens.accent)).frame(width: 16, height: 16)
                    Circle().fill(Color(hex: tokens.accent2)).frame(width: 16, height: 16)
                }
            }
            .frame(width: 72, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: theme.radiusChip)
                    .stroke(isSelected ? theme.accent2 : theme.inkFaint,
                            lineWidth: isSelected ? 2 : 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("palette-swatch-\(palette.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Palette") {
    let theme = Theme()
    return PaletteView()
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .environment(theme)
}
