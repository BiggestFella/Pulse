import Foundation

@MainActor
struct InMemoryStatsRepository: StatsRepository {
    let store: MockStore
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
    private func sessionsInRange(_ range: StatRange) -> [WorkoutSession] {
        let now = Date()
        guard let start = windowStart(range, now: now) else { return store.sessions }
        return store.sessions.filter { $0.startedAt > start }
    }

    /// The bucket-start date for a session in this range (day / ISO-week / month
    /// start). The axis *label* is derived from this key via
    /// `WorkoutAnalytics.bucketLabel`, so fixed-locale formatting lives in one place.
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
        try await store.gate()
        // Anchor 3M week labels to the window start so they read "W1, W2, …".
        let rangeStart = windowStart(range, now: Date())
        var totals: [Date: Double] = [:]
        for session in sessionsInRange(range) {
            totals[bucketKey(session.startedAt, range), default: 0] += WorkoutAnalytics.sessionVolume(session)
        }
        return totals.map { key, volume in
            VolumePoint(date: key,
                        label: WorkoutAnalytics.bucketLabel(for: key, range: range,
                                                            rangeStart: rangeStart, calendar: cal),
                        volume: volume)
        }
        .sorted { $0.date < $1.date }
    }

    func summary(range: StatRange) async throws -> StatsSummary {
        try await store.gate()
        let sessions = sessionsInRange(range)
        let durations = sessions.compactMap { s -> TimeInterval? in
            s.endedAt.map { $0.timeIntervalSince(s.startedAt) }
        }
        let avg = durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
        let prRepo = InMemoryPRRepository(store: store)
        let newPRs = try await prRepo.newPRs(in: range).count
        let streak = try await currentStreak()
        return StatsSummary(sessions: sessions.count, newPRs: newPRs,
                            averageDuration: avg, streak: streak)
    }

    func volumeByMuscle(range: StatRange) async throws -> [MuscleVolume] {
        try await store.gate()
        let muscleByExercise = Dictionary(uniqueKeysWithValues:
            store.exercises.map { ($0.id, $0.muscleGroup) })
        var totals: [String: Double] = [:]
        for session in sessionsInRange(range) {
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
        try await store.gate()
        let completedDays = Set(store.sessions
            .filter { $0.endedAt != nil }
            .map { cal.startOfDay(for: $0.startedAt) })
        return WorkoutAnalytics.streak(plan: store.schedule,
                                       completedDays: completedDays,
                                       asOf: Date(), calendar: cal)
    }

    func exerciseVolumeHistory(_ exerciseID: Exercise.ID, lastN: Int) async throws -> [VolumePoint] {
        try await store.gate()
        let relevant = store.sessions
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

    /// "d/M" caption for the per-session exercise-history chart. Fixed locale so
    /// it reads identically regardless of device language.
    private func dayMonthLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = cal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d/M"
        return f.string(from: date)
    }
}
