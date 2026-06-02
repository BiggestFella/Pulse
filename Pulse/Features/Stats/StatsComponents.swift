import SwiftUI

/// Uppercase, tracked, monospaced micro-label with an optional color override.
/// (Stats-local; named to avoid colliding with the Today feature's `Eyebrow`,
/// which has no color parameter.)
struct StatLabel: View {
    let text: String
    var color: Color?
    @Environment(Theme.self) private var theme
    init(_ text: String, color: Color? = nil) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(color ?? theme.inkSoft)
    }
}

/// Single range pill (selected = accent fill + onAccent).
struct FilterChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void
    @Environment(Theme.self) private var theme
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? theme.onAccent : theme.ink)
                .padding(.horizontal, theme.spacing[4])
                .padding(.vertical, theme.spacing[1])
                .background(isOn ? theme.accent : theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Back chevron + STATS eyebrow + inert overflow glyph.
struct StatsTopBar: View {
    let onBack: () -> Void
    @Environment(Theme.self) private var theme
    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").foregroundStyle(theme.ink)
            }
            .accessibilityIdentifier("stats.back")
            Spacer()
            StatLabel("STATS")
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("stats.overflow")   // inert per product decision
        }
    }
}

/// One sub-stat card in the 2×2 grid.
struct SmallStatCard: View {
    let label: String
    let value: String
    var unit: String?
    let sub: String
    var valueColor: Color?
    var labelColor: Color?
    @Environment(Theme.self) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[0]) {
            StatLabel(label, color: labelColor)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(valueColor ?? theme.ink)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(theme.ink.opacity(0.6))
                }
            }
            StatLabel(sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing[3])
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
    }
}

/// One row of the volume-by-muscle list. `pct` scales the fill; `isMax` colors it accent2.
struct MuscleBarRow: View {
    let muscle: String
    let valueDisplay: String
    let pct: Double
    let isMax: Bool
    @Environment(Theme.self) private var theme
    var body: some View {
        HStack(spacing: theme.spacing[2]) {
            Text(muscle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(width: 72, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(theme.inkFaint)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isMax ? theme.accent2 : theme.accent)
                        .frame(width: max(geo.size.width * pct, 4))   // floor so near-zero is visible
                }
            }
            .frame(height: 18)
            Text(valueDisplay)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.ink)
                .frame(width: 52, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("muscle.\(muscle)")
    }
}
