import Foundation
import Observation

/// The four History filter chips. Single-select; `.all` is the default.
enum HistoryFilter: CaseIterable {
    case all, program, oneOff, pr

    var chipLabel: String {
        switch self {
        case .all:     return "All"
        case .program: return "PPL"
        case .oneOff:  return "One-offs"
        case .pr:      return "+ PR"
        }
    }
}

/// Read-only Workout History model. Loads logged sessions, resolves each into a
/// presentation-ready row (name / duration / volume / PR / program flag) from the
/// merged BAK-6 repositories + `WorkoutAnalytics`, holds the selected filter, and
/// derives Monday-start recency groups. kg-only volume copy (product decision).
@MainActor
@Observable
final class WorkoutHistoryModel {
    enum Phase: Equatable { case loading, loaded, empty, error }

    /// One History list row. Presentation-ready: every string is pre-formatted so
    /// the view does zero computation. `date` drives recency bucketing only.
    struct Item: Identifiable, Equatable {
        let id: WorkoutSession.ID
        let dayOfWeek: String      // "WED"
        let date: Date
        let dayNumber: String      // "21"
        let name: String
        let durationLabel: String  // "58m"
        let volumeLabel: String    // "12.4k KG"
        let hasPR: Bool
        let isProgram: Bool        // belongs to the active program
    }

    private(set) var phase: Phase = .loading
    private(set) var sessions: [Item] = []   // all loaded rows, most-recent first
    var selectedFilter: HistoryFilter = .all

    private let sessionRepo: any SessionRepository
    private let workoutRepo: any WorkoutRepository
    private let programRepo: any ProgramRepository
    private let now: Date
    private let calendar: Calendar

    init(sessionRepo: any SessionRepository,
         workoutRepo: any WorkoutRepository,
         programRepo: any ProgramRepository,
         now: Date = Date(),
         calendar: Calendar = .current) {
        self.sessionRepo = sessionRepo
        self.workoutRepo = workoutRepo
        self.programRepo = programRepo
        self.now = now
        self.calendar = calendar
    }

    // MARK: - loading

    func load() async {
        phase = .loading
        do {
            let raw = try await sessionRepo.fetchSessions(limit: 200) // most-recent first
            let workouts = try await workoutRepo.fetchWorkouts()
            let activeProgram = try await programRepo.activeProgram()
            let activeWorkoutIDs = Set(activeProgram?.workouts.map(\.id) ?? [])
            let workoutsByID = Dictionary(workouts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            sessions = raw.map { session in
                Self.item(from: session,
                          workout: workoutsByID[session.workoutID],
                          activeWorkoutIDs: activeWorkoutIDs,
                          allSessions: raw,
                          calendar: calendar)
            }
            phase = sessions.isEmpty ? .empty : .loaded
        } catch {
            sessions = []
            phase = .error
        }
    }

    func select(_ filter: HistoryFilter) { selectedFilter = filter }
    func retry() async { await load() }

    // MARK: - derived

    private var filteredSessions: [Item] {
        switch selectedFilter {
        case .all:     return sessions
        case .program: return sessions.filter(\.isProgram)
        case .oneOff:  return sessions.filter { !$0.isProgram }
        case .pr:      return sessions.filter(\.hasPR)
        }
    }

    var filteredGroups: [HistoryGroup] {
        HistoryGrouping.groups(for: filteredSessions, now: now, calendar: calendar)
    }

    var isEmpty: Bool { filteredSessions.isEmpty }

    /// Total logged session count for the sub-line ("183 sessions · since …").
    var headerCount: Int { sessions.count }

    /// "since <Month Year>" of the oldest loaded session, or empty if none.
    var sinceLabel: String {
        guard let oldest = sessions.map(\.date).min() else { return "" }
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM yyyy"
        return "since \(f.string(from: oldest))"
    }

    // MARK: - row projection

    static func item(from session: WorkoutSession,
                     workout: Workout?,
                     activeWorkoutIDs: Set<Workout.ID>,
                     allSessions: [WorkoutSession],
                     calendar: Calendar) -> Item {
        let dow = HistoryFormat.dayOfWeek(session.startedAt, calendar: calendar)
        let dayNumber = HistoryFormat.dayNumber(session.startedAt, calendar: calendar)
        let duration = HistoryFormat.durationLabel(start: session.startedAt, end: session.endedAt)
        let volume = WorkoutAnalytics.sessionVolume(session)
        let hasPR = SessionPRs.count(in: session, allSessions: allSessions) > 0
        return Item(
            id: session.id,
            dayOfWeek: dow,
            date: session.startedAt,
            dayNumber: dayNumber,
            name: workout?.name ?? "Workout",
            durationLabel: duration,
            volumeLabel: "\(HistoryFormat.abbreviate(volume)) KG",
            hasPR: hasPR,
            isProgram: activeWorkoutIDs.contains(session.workoutID))
    }
}
