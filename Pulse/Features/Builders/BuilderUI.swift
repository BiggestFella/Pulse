import SwiftUI

/// Pill chip with the design-system ink border + capsule fill. Used for tags,
/// muscle-group filters, and per-set type selection inside the builders.
/// (Distinct from `FilterChip` — this exposes selectable fill/onFill colors so
/// the same chip serves both `accent` and `accent2` selection styles.)
struct PillChip: View {
    let label: String
    let selected: Bool
    var fill: Color
    var onFill: Color
    let action: () -> Void
    @Environment(Theme.self) private var theme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(selected ? onFill : theme.inkSoft)
                .padding(.horizontal, theme.spacing[3])
                .padding(.vertical, theme.spacing[1])
                .background(selected ? fill : .clear, in: Capsule())
                .overlay(Capsule().stroke(theme.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Numbered / lettered badge used in exercise rows, day rows, and the Set
/// Editor. `tinted` fills `accent2` with `onAccent` text (superset / non-working).
struct BuilderBadge: View {
    let text: String
    var tinted: Bool
    @Environment(Theme.self) private var theme
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(tinted ? theme.onAccent : theme.ink)
            .frame(width: 28, height: 28)
            .background(tinted ? theme.accent2 : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.ink, lineWidth: 2))
    }
}

/// Builder screen scaffold: top bar (eyebrow + inert ⋯), scrollable content, and
/// a footer (Cancel secondary + primary save). Footer primary is disabled while
/// saving. Eyebrow uses the shared `StatLabel` so it re-skins with the palette.
struct BuilderScaffold<Content: View>: View {
    let eyebrow: String
    let primaryLabel: String
    let saving: Bool
    let onCancel: () -> Void
    let onPrimary: () -> Void
    @ViewBuilder var content: Content
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                StatLabel(eyebrow)
                    .accessibilityIdentifier("eyebrow-\(eyebrow)")
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundStyle(theme.inkSoft)
                    .accessibilityIdentifier("builder-overflow") // inert per product decision
            }
            .padding(.horizontal, theme.spacing[5])
            .padding(.vertical, theme.spacing[3])

            ScrollView {
                content.padding(.horizontal, theme.spacing[5])
            }

            HStack(spacing: theme.spacing[2]) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
                    .accessibilityIdentifier("builder-cancel")
                Button(action: onPrimary) { Text(primaryLabel) }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
                    .disabled(saving)
                    .accessibilityIdentifier("builder-primary")
            }
            .padding(theme.spacing[5])
        }
        .background(theme.bg.ignoresSafeArea())
    }
}

#Preview {
    BuilderScaffold(eyebrow: "NEW WORKOUT", primaryLabel: "Save workout →",
                    saving: false, onCancel: {}, onPrimary: {}) {
        VStack(alignment: .leading, spacing: 12) {
            PillChip(label: "PUSH", selected: true,
                     fill: Theme().accent2, onFill: Theme().onAccent, action: {})
            BuilderBadge(text: "A", tinted: true)
        }
    }
    .environment(Theme())
}
