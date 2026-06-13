import SwiftUI

struct TodayView: View {
    @Environment(Theme.self) private var theme
    @Environment(RepositoryContainer.self) private var repos
    @State private var model: TodayModel
    @State private var path: [UUID] = []
    /// Offline buffer of unsynced sessions + a flush trigger (BAK-32). `AppShell`
    /// injects these from the `RepositoryContainer`; previews/tests omit them.
    private let pendingStore: PendingSessionStore?
    private let onFlushPending: (() async -> Void)?

    /// Default initializer wires the sample mock; `AppShell` injects the real
    /// repo/callbacks (Task 8). Tests/previews inject their own model.
    init(model: TodayModel? = nil,
         pendingStore: PendingSessionStore? = nil,
         onFlushPending: (() async -> Void)? = nil) {
        _model = State(initialValue: model ?? TodayModel.mock())
        self.pendingStore = pendingStore
        self.onFlushPending = onFlushPending
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(theme.bg.ignoresSafeArea())
                .navigationDestination(for: UUID.self) { id in
                    SessionDetailView(model: SessionDetailModel(
                        sessionID: id,
                        sessionRepo: repos.sessions,
                        workoutRepo: repos.workouts,
                        programRepo: repos.programs,
                        exerciseRepo: repos.exercises))
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            loaded(skeleton: true).redacted(reason: .placeholder)
                .accessibilityIdentifier("today.loading")
        case .loaded, .empty:
            loaded(skeleton: false)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .error:
            errorState
        }
    }

    private func loaded(skeleton: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing[5]) {
                topBar
                if !skeleton, let suggestion = model.deloadBanner {
                    DeloadBanner(suggestion: suggestion) { model.dismissDeload() }
                }
                greetingRow
                if let store = pendingStore, store.pendingCount > 0 {
                    PendingSyncBanner(count: store.pendingCount) {
                        await onFlushPending?()
                    }
                }
                TodayHeroCard(card: model.today) { model.startTodaysWorkout() }
                TodayWeekStrip(week: model.week, progressLabel: model.weekProgressLabel)
                if let recap = model.yesterday {
                    Eyebrow("YESTERDAY")
                    YesterdayRow(recap: recap) {
                        model.openYesterday()
                        path.append(recap.sessionID)
                    }
                }
            }
            .padding(theme.spacing[5])
        }
    }

    private var topBar: some View {
        HStack {
            Eyebrow(model.dateEyebrow)
            Spacer()
            Button { /* inert placeholder (product decision) */ } label: {
                Image(systemName: "ellipsis").foregroundStyle(theme.inkSoft)
            }
            .buttonStyle(IconButtonStyle())
            .accessibilityIdentifier("today.overflow")
        }
    }

    private var greetingRow: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Hey, \(model.greetingName).")
                .pulseStyle(.h1)
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("today.greeting")
            Spacer()
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(model.streak)")
                    .pulseStyle(.statNumeral)
                    .foregroundStyle(theme.accent2)
                Text("D")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent2.opacity(0.7))
            }
            .accessibilityIdentifier("today.streak")
        }
    }

    private var errorState: some View {
        VStack(spacing: theme.spacing[4]) {
            Text("Couldn't load Today.")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.ink)
            Button("Retry") { Task { await model.load() } }
                .buttonStyle(PressableButtonStyle(variant: .primary, size: .sm))
                .accessibilityIdentifier("today.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)   // expose the retry button's own id
        .accessibilityIdentifier("today.error")
    }
}

#Preview("Loaded") {
    TodayView(model: TodayModel.mock())
        .environment(Theme())
        .environment(RepositoryContainer(useMock: true))
}
#Preview("Rest day") {
    // A store with no workouts → today's card is nil → the rest-day hero renders.
    TodayView(model: TodayModel.mock(store: MockStore(seeded: false)))
        .environment(Theme())
        .environment(RepositoryContainer(useMock: true))
}
#Preview("Error") {
    let store = MockStore(); store.forceError = true
    return TodayView(model: TodayModel.mock(store: store))
        .environment(Theme())
        .environment(RepositoryContainer(useMock: true))
}
