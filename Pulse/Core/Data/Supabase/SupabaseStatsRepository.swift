import Foundation
import Supabase

/// Range-scoped aggregations for the Stats tab, derived client-side from logged
/// sessions via `WorkoutAnalytics`. Mirrors `InMemoryStatsRepository`, fetching
/// the user's sessions / catalog / schedule from Supabase. No stored aggregates.
struct SupabaseStatsRepository: StatsRepository {
    let client: SupabaseClient
    private var cal: Calendar { SampleData.calendar }

    private func windowStart(_ range: StatRange, now: Date) -> Date? {
        switch range {
        case .d7:   return cal.date(byAdding: .day, value: -7, to: now)
        case .d30:  return cal.date(byAdding: .day, value: -30, to: now)
        case .m3:   return cal.date(byAdding: .month, value: -3, to: now)
        case .year: return cal.date(byAdding: .year, value: -1, to: now)
        case .all:  return nil
        }
    }
    private func sessionsInRange(_ sessions: [WorkoutSession], _ range: StatRange) -> [WorkoutSession] {
        guard let start = windowStart(range, now: Date()) else { return sessions }
        return sessions.filter { $0.startedAt > start }
    }

    private func bucketKey(_ date: Date, _ range: StatRange) -> Date {
        switch range {
        case .d7, .d30:
            return cal.startOfDay(for: date)
        case .m3:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return cal.date(from: comps)!
        case .year, .all:
            let comps = cal.dateComponents([.year, .month], from: date)
            return cal.date(from: comps)!
        }
    }

    func volumeSeries(range: StatRange) async throws -> [VolumePoint] {
        let sessions = sessionsInRange(try await allSessions(), range)
        var totals: [Date: Double] = [:]
        for session in sessions {
            totals[bucketKey(session.startedAt, range), default: 0] += WorkoutAnalytics.sessionVolume(session)
        }
        return totals.map { key, volume in
            VolumePoint(date: key,
                        label: WorkoutAnalytics.bucketLabel(for: key, range: range, calendar: cal),
                        volume: volume)
        }
        .sorted { $0.date < $1.date }
    }

    func summary(range: StatRange) async throws -> StatsSummary {
        let sessions = sessionsInRange(try await allSessions(), range)
        let durations = sessions.compactMap { s -> TimeInterval? in
            s.endedAt.map { $0.timeIntervalSince(s.startedAt) }
        }
        let avg = durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
        let newPRs = try await SupabasePRRepository(client: client).newPRs(in: range).count
        let streak = try await currentStreak()
        return StatsSummary(sessions: sessions.count, newPRs: newPRs,
                            averageDuration: avg, streak: streak)
    }

    func volumeByMuscle(range: StatRange) async throws -> [MuscleVolume] {
        let muscleByExercise = Dictionary(uniqueKeysWithValues:
            try await allExercises().map { ($0.id, $0.muscleGroup) })
        let sessions = sessionsInRange(try await allSessions(), range)
        var totals: [String: Double] = [:]
        for session in sessions {
            for set in session.sets {
                guard let muscle = muscleByExercise[set.exerciseID] else { continue }
                totals[muscle, default: 0] += WorkoutAnalytics.setVolume(set)
            }
        }
        return totals.filter { $0.value > 0 }
                     .map { MuscleVolume(muscleGroup: $0.key, volume: $0.value) }
                     .sorted { $0.volume > $1.volume }
    }

    func currentStreak() async throws -> Int {
        let completedDays = Set(try await allSessions()
            .filter { $0.endedAt != nil }
            .map { cal.startOfDay(for: $0.startedAt) })
        let plan = try await SupabaseScheduleRepository(client: client).fullSchedule()
        return WorkoutAnalytics.streak(plan: plan, completedDays: completedDays,
                                       asOf: Date(), calendar: cal)
    }

    func exerciseVolumeHistory(_ exerciseID: Exercise.ID, lastN: Int) async throws -> [VolumePoint] {
        let relevant = try await allSessions()
            .filter { $0.sets.contains { $0.exerciseID == exerciseID } }
            .sorted { $0.startedAt < $1.startedAt }
            .suffix(lastN)
        return relevant.map { session in
            let vol = session.sets.filter { $0.exerciseID == exerciseID }
                                  .reduce(0) { $0 + WorkoutAnalytics.setVolume($1) }
            return VolumePoint(date: session.startedAt,
                               label: dayMonthLabel(session.startedAt), volume: vol)
        }
    }

    private func dayMonthLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d/M"
        return f.string(from: date)
    }

    private func allSessions() async throws -> [WorkoutSession] {
        try await SupabaseSessionRepository(client: client).fetchSessions(limit: nil)
    }
    private func allExercises() async throws -> [Exercise] {
        try await SupabaseExerciseRepository(client: client).fetchCatalog()
    }
}
