import SwiftUI

/// Stub push target for the Yesterday row. Real Session Detail is a separate
/// feature; this satisfies AC #8 (navigation occurs) without owning that screen.
struct SessionDetailStub: View {
    @Environment(Theme.self) private var theme
    let sessionID: UUID
    var body: some View {
        Text("Session Detail")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
            .navigationTitle("Session")
            .accessibilityIdentifier("sessionDetail.stub")
    }
}

struct TodayView: View {
    @Environment(Theme.self) private var theme
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
        _model = State(initialValue: model ?? TodayModel(repository: MockTodayRepository.sample))
        self.pendingStore = pendingStore
        self.onFlushPending = onFlushPending
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(theme.bg.ignoresSafeArea())
                .navigationDestination(for: UUID.self) { SessionDetailStub(sessionID: $0) }
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
            VStack(alignment: .leading, spacing: 18) {
                topBar
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
            .padding(18)
        }
    }

    private var topBar: some View {
        HStack {
            Eyebrow(model.dateEyebrow)
            Spacer()
            Button { /* inert placeholder (product decision) */ } label: {
                Image(systemName: "ellipsis").foregroundStyle(theme.inkSoft)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("today.overflow")
        }
    }

    private var greetingRow: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Hey, \(model.greetingName).")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("today.greeting")
            Spacer()
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(model.streak)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(theme.accent2)
                Text("D")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent2.opacity(0.7))
            }
            .accessibilityIdentifier("today.streak")
        }
    }

    private var errorState: some View {
        VStack(spacing: 14) {
            Text("Couldn't load Today.")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.ink)
            Button("Retry") { Task { await model.load() } }
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 999))
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("today.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)   // expose the retry button's own id
        .accessibilityIdentifier("today.error")
    }
}

#Preview("Loaded") {
    TodayView(model: TodayModel(repository: MockTodayRepository.sample))
        .environment(Theme())
}
#Preview("Rest day") {
    TodayView(model: TodayModel(repository: MockTodayRepository.restDay))
        .environment(Theme())
}
#Preview("Error") {
    TodayView(model: TodayModel(repository: MockTodayRepository.failing))
        .environment(Theme())
}
