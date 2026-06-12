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
        // TODO(BAK-35): pass the persisted autoProgressWeight once async settings
        // load is wired into the shell; `SettingsRepository.load()` is async and the
        // session is built synchronously here, so seed from the default for now.
        let session = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MockHistoryRepository(),
            sessionWriter: container.sessionWriter,
            restCue: RestCueService(),
            autoProgress: UserSettings.default.autoProgressWeight)
        _session = State(initialValue: session)

        let writer = WidgetSnapshotWriter()
        self.widgetWriter = writer

        // Today now composes from the shared `RepositoryContainer` (BAK-24). The
        // live path uses the real `now`; the mock/UI-test path pins `now` to a
        // deterministic weekday so the suite isn't at the mercy of the calendar day
        // it runs on: a training day (Mon/Wed/Fri) shows the hero, and
        // `-uiTestRestDay` snaps to a rest weekday so today's card is nil. The
        // `-uiTestError` variant is expressed through the container's forced-error
        // mock store (see `RepositoryContainer`).
        let args = ProcessInfo.processInfo.arguments
        let todayNow: Date
        if RepositoryContainer.useMock() {
            todayNow = args.contains("-uiTestRestDay")
                ? Self.nearestRestWeekday(from: Date())
                : Self.nearestTrainingWeekday(from: Date())
        } else {
            todayNow = Date()
        }
        // Widget mirroring is inert under the UI-test mock path: it would spawn the
        // widget extension (WidgetCenter reload) on every launch, adding
        // nondeterministic cross-process load to the UI suite (BAK-19).
        let widgetsEnabled = !RepositoryContainer.useMock()
        _todayModel = State(initialValue: TodayModel(
            programs: container.programs,
            workouts: container.workouts,
            stats: container.stats,
            schedule: container.schedule,
            sessions: container.sessions,
            user: container.user,
            now: todayNow,
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
            LibraryView(onStartWorkout: { session.startWorkout($0) })
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

    // MARK: - Deterministic `now` for the mock/UI-test path (BAK-24)

    /// The shared Monday-first calendar (the mock world's day boundaries), so the
    /// pinned `now` snaps on the same weekday keys the repositories use.
    private static let mockCalendar = SampleData.calendar

    /// Soonest training weekday (Gregorian Mon/Wed/Fri) on or after `date`, so the
    /// mocked Today shows a startable hero. Searching forward keeps `now` on a day
    /// with no logged session (today/future), so the schedule reads `.workout` —
    /// never `.done`, which the hero now suppresses — and the card actually renders.
    static func nearestTrainingWeekday(from date: Date) -> Date {
        snap(from: date, weekdays: [2, 4, 6], step: 1)
    }

    /// Soonest rest weekday (Gregorian Tue/Thu/Sat/Sun) on or after `date`, so
    /// today's card composes to nil and the rest-day hero renders.
    static func nearestRestWeekday(from date: Date) -> Date {
        snap(from: date, weekdays: [1, 3, 5, 7], step: 1)
    }

    private static func snap(from date: Date, weekdays: Set<Int>, step: Int) -> Date {
        var day = mockCalendar.startOfDay(for: date)
        for _ in 0..<7 {
            if weekdays.contains(mockCalendar.component(.weekday, from: day)) { return day }
            day = mockCalendar.date(byAdding: .day, value: step, to: day)!
        }
        return mockCalendar.startOfDay(for: date)
    }
}

#Preview { AppShell(container: RepositoryContainer(useMock: true)).environment(Theme()) }
