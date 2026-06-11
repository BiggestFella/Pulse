import Foundation

@MainActor
struct InMemorySessionRepository: SessionRepository {
    let store: MockStore

    func startSession(workoutID: Workout.ID, at: Date) async throws -> WorkoutSession {
        try await store.gate()
        let session = WorkoutSession(workoutID: workoutID, startedAt: at, endedAt: nil, sets: [])
        store.sessions.append(session)
        return session
    }
    func appendSet(_ set: SessionSet, to sessionID: WorkoutSession.ID) async throws {
        try await store.gate()
        guard let i = store.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw RepositoryError.notFound
        }
        // The whole SessionSet is stored by value, so `rir` (and any future
        // field) is preserved on read-back — a refactor must keep this verbatim.
        store.sessions[i].sets.append(set)
    }
    func finishSession(id: WorkoutSession.ID, endedAt: Date) async throws -> WorkoutSession {
        try await store.gate()
        guard let i = store.sessions.firstIndex(where: { $0.id == id }) else {
            throw RepositoryError.notFound
        }
        store.sessions[i].endedAt = endedAt
        return store.sessions[i]
    }
    func fetchSessions(limit: Int?) async throws -> [WorkoutSession] {
        try await store.gate()
        let sorted = store.sessions.sorted { $0.startedAt > $1.startedAt }
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }
    func fetchSession(id: WorkoutSession.ID) async throws -> WorkoutSession? {
        try await store.gate(); return store.sessions.first { $0.id == id }
    }
    func lastSessions(forExercise: Exercise.ID, limit: Int) async throws -> [WorkoutSession] {
        try await store.gate()
        return store.sessions
            .filter { $0.sets.contains { $0.exerciseID == forExercise } }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit).map { $0 }
    }
    func deleteSession(id: WorkoutSession.ID) async throws {
        try await store.gate(); store.sessions.removeAll { $0.id == id }
    }
}
