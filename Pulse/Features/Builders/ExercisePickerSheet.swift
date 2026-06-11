import SwiftUI

/// Multi-select catalog grouped by muscle. Holds its own transient selection;
/// on confirm it calls back with the picked ids (the model dedupes). Already
/// added exercises are dimmed and non-selectable. Search field is decorative
/// (inert per product decision); the muscle filter chips are functional.
struct ExercisePickerSheet: View {
    let catalog: [BuilderCatalogGroup]
    let loading: Bool
    let errorText: String?
    let alreadyAdded: Set<Exercise.ID>
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onConfirm: ([Exercise.ID]) -> Void

    @State private var selected: [Exercise.ID] = []   // ordered by tap, preserved on confirm
    @State private var filter: String = "All"
    @Environment(Theme.self) private var theme

    private var muscles: [String] { ["All"] + catalog.map { $0.muscle } }
    private var visibleGroups: [BuilderCatalogGroup] {
        filter == "All" ? catalog : catalog.filter { $0.muscle == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet,
                                   topTrailingRadius: theme.radiusSheet)
                .stroke(theme.ink, lineWidth: 2)
                .ignoresSafeArea(edges: .bottom)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet,
                                          topTrailingRadius: theme.radiusSheet))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Capsule().fill(theme.inkFaint).frame(width: 42, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 12)
            StatLabel("ADD EXERCISE").accessibilityIdentifier("eyebrow-ADD EXERCISE")
            Text("Pick exercises.").pulseStyle(.h1).foregroundStyle(theme.ink)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.inkFaint)
                Text("Search").foregroundStyle(theme.inkFaint)
                Spacer()
            }
            .padding(theme.spacing[3])
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.inkFaint, lineWidth: 2))
            .accessibilityIdentifier("exercise-search")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing[1]) {
                    ForEach(muscles, id: \.self) { m in
                        PillChip(label: m, selected: filter == m,
                                 fill: theme.accent, onFill: theme.onAccent) { filter = m }
                            .accessibilityIdentifier("picker-filter-\(m)")
                    }
                }
            }
        }
        .padding(.horizontal, theme.spacing[5])
        .padding(.bottom, theme.spacing[3])
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("picker-loading")
        } else if let errorText {
            VStack(spacing: theme.spacing[3]) {
                Text(errorText).foregroundStyle(theme.inkSoft)
                Button("Retry", action: onRetry).accessibilityIdentifier("picker-retry")
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing[3]) {
                    ForEach(visibleGroups) { group in
                        StatLabel(group.muscle)
                        ForEach(group.exercises) { ex in row(ex) }
                    }
                }
                .padding(.horizontal, theme.spacing[5])
                .padding(.bottom, theme.spacing[3])
            }
            .scrollIndicators(.hidden)
        }
    }

    private var footer: some View {
        HStack(spacing: theme.spacing[2]) {
            Button("Cancel", action: onCancel)
                .buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
                .accessibilityIdentifier("picker-cancel")
            Button { onConfirm(selected) } label: {
                Text(selected.isEmpty ? "Select exercises" : "Add \(selected.count) selected")
            }
            .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
            .disabled(selected.isEmpty)
            .accessibilityIdentifier("picker-confirm")
        }
        .padding(theme.spacing[5])
    }

    @ViewBuilder private func row(_ ex: Exercise) -> some View {
        let added = alreadyAdded.contains(ex.id)
        let isSel = selected.contains(ex.id)
        let equipment = ex.variations.first?.equipment ?? ""
        Button {
            guard !added else { return }
            if let i = selected.firstIndex(of: ex.id) { selected.remove(at: i) }
            else { selected.append(ex.id) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ex.name).foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                    if !equipment.isEmpty {
                        Text(equipment).foregroundStyle(theme.inkSoft).font(.system(size: 13))
                    }
                }
                Spacer()
                Image(systemName: (added || isSel) ? "checkmark" : "plus")
                    .foregroundStyle(added ? theme.inkSoft : theme.accent)
            }
            .padding(theme.spacing[3])
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isSel ? theme.accent : theme.inkFaint, lineWidth: isSel ? 2 : 1))
            // Make the whole row tappable. Without this the `.plain` button only
            // hit-tests its text/icon, so a tap landing on the Spacer gap (e.g.
            // an automation tap at the row's center) never toggles selection (BAK-26).
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(added)
        .opacity(added ? 0.4 : 1)
        .accessibilityIdentifier("picker-row-\(ex.name)")
    }
}

#Preview {
    let theme = Theme()
    let groups = WorkoutBuilderModel.group(SampleData.exercises)
    return ExercisePickerSheet(catalog: groups, loading: false, errorText: nil,
                               alreadyAdded: [], onRetry: {}, onCancel: {}, onConfirm: { _ in })
        .environment(theme)
}
