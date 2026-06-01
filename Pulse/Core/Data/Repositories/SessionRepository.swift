import Foundation

/// Logged workout sessions. Mutating methods return the persisted entity so
/// server-assigned ids/timestamps round-trip.
protocol SessionRepository {
    func startSession(workoutID: Workout.ID, at: Date) async throws -> WorkoutSession
    func appendSet(_ set: SessionSet, to sessionID: WorkoutSession.ID) async throws
    func finishSession(id: WorkoutSession.ID, endedAt: Date) async throws -> WorkoutSession
    func fetchSessions(limit: Int?) async throws -> [WorkoutSession]
    func fetchSession(id: WorkoutSession.ID) async throws -> WorkoutSession?
    func lastSessions(forExercise: Exercise.ID, limit: Int) async throws -> [WorkoutSession]
    func deleteSession(id: WorkoutSession.ID) async throws
}
