import Foundation

/// Range-scoped aggregations for the Stats tab and Exercise Detail. All values
/// are computed from logged sessions via `WorkoutAnalytics`.
protocol StatsRepository {
    func volumeSeries(range: StatRange) async throws -> [VolumePoint]
    func summary(range: StatRange) async throws -> StatsSummary
    func volumeByMuscle(range: StatRange) async throws -> [MuscleVolume]
    func currentStreak(asOf now: Date) async throws -> Int
    func exerciseVolumeHistory(_ exerciseID: Exercise.ID, lastN: Int) async throws -> [VolumePoint]
}

extension StatsRepository {
    /// Streak as of the real current date. Screens that don't pin a clock (Stats,
    /// You) use this; the Today composer passes its injected `now` so the streak
    /// stays consistent with the rest of the snapshot it renders (BAK-24).
    func currentStreak() async throws -> Int { try await currentStreak(asOf: Date()) }
}
