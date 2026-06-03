import Foundation

/// Reads the current lifter's profile + headline aggregate stats for the You tab.
/// Owned by the data layer (BAK-6); mock implementation backs the UI-first build.
/// Distinct from `StatsRepository`, which serves range-scoped chart analytics for
/// the Stats tab — this protocol returns the single profile snapshot the You
/// header and NavRow sub-counts render.
protocol UserRepository {
    func currentProfile() async throws -> UserProfile
    func profileSummary() async throws -> ProfileStats
}
