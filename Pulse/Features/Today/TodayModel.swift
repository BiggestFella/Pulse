import Foundation
import Observation

@MainActor
@Observable
final class TodayModel {
    enum Phase: Equatable { case loading, loaded, empty, error }

    private(set) var phase: Phase = .loading

    private(set) var dateEyebrow = ""
    private(set) var greetingName = ""
    private(set) var streak = 0
    private(set) var today: TodayWorkoutCard?
    private(set) var week: [WeekDayCell] = []
    private(set) var yesterday: SessionRecap?

    /// Advisory "consider a deload" banner derived from recent RIR trends (BAK-36).
    /// `nil` = no signal, not enough data, or dismissed for this session. Named
    /// `deloadBanner` (not `deloadSuggestion`) to avoid shadowing the free
    /// `deloadSuggestion(recentSessions:)` heuristic it calls.
    private(set) var deloadBanner: DeloadSuggestion?
    private var deloadDismissed = false

    var doneCount: Int { week.filter { $0.state == .done }.count }
    var plannedCount: Int { week.filter { $0.state != .rest }.count }

    /// Streak rendered as "<n>D" — 0D at zero, never hidden (product decision).
    var streakLabel: String { "\(streak)D" }
    /// Header trailing eyebrow, e.g. "3 OF 5 DONE".
    var weekProgressLabel: String { "\(doneCount) OF \(plannedCount) DONE" }

    /// Builds the snapshot from the shared repositories (BAK-24).
    private let composer: TodaySnapshotComposer
    /// The reference "now" for this load. Captured at construction so the eyebrow,
    /// week strip, and streak are stable for the screen's lifetime (and injectable
    /// in tests). `AppShell` pins it on the mock/UI-test path; live uses `.now`.
    private let now: Date
    /// Recent logged sessions also feed the advisory deload banner (BAK-36).
    private let sessions: any SessionRepository
    private let onStartWorkout: (UUID) -> Void
    private let onOpenSession: (UUID) -> Void
    /// Called with the freshly-loaded snapshot so the app can mirror it to the
    /// widget App Group (BAK-19). A decoupling hook so the model stays
    /// WidgetKit-unaware.
    private let onSnapshot: (TodaySnapshot) -> Void

    /// Most recent in-flight load, so a newer load supersedes an older one.
    private var inFlightLoad: Task<Void, Never>?

    init(programs: any ProgramRepository,
         workouts: any WorkoutRepository,
         stats: any StatsRepository,
         schedule: any ScheduleRepository,
         sessions: any SessionRepository,
         user: any UserRepository,
         now: Date = .now,
         onStartWorkout: @escaping (UUID) -> Void = { _ in },
         onOpenSession: @escaping (UUID) -> Void = { _ in },
         onSnapshot: @escaping (TodaySnapshot) -> Void = { _ in }) {
        self.composer = TodaySnapshotComposer(
            programs: programs, workouts: workouts, stats: stats,
            schedule: schedule, sessions: sessions, user: user)
        self.now = now
        self.sessions = sessions
        self.onStartWorkout = onStartWorkout
        self.onOpenSession = onOpenSession
        self.onSnapshot = onSnapshot
    }

    /// Loads today's snapshot. Guards against overlapping loads (e.g. pull-to-
    /// refresh firing while the initial load is still in flight): a newer load
    /// cancels the older one, and a superseded load discards its result so an
    /// out-of-order completion can't write stale data.
    func load() async {
        inFlightLoad?.cancel()
        let task = Task { @MainActor in
            phase = .loading
            do {
                let s = try await composer.compose(now: now)
                try Task.checkCancellation()   // superseded? leave state to the newer load
                dateEyebrow = s.dateEyebrow
                greetingName = s.greetingName
                streak = s.streak
                today = s.today
                week = s.week
                yesterday = s.yesterday
                phase = (s.today == nil) ? .empty : .loaded
                onSnapshot(s)                  // mirror to the widget App Group (BAK-19)
                await refreshDeloadSignal()    // advisory fatigue banner (BAK-36)
            } catch is CancellationError {
                // A newer load took over; don't clobber its state.
            } catch {
                phase = .error
            }
        }
        inFlightLoad = task
        await task.value
    }

    func startTodaysWorkout() {
        guard let id = today?.workoutID else { return }
        onStartWorkout(id)
    }

    func openYesterday() {
        guard let id = yesterday?.sessionID else { return }
        onOpenSession(id)
    }

    /// Recompute the advisory deload signal from recent logged sessions. No-op
    /// once dismissed this session. Failures to read sessions are swallowed — the
    /// banner is purely advisory.
    func refreshDeloadSignal() async {
        guard !deloadDismissed else { deloadBanner = nil; return }
        let recent = (try? await sessions.fetchSessions(limit: 6)) ?? []
        deloadBanner = deloadSuggestion(recentSessions: recent)
    }

    func dismissDeload() {
        deloadDismissed = true
        deloadBanner = nil
    }

    /// A model wired to the in-memory mock world, for SwiftUI previews and the
    /// `TodayView` default initializer. Production injects repositories from the
    /// `RepositoryContainer` (see `AppShell`).
    static func mock(store: MockStore? = nil, now: Date = .now,
                     onStartWorkout: @escaping (UUID) -> Void = { _ in },
                     onOpenSession: @escaping (UUID) -> Void = { _ in }) -> TodayModel {
        // Construct the store here (not as a default arg): `MockStore` is
        // @MainActor and default-argument expressions evaluate nonisolated.
        let store = store ?? MockStore()
        return TodayModel(programs: InMemoryProgramRepository(store: store),
                   workouts: InMemoryWorkoutRepository(store: store),
                   stats: InMemoryStatsRepository(store: store),
                   schedule: InMemoryScheduleRepository(store: store),
                   sessions: InMemorySessionRepository(store: store),
                   user: InMemoryUserRepository(),
                   now: now,
                   onStartWorkout: onStartWorkout,
                   onOpenSession: onOpenSession)
    }
}
