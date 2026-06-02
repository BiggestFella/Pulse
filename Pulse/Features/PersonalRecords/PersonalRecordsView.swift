import SwiftUI

struct PersonalRecordsView: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var model: PersonalRecordsModel

    init(prRepo: any PRRepository, exerciseRepo: any ExerciseRepository) {
        _model = State(initialValue: PersonalRecordsModel(prRepo: prRepo, exerciseRepo: exerciseRepo))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            topBar
            content
        }
        .padding(.horizontal, theme.spacing[5])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .task { await model.load() }
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left").foregroundStyle(theme.ink)
            }
            .accessibilityIdentifier("pr.back")
            Spacer()
            StatLabel("PERSONAL RECORDS")
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("pr.overflow")
        }
        .padding(.top, theme.spacing[3])
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().tint(theme.accent)
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityIdentifier("pr.loading")
        case .error:
            errorState
        case .empty:
            emptyState
        case .loaded:
            loaded
        }
    }

    private var loaded: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            header
            chipRow
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing[1]) {
                    if let hero = model.hero { heroCard(hero) }
                    if model.filtered.isEmpty { filterEmptyState } else { grid }
                }
                .padding(.top, theme.spacing[1])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PRs.")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("pr.h1")
            Text("\(model.trackedCount) lifts tracked · \(model.freshThisMonthCount) new this month")
                .font(.system(size: 13))
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("pr.subline")
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing[1]) {
                FilterChip(label: "All", isOn: model.selectedMuscle == nil) { model.select(nil) }
                    .accessibilityIdentifier("pr.chip.All")
                ForEach(model.muscleFilters, id: \.self) { muscle in
                    FilterChip(label: muscle, isOn: model.selectedMuscle == muscle) { model.select(muscle) }
                        .accessibilityIdentifier("pr.chip.\(muscle)")
                }
            }
        }
    }

    private func heroCard(_ pr: PersonalRecordsModel.Item) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing[1]) {
            HStack(alignment: .top) {
                if pr.isFresh {
                    Text("NEW · \(relativeDate(pr.achievedAt))".uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, theme.spacing[1])
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.onAccent))
                        .accessibilityIdentifier("pr.hero.newPill")
                }
                Spacer()
                StatLabel(pr.muscleGroup, color: theme.onAccent.opacity(0.85))
            }
            Text(pr.exerciseName)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(theme.onAccent)
                .accessibilityIdentifier("pr.hero.name")
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing[4]) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(numeral(pr.weight))
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(theme.onAccent)
                    Text(unitSuffix)
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(theme.onAccent.opacity(0.85))
                }
                // Per the design, the rep numeral is an intentional accent-2 figure
                // (not "small highlight text") even on the accent card.
                Text("×\(pr.reps)")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(theme.accent2)
            }
        }
        .padding(theme.spacing[5])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: theme.radiusCard).fill(theme.accent))
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: theme.spacing[1]),
                            GridItem(.flexible(), spacing: theme.spacing[1])],
                  spacing: theme.spacing[1]) {
            ForEach(model.gridRecords) { pr in gridCard(pr) }
        }
    }

    private func gridCard(_ pr: PersonalRecordsModel.Item) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                StatLabel(pr.muscleGroup)
                Spacer()
                if pr.isFresh { StatLabel("New", color: theme.accent2) }
            }
            Text(pr.exerciseName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing[2]) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(numeral(pr.weight))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(theme.ink)
                    Text(unitSuffix)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(theme.inkSoft)
                }
                Text("×\(pr.reps)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.accent2)
            }
            StatLabel(relativeDate(pr.achievedAt))
        }
        .padding(.horizontal, theme.spacing[4])
        .padding(.vertical, theme.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: theme.radiusCard)
            .stroke(pr.isFresh ? theme.accent2 : theme.inkFaint, lineWidth: pr.isFresh ? 2 : 1.5))
    }

    private var emptyState: some View {
        VStack(spacing: theme.spacing[2]) {
            Text("No personal records yet")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.ink)
            Text("Log a few working sets and your bests will show up here.")
                .font(.system(size: 13))
                .foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityIdentifier("pr.empty")
    }

    private var filterEmptyState: some View {
        Text("No PRs for \(model.selectedMuscle ?? "") yet")
            .font(.system(size: 13))
            .foregroundStyle(theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, theme.spacing[6])
            .accessibilityIdentifier("pr.filterEmpty")
    }

    private var errorState: some View {
        VStack(spacing: theme.spacing[2]) {
            Text("Couldn't load your records.")
                .font(.system(size: 14))
                .foregroundStyle(theme.ink)
            Button("Retry") { Task { await model.retry() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .accessibilityIdentifier("pr.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityIdentifier("pr.error")
    }

    /// Big numeral without a trailing ".0".
    private func numeral(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(w)
    }
    private var unitSuffix: String { "kg" }   // kg-only v1

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Loaded") {
    NavigationStack {
        PersonalRecordsView(prRepo: InMemoryPRRepository(store: MockStore()),
                            exerciseRepo: InMemoryExerciseRepository(store: MockStore()))
    }
    .environment(Theme())
}

#Preview("Empty") {
    NavigationStack {
        PersonalRecordsView(prRepo: InMemoryPRRepository(store: MockStore(seeded: false)),
                            exerciseRepo: InMemoryExerciseRepository(store: MockStore(seeded: false)))
    }
    .environment(Theme())
}
