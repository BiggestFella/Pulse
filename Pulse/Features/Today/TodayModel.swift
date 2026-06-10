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

    var doneCount: Int { week.filter { $0.state == .done }.count }
    var plannedCount: Int { week.filter { $0.state != .rest }.count }

    /// Streak rendered as "<n>D" — 0D at zero, never hidden (product decision).
    var streakLabel: String { "\(streak)D" }
    /// Header trailing eyebrow, e.g. "3 OF 5 DONE".
    var weekProgressLabel: String { "\(doneCount) OF \(plannedCount) DONE" }

    private let repository: any TodayRepository
    private let onStartWorkout: (UUID) -> Void
    private let onOpenSession: (UUID) -> Void

    /// Most recent in-flight load, so a newer load supersedes an older one.
    private var inFlightLoad: Task<Void, Never>?

    init(repository: any TodayRepository,
         onStartWorkout: @escaping (UUID) -> Void = { _ in },
         onOpenSession: @escaping (UUID) -> Void = { _ in }) {
        self.repository = repository
        self.onStartWorkout = onStartWorkout
        self.onOpenSession = onOpenSession
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
                let s = try await repository.loadToday()
                try Task.checkCancellation()   // superseded? leave state to the newer load
                dateEyebrow = s.dateEyebrow
                greetingName = s.greetingName
                streak = s.streak
                today = s.today
                week = s.week
                yesterday = s.yesterday
                phase = (s.today == nil) ? .empty : .loaded
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
}
