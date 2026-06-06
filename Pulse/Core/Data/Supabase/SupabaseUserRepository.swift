import Foundation
import Supabase

/// The You-tab profile + headline aggregates. v1 derives the profile from the
/// signed-in auth session (no `profiles` table yet) and the aggregates from the
/// user's logged sessions via `WorkoutAnalytics`.
struct SupabaseUserRepository: UserRepository {
    let client: SupabaseClient

    func currentProfile() async throws -> UserProfile {
        let user = try await client.auth.session.user
        let email = user.email ?? ""
        let displayName = email.split(separator: "@").first.map { String($0).capitalized } ?? "Athlete"
        let program = try? await SupabaseProgramRepository(client: client).activeProgram()
        return UserProfile(displayName: displayName,
                           memberSince: user.createdAt,
                           programLabel: program?.name ?? "—")
    }

    func profileSummary() async throws -> ProfileStats {
        let sessions = try await SupabaseSessionRepository(client: client).fetchSessions(limit: nil)
        let totalVolume = sessions.reduce(0) { $0 + WorkoutAnalytics.sessionVolume($1) }
        let liftsTracked = Set(sessions.flatMap { $0.sets.map(\.exerciseID) }).count
        let sessionsLogged = sessions.filter { $0.endedAt != nil }.count
        let streak = try await SupabaseStatsRepository(client: client).currentStreak()
        return ProfileStats(streakDays: streak,
                            totalSessions: sessions.count,
                            totalVolumeKg: totalVolume,
                            liftsTracked: liftsTracked,
                            sessionsLogged: sessionsLogged)
    }
}
