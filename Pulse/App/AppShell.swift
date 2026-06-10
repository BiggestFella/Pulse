import SwiftUI

struct AppShell: View {
    /// Tabs, with a selection binding so widget deep links can switch to Today.
    private enum Tab: Hashable { case today, library, plan, you }
    @State private var selectedTab: Tab = .today
    @Environment(Theme.self) private var theme
    @Environment(\.scenePhase) private var scenePhase
    /// The active-workout session engine. When `isActive`, the app takes over
    /// full-screen (tab bar hidden) and runs the flow.
    @State private var session: ActiveWorkoutModel
    /// Today is the default/first tab. Its Start → callback launches the active
    /// flow. Launch arguments select a mock variant for UI tests.
    @State private var todayModel: TodayModel
    /// Held for dev-user sign-in (`bootstrap()`); children resolve it from the environment.
    private let container: RepositoryContainer
    /// Mirrors the Today snapshot to the widget App Group (BAK-19).
    private let widgetWriter: WidgetSnapshotWriter
    /// The workout the active flow logs against. The mock / UI-test path uses the
    /// superset-shaped sample (acceptance tests assert its structure); the live
    /// path uses the seeded "Upper" day so logged sessions satisfy Supabase FKs.
    /// (Active flow fetching today's workout from the repo is a BAK-27 follow-up.)
    private let startWorkout: Workout

    init(container: RepositoryContainer) {
        self.container = container
        let startWorkout = RepositoryContainer.useMock() ? ActiveWorkoutSample.workout
                                                         : TodaysWorkout.workout
        self.startWorkout = startWorkout
        let session = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MockHistoryRepository(),
            sessionWriter: container.sessionWriter)
        _session = State(initialValue: session)

        let writer = WidgetSnapshotWriter()
        self.widgetWriter = writer

        let repo: MockTodayRepository
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestRestDay") { repo = .restDay }
        else if args.contains("-uiTestError") { repo = .failing }
        else { repo = .sample }
        // Widget mirroring is inert under the UI-test mock path: it would spawn the
        // widget extension (WidgetCenter reload) on every launch, adding
        // nondeterministic cross-process load to the UI suite (BAK-19).
        let widgetsEnabled = !RepositoryContainer.useMock()
        _todayModel = State(initialValue: TodayModel(
            repository: repo,
            // Start → launches the active flow with the path-appropriate workout.
            onStartWorkout: { _ in session.startWorkout(startWorkout) },
            onOpenSession: { _ in /* handled by TodayView path push */ },
            // Mirror each fresh Today load into the widget snapshot, in the
            // user's persisted palette (BAK-19).
            onSnapshot: widgetsEnabled ? { snapshot in
                let palette = UserDefaults.standard.string(forKey: Theme.paletteDefaultsKey)
                    .flatMap(Palette.init(rawValue:)) ?? .default
                writer.update(from: snapshot, palette: palette)
            } : { _ in }))
    }

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-LA_DEBUG_REST") {
                LiveActivityDebugScreen(state: LiveActivityDebugScreen.restFixture)
            } else if ProcessInfo.processInfo.arguments.contains("-LA_DEBUG_FAILURE") {
                LiveActivityDebugScreen(state: LiveActivityDebugScreen.failureFixture)
            } else if ProcessInfo.processInfo.arguments.contains("-uiTestGallery") {
                DesignSystemGallery()
            } else {
                shell
            }
            #else
            shell
            #endif
        }
        .task {
            await container.bootstrap()
            await container.flushPending()   // BAK-32: drain any buffered session at launch
        }
        .onChange(of: scenePhase) { _, phase in
            // Returning to the foreground is a good moment to retry a pending sync.
            if phase == .active { Task { await container.flushPending() } }
        }
        // Re-skin the widget when the user switches palette (BAK-19) — inert under
        // the UI-test mock path (see init).
        .onChange(of: theme.palette) { _, new in
            if !RepositoryContainer.useMock() { widgetWriter.repaint(palette: new) }
        }
        // Resolve widget deep links (BAK-19).
        .onOpenURL { url in
            switch WidgetDeepLink(url) {
            case .startToday:
                selectedTab = .today
                session.startWorkout(startWorkout)
            case .today:
                selectedTab = .today
            case nil:
                break
            }
        }
    }

    /// Session takeover replaces the whole shell (no tab bar) while active.
    @ViewBuilder private var shell: some View {
        if session.isActive {
            ActiveWorkoutFlowView(model: session)
                .accessibilityIdentifier("activeFlow.root")
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            TodayView(model: todayModel,
                      pendingStore: container.pendingStore,
                      onFlushPending: { await container.flushPending() })
                .tabItem { Label("Today", systemImage: "bolt.fill") }
                .tag(Tab.today)
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
                .tag(Tab.library)
            PlanView(onStartWorkout: { session.startWorkout(startWorkout) })
                .tabItem { Label("Plan", systemImage: "calendar") }
                .tag(Tab.plan)
            YouView()
                .tabItem { Label("You", systemImage: "person.fill") }
                .tag(Tab.you)
        }
    }
}

#Preview { AppShell(container: RepositoryContainer(useMock: true)).environment(Theme()) }
