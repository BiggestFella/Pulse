import SwiftUI

struct AppShell: View {
    /// The active-workout session engine. When `isActive`, the app takes over
    /// full-screen (tab bar hidden) and runs the flow.
    @State private var session: ActiveWorkoutModel
    /// Today is the default/first tab. Its Start → callback launches the active
    /// flow. Launch arguments select a mock variant for UI tests.
    @State private var todayModel: TodayModel
    /// Held for dev-user sign-in (`bootstrap()`); children resolve it from the environment.
    private let container: RepositoryContainer
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

        let repo: MockTodayRepository
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestRestDay") { repo = .restDay }
        else if args.contains("-uiTestError") { repo = .failing }
        else { repo = .sample }
        _todayModel = State(initialValue: TodayModel(
            repository: repo,
            // Start → launches the active flow with the path-appropriate workout.
            onStartWorkout: { _ in session.startWorkout(startWorkout) },
            onOpenSession: { _ in /* handled by TodayView path push */ }))
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
        .task { await container.bootstrap() }
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
        TabView {
            TodayView(model: todayModel)
                .tabItem { Label("Today", systemImage: "bolt.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
            PlanView(onStartWorkout: { session.startWorkout(startWorkout) })
                .tabItem { Label("Plan", systemImage: "calendar") }
            YouView()
                .tabItem { Label("You", systemImage: "person.fill") }
        }
    }
}

#Preview { AppShell(container: RepositoryContainer(useMock: true)).environment(Theme()) }
