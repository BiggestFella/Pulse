import Foundation
import Supabase

/// Workouts (routines). Reads hydrate the full exercise/set graph. A workout must
/// belong to a program (FK), so `saveWorkout` attaches the draft to the user's
/// active program (falling back to their first program), mirroring the mock.
struct SupabaseWorkoutRepository: WorkoutRepository {
    let client: SupabaseClient

    static let graphSelect = "*,workout_exercises(*,exercises(*,variations(*)),set_specs(*))"

    private struct ProgramIDRow: Decodable { let id: UUID; let isActive: Bool }

    func fetchWorkouts() async throws -> [Workout] {
        let rows: [WorkoutRow] = try await client
            .from("workouts").select(Self.graphSelect).order("order")
            .execute().value
        return rows.map { $0.toModel() }
    }

    func fetchWorkout(id: Workout.ID) async throws -> Workout? {
        let rows: [WorkoutRow] = try await client
            .from("workouts").select(Self.graphSelect).eq("id", value: id.uuidString).limit(1)
            .execute().value
        return rows.first?.toModel()
    }

    func todaysWorkout(on date: Date) async throws -> Workout? {
        let greg = SampleData.calendar.component(.weekday, from: date) // 1=Sun…7=Sat
        let appWeekday = ((greg + 5) % 7) + 1                          // Mon→1 … Sun→7
        let rows: [WorkoutRow] = try await client
            .from("workouts").select(Self.graphSelect)
            .eq("weekday", value: appWeekday).limit(1)
            .execute().value
        return rows.first?.toModel()
    }

    func saveWorkout(_ workout: Workout) async throws -> Workout {
        guard let programID = try await targetProgramID() else { throw RepositoryError.notFound }
        // Replace this workout's graph: delete the row (cascades children) then re-insert.
        try await client.from("workouts").delete().eq("id", value: workout.id.uuidString).execute()
        try await WorkoutGraphWriter(client: client).insert([workout], programID: programID)
        return try await fetchWorkout(id: workout.id) ?? workout
    }

    func deleteWorkout(id: Workout.ID) async throws {
        try await client.from("workouts").delete().eq("id", value: id.uuidString).execute()
    }

    /// The active program's id, or the user's first program — where a standalone
    /// saved workout is parented (the schema requires a program_id).
    private func targetProgramID() async throws -> Program.ID? {
        let rows: [ProgramIDRow] = try await client
            .from("programs").select("id,is_active").order("created_at")
            .execute().value
        return (rows.first { $0.isActive } ?? rows.first)?.id
    }
}
