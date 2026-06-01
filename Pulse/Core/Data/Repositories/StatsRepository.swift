import Foundation

/// Range-scoped aggregations for the Stats tab and Exercise Detail. All values
/// are computed from logged sessions via `WorkoutAnalytics`.
protocol StatsRepository {
    func volumeSeries(range: StatRange) async throws -> [VolumePoint]
    func summary(range: StatRange) async throws -> StatsSummary
    func volumeByMuscle(range: StatRange) async throws -> [MuscleVolume]
    func currentStreak() async throws -> Int
    func exerciseVolumeHistory(_ exerciseID: Exercise.ID, lastN: Int) async throws -> [VolumePoint]
}
