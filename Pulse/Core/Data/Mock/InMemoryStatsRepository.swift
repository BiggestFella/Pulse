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
    private enum Bucket { case day, week, month }
    private func bucket(_ range: StatRange) -> Bucket {
        switch range {
        case .d7, .d30: return .day
        case .m3:       return .week
        case .year, .all: return .month
        }
    }
    private func sessionsInRange(_ range: StatRange) -> [WorkoutSession] {
        let now = Date()
        guard let start = windowStart(range, now: now) else { return store.sessions }
        return store.sessions.filter { $0.startedAt > start }
    }
    private func bucketKey(_ date: Date, _ b: Bucket) -> (Date, String) {
        switch b {
        case .day:
            let d = cal.startOfDay(for: date)
            return (d, shortLabel(d, "EEE"))
        case .week:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let d = cal.date(from: comps)!
            return (d, "W\(cal.component(.weekOfYear, from: d))")
        case .month:
            let comps = cal.dateComponents([.year, .month], from: date)
            let d = cal.date(from: comps)!
            return (d, shortLabel(d, "MMM"))
        }
    }
    private func shortLabel(_ date: Date, _ fmt: String) -> String {
        let f = DateFormatter(); f.calendar = cal; f.dateFormat = fmt
        return f.string(from: date)
    }

    func volumeSeries(range: StatRange) async throws -> [VolumePoint] {
        try await store.gate()
        let b = bucket(range)
        var totals: [Date: (label: String, volume: Double)] = [:]
        for session in sessionsInRange(range) {
            let (key, label) = bucketKey(session.startedAt, b)
            totals[key, default: (label, 0)].volume += WorkoutAnalytics.sessionVolume(session)
        }
        return totals.map { VolumePoint(date: $0.key, label: $0.value.label, volume: $0.value.volume) }
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
                               label: shortLabel(session.startedAt, "d/M"), volume: vol)
        }
    }
}
