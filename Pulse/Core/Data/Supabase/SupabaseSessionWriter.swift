import Foundation
import Supabase

/// Persists a finished session to Supabase: one `sessions` row (stamped with the
/// signed-in user) + its `session_sets` (each carrying the variation logged).
/// Uses the shared signed-in client so RLS sees `auth.uid()`.
struct SupabaseSessionWriter: SessionWriter {
    let client: SupabaseClient

    // Encoded with the client's convertToSnakeCase encoder → snake_case columns.
    private struct SessionRow: Encodable {
        let id: UUID
        let userId: UUID
        let workoutId: UUID
        let startedAt: Date
        let endedAt: Date?
    }
    private struct SetRow: Encodable {
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

    func save(_ session: WorkoutSession) async throws {
        let userID = try await client.auth.session.user.id

        try await client.from("sessions").insert(SessionRow(
            id: session.id, userId: userID, workoutId: session.workoutID,
            startedAt: session.startedAt, endedAt: session.endedAt)).execute()

        let rows = session.sets.map { s in
            SetRow(id: s.id, sessionId: session.id, exerciseId: s.exerciseID,
                   variationId: s.variationID, reps: s.reps, weight: s.weight,
                   type: s.type.rawValue, order: s.order, rir: s.rir)
        }
        if !rows.isEmpty {
            try await client.from("session_sets").insert(rows).execute()
        }
    }
}
