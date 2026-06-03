import Foundation

/// In-memory mock for `UserRepository` with sample data mirroring the prototype
/// (`Alex Mason · Member since Feb 2024 · PPL`; streak 27, 183 sessions, 2.1M kg,
/// 8 lifts tracked). Offers a controllable failure mode and an empty/new-user
/// variant so the You model's edge cases are testable.
struct InMemoryUserRepository: UserRepository {
    enum Variant { case sample, emptyUser }

    let shouldFail: Bool
    let variant: Variant

    init(shouldFail: Bool = false, variant: Variant = .sample) {
        self.shouldFail = shouldFail
        self.variant = variant
    }

    func currentProfile() async throws -> UserProfile {
        if shouldFail { throw RepositoryError.forced }
        switch variant {
        case .emptyUser:
            return UserProfile(displayName: "", memberSince: Date(), programLabel: "—")
        case .sample:
            var components = DateComponents()
            components.year = 2024; components.month = 2; components.day = 1
            let memberSince = Calendar.current.date(from: components) ?? Date()
            return UserProfile(displayName: "Alex Mason",
                               memberSince: memberSince, programLabel: "PPL")
        }
    }

    func profileSummary() async throws -> ProfileStats {
        if shouldFail { throw RepositoryError.forced }
        switch variant {
        case .emptyUser:
            return .empty
        case .sample:
            return ProfileStats(streakDays: 27, totalSessions: 183,
                                totalVolumeKg: 2_100_000, liftsTracked: 8, sessionsLogged: 183)
        }
    }
}
