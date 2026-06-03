import SwiftUI

struct WorkoutHistoryView: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var model: WorkoutHistoryModel
    let onSelectSession: (WorkoutSession.ID) -> Void

    init(model: WorkoutHistoryModel,
         onSelectSession: @escaping (WorkoutSession.ID) -> Void) {
        _model = State(initialValue: model)
        self.onSelectSession = onSelectSession
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            topBar
            header
            filterChips
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
            .accessibilityIdentifier("history.back")
            Spacer()
            StatLabel("WORKOUT HISTORY")
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("history.overflow")   // inert per product decision
        }
        .padding(.top, theme.spacing[3])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("History.")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("history.h1")
            Text(subLine)
                .font(.system(size: 13))
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("history.subline")
        }
    }

    private var subLine: String {
        let sessionWord = model.headerCount == 1 ? "session" : "sessions"
        let since = model.sinceLabel
        return since.isEmpty
            ? "\(model.headerCount) \(sessionWord)"
            : "\(model.headerCount) \(sessionWord) · \(since)"
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing[1]) {
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    FilterChip(label: filter.chipLabel,
                               isOn: model.selectedFilter == filter) {
                        model.select(filter)
                    }
                    .accessibilityIdentifier("history.chip.\(filter.chipLabel)")
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().tint(theme.accent)
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityIdentifier("history.loading")
        case .error:
            errorState
        case .empty:
            emptyState
        case .loaded:
            if model.isEmpty { filterEmptyState } else { groupedList }
        }
    }

    private var groupedList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing[2]) {
                ForEach(model.filteredGroups) { group in
                    StatLabel(group.label)
                        .padding(.top, theme.spacing[2])
                    ForEach(group.sessions) { session in
                        Button { onSelectSession(session.id) } label: {
                            SessionRow(session: session)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("history.row.\(session.name)")
                    }
                }
            }
            .padding(.top, theme.spacing[1])
        }
    }

    private var emptyState: some View {
        VStack(spacing: theme.spacing[2]) {
            Text("No sessions yet")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.ink)
            Text("Log a workout and it'll show up here.")
                .font(.system(size: 13))
                .foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityIdentifier("history.empty")
    }

    private var filterEmptyState: some View {
        Text("No sessions match this filter")
            .font(.system(size: 13))
            .foregroundStyle(theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, theme.spacing[6])
            .accessibilityIdentifier("history.empty")
    }

    private var errorState: some View {
        VStack(spacing: theme.spacing[2]) {
            Text("Couldn't load your history.")
                .font(.system(size: 14))
                .foregroundStyle(theme.ink)
            Button("Retry") { Task { await model.retry() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .accessibilityIdentifier("history.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityIdentifier("history.error")
    }
}

/// A single history list row: date block · name/sub · optional PR · chevron.
private struct SessionRow: View {
    @Environment(Theme.self) private var theme
    let session: WorkoutHistoryModel.Item

    var body: some View {
        HStack(spacing: theme.spacing[3]) {
            VStack(alignment: .leading, spacing: 0) {
                StatLabel(session.dayOfWeek)
                Text(session.dayNumber)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.ink)
            }
            .frame(minWidth: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.ink)
                Text("\(session.durationLabel) · \(session.volumeLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.inkSoft)
            }
            Spacer()
            if session.hasPR { PrBadge() }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.inkFaint)
        }
        .padding(.vertical, theme.spacing[2])
        .padding(.horizontal, theme.spacing[3])
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
        .contentShape(Rectangle())
    }
}

/// Small "PR" pill used on history rows and log rows. Accent fill + onAccent text.
struct PrBadge: View {
    @Environment(Theme.self) private var theme
    var body: some View {
        Text("PR")
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, theme.spacing[1])
            .padding(.vertical, 2)
            .background(Capsule().fill(theme.accent))
            .accessibilityIdentifier("history.prBadge")
    }
}

#Preview("Loaded") {
    NavigationStack {
        WorkoutHistoryView(
            model: WorkoutHistoryModel(
                sessionRepo: InMemorySessionRepository(store: MockStore()),
                workoutRepo: InMemoryWorkoutRepository(store: MockStore()),
                programRepo: InMemoryProgramRepository(store: MockStore())),
            onSelectSession: { _ in })
    }
    .environment(Theme())
}

#Preview("Empty") {
    NavigationStack {
        WorkoutHistoryView(
            model: WorkoutHistoryModel(
                sessionRepo: InMemorySessionRepository(store: MockStore(seeded: false)),
                workoutRepo: InMemoryWorkoutRepository(store: MockStore(seeded: false)),
                programRepo: InMemoryProgramRepository(store: MockStore(seeded: false))),
            onSelectSession: { _ in })
    }
    .environment(Theme())
}
