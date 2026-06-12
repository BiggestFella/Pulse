import Foundation

/// Composes a `TodaySnapshot` from the shared repositories (BAK-24), so the Today
/// screen reads the same single mock/live world as the rest of the app instead of
/// a parallel `TodayRepository` stopgap. Pure and `now`-parameterised: all
/// date-relative output derives from the injected `now`, which keeps it testable.
@MainActor
struct TodaySnapshotComposer {
    let programs: any ProgramRepository
    let workouts: any WorkoutRepository
    let stats: any StatsRepository
    let schedule: any ScheduleRepository
    let sessions: any SessionRepository
    let user: any UserRepository

    /// The single shared Monday-first calendar, so `schedule.plan(for:)` lookups
    /// land on the same `startOfDay` keys the repositories key their data by
    /// (avoids day-boundary drift between independent calendar copies).
    var calendar: Calendar = SampleData.calendar

    func compose(now: Date) async throws -> TodaySnapshot {
        let profile = try await user.currentProfile()
        // Pass `now` so the streak is computed against the same reference day as
        // the rest of the snapshot (consistent under the pinned mock/test clock).
        let streak = try await stats.currentStreak(asOf: now)

        // Full history (limit: nil): the Yesterday recap's PR count needs every
        // prior best — a true PR can pre-date the last 30 sessions — and the hero's
        // "day N" counter must not silently cap at a fetch limit.
        let history = try await sessions.fetchSessions(limit: nil)
        let completed = history.filter { $0.endedAt != nil }
            .sorted { $0.startedAt > $1.startedAt }

        let allWorkouts = (try? await workouts.fetchWorkouts()) ?? []
        let workoutName = Dictionary(allWorkouts.map { ($0.id, $0.name) },
                                     uniquingKeysWith: { first, _ in first })

        let card = try await composeCard(now: now, profile: profile,
                                         completedCount: completed.count)
        let week = try await composeWeek(now: now, workoutName: workoutName,
                                         sessions: history)
        let yesterday = composeRecap(completed.first, all: history,
                                     workoutName: workoutName)

        return TodaySnapshot(
            dateEyebrow: eyebrow(now),
            greetingName: firstName(profile.displayName),
            streak: streak,
            today: card,
            week: week,
            yesterday: yesterday)
    }

    // MARK: - Hero card

    private func composeCard(now: Date, profile: UserProfile,
                             completedCount: Int) async throws -> TodayWorkoutCard? {
        guard let workout = try await workouts.todaysWorkout(on: now) else { return nil }
        // Week/day are derived from how many sessions are already logged: the next
        // workout is "day N+1", and weeks advance every `workouts-per-week`.
        let perWeek = max(1, (try await programs.activeProgram())?.workouts.count ?? 1)
        let day = completedCount + 1
        let week = (day + perWeek - 1) / perWeek
        return TodayWorkoutCard(
            workoutID: workout.id,
            programLabel: profile.programLabel,
            week: week, day: day,
            name: workout.name,
            exerciseCount: workout.exercises.count,
            // No stored duration on the model yet; a simple per-exercise heuristic.
            estimatedMinutes: max(1, workout.exercises.count) * 9)
    }

    // MARK: - Week strip (always exactly 7 cells, Mon–Sun)

    private func composeWeek(now: Date, workoutName: [UUID: String],
                             sessions: [WorkoutSession]) async throws -> [WeekDayCell] {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)   // 1=Sun…7=Sat
        let offsetFromMonday = (weekday + 5) % 7                  // Mon→0 … Sun→6
        let monday = calendar.date(byAdding: .day, value: -offsetFromMonday, to: today)!
        let letters = ["M", "T", "W", "T", "F", "S", "S"]
        let sessionWorkout = Dictionary(sessions.map { ($0.id, $0.workoutID) },
                                        uniquingKeysWith: { first, _ in first })

        var cells: [WeekDayCell] = []
        for i in 0..<7 {
            let day = calendar.date(byAdding: .day, value: i, to: monday)!
            let state: WeekDayCell.State
            let label: String
            switch try await schedule.plan(for: day) {
            case .done(let sessionID)?:
                state = .done
                label = sessionWorkout[sessionID].flatMap { workoutName[$0] } ?? "Done"
            case .workout(let id)?:
                state = calendar.isDate(day, inSameDayAs: today) ? .today : .plan
                label = workoutName[id] ?? "Workout"
            case .rest?, nil:
                state = .rest
                label = "Rest"
            }
            cells.append(WeekDayCell(index: i, dayLetter: letters[i],
                                     label: label, state: state))
        }
        return cells
    }

    // MARK: - Yesterday recap

    private func composeRecap(_ session: WorkoutSession?, all: [WorkoutSession],
                              workoutName: [UUID: String]) -> SessionRecap? {
        guard let session else { return nil }
        let minutes = session.endedAt.map {
            max(0, Int(($0.timeIntervalSince(session.startedAt) / 60).rounded()))
        } ?? 0
        let compact = VolumeFormatter.compact(WorkoutAnalytics.sessionVolume(session))
        let volumeText = compact.unit.isEmpty ? "\(compact.value) KG"
                                              : "\(compact.value)\(compact.unit) KG"
        let prs = SessionPRs.count(in: session, allSessions: all)
        return SessionRecap(
            sessionID: session.id,
            name: workoutName[session.workoutID] ?? "Workout",
            subline: "\(minutes)M · \(volumeText) · +\(prs) PR")
    }

    // MARK: - Formatting

    /// "WED · MAY 28" — fixed `en_US_POSIX` locale so eyebrows read identically
    /// regardless of device language (they are stylistic tokens, not prose).
    private func eyebrow(_ now: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE · MMM d"
        return f.string(from: now).uppercased()
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}
