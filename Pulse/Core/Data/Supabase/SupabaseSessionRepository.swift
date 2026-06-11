import Foundation
import Supabase

/// Logged sessions + their sets. The active flow persists a finished session in
/// one shot via `SupabaseSessionWriter`; these granular methods back History,
/// Exercise Detail, and any incremental logging. RLS scopes rows to the user;
/// inserts stamp `user_id` from the signed-in session.
struct SupabaseSessionRepository: SessionRepository {
    let client: SupabaseClient

    private struct SessionInsertRow: Encodable {
        let id: UUID
        let userId: UUID
        let workoutId: UUID
        let startedAt: Date
    }
    private struct SetInsertRow: Encodable {
        let id: UUID
        let sessionId: UUID
        let exerciseId: UUID
        let variationId: UUID?
        let reps: Int
        let weight: Double
        let type: String
        let order: Int
        let rir: Int?    // Reps In Reserve; nil → SQL NULL (migration 0006)
    }
    private struct EndedUpdate: Encodable { let endedAt: Date }

    // MARK: Writes

    func startSession(workoutID: Workout.ID, at: Date) async throws -> WorkoutSession {
        let userID = try await client.auth.session.user.id
        let session = WorkoutSession(workoutID: workoutID, startedAt: at, endedAt: nil, sets: [])
        try await client.from("sessions").insert(SessionInsertRow(
            id: session.id, userId: userID, workoutId: workoutID, startedAt: at)).execute()
        return session
    }

    func appendSet(_ set: SessionSet, to sessionID: WorkoutSession.ID) async throws {
        try await client.from("session_sets").insert(SetInsertRow(
            id: set.id, sessionId: sessionID, exerciseId: set.exerciseID,
            variationId: set.variationID, reps: set.reps, weight: set.weight,
            type: set.type.rawValue, order: set.order, rir: set.rir)).execute()
    }

    func finishSession(id: WorkoutSession.ID, endedAt: Date) async throws -> WorkoutSession {
        try await client.from("sessions")
            .update(EndedUpdate(endedAt: endedAt)).eq("id", value: id.uuidString).execute()
        guard let session = try await fetchSession(id: id) else { throw RepositoryError.notFound }
        return session
    }

    func deleteSession(id: WorkoutSession.ID) async throws {
        try await client.from("sessions").delete().eq("id", value: id.uuidString).execute()
    }

    // MARK: Reads

    func fetchSessions(limit: Int?) async throws -> [WorkoutSession] {
        let base = client.from("sessions")
            .select("*,session_sets(*)").order("started_at", ascending: false)
        let rows: [SessionReadRow] = try await (limit.map { base.limit($0) } ?? base).execute().value
        return rows.map { $0.toModel() }
    }

    func fetchSession(id: WorkoutSession.ID) async throws -> WorkoutSession? {
        let rows: [SessionReadRow] = try await client
            .from("sessions").select("*,session_sets(*)").eq("id", value: id.uuidString).limit(1)
            .execute().value
        return rows.first?.toModel()
    }

    func lastSessions(forExercise: Exercise.ID, limit: Int) async throws -> [WorkoutSession] {
        // Fetch recent sessions (RLS-scoped) and keep those that include the
        // exercise, preserving full set lists — mirrors the in-memory repo.
        let sessions = try await fetchSessions(limit: nil)
        return sessions
            .filter { $0.sets.contains { $0.exerciseID == forExercise } }
            .prefix(limit)
            .map { $0 }
    }
}
