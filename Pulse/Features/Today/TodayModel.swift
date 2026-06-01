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

    private var repository: any TodayRepository
    private let onStartWorkout: (UUID) -> Void
    private let onOpenSession: (UUID) -> Void

    init(repository: any TodayRepository,
         onStartWorkout: @escaping (UUID) -> Void = { _ in },
         onOpenSession: @escaping (UUID) -> Void = { _ in }) {
        self.repository = repository
        self.onStartWorkout = onStartWorkout
        self.onOpenSession = onOpenSession
    }

    func load() async {
        phase = .loading
        do {
            let s = try await repository.loadToday()
            dateEyebrow = s.dateEyebrow
            greetingName = s.greetingName
            streak = s.streak
            today = s.today
            week = s.week
            yesterday = s.yesterday
            phase = (s.today == nil) ? .empty : .loaded
        } catch {
            phase = .error
        }
    }

    func startTodaysWorkout() {
        guard let id = today?.workoutID else { return }
        onStartWorkout(id)
    }

    func openYesterday() {
        guard let id = yesterday?.sessionID else { return }
        onOpenSession(id)
    }

    /// Test/recovery seam: swap the repo (e.g. after an error) then `load()` again.
    func replaceRepository(_ repo: any TodayRepository) { repository = repo }
}
