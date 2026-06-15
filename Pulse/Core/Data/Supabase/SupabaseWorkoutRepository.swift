import Foundation
import Supabase

/// Workouts (routines). Reads hydrate the full exercise/set graph. A workout must
/// belong to a program (FK), so `saveWorkout` attaches the draft to the user's
/// active program (falling back to their first program), mirroring the mock.
struct SupabaseWorkoutRepository: WorkoutRepository {
    let client: SupabaseClient

    static let graphSelect = "*,workout_exercises(*,exercises(*,variations!variations_exercise_id_fkey(*)),set_specs(*))"

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
            .contains("weekdays", value: [appWeekday]).limit(1)
            .execute().value
        return rows.first?.toModel()
    }

    func saveWorkout(_ workout: Workout) async throws -> Workout {
        guard let programID = try await targetProgramID() else { throw RepositoryError.notFound }
        // Upsert the workout's OWN row in place. A delete+reinsert (the previous
        // approach) reset folder_id (not carried by WorkoutWriteRow) and tripped
        // plan_entries.workout_id's `on delete set null`, silently un-foldering the
        // workout and wiping its specific-date schedule (BAK-60). Upsert touches only
        // name/weekdays/order/targets; folder_id + plan_entries are left intact.
        let row = WorkoutWriteRow(
            id: workout.id, programId: programID, name: workout.name,
            weekdays: workout.weekdays, order: workout.order,
            targets: workout.targets.map(\.rawValue),
            restSeconds: workout.restSeconds, notes: workout.notes)
        try await client.from("workouts").upsert(row).execute()
        // Replace only the children: delete this workout's exercises (cascades
        // set_specs) then re-insert the exercise/set graph.
        try await client.from("workout_exercises")
            .delete().eq("workout_id", value: workout.id.uuidString).execute()
        try await WorkoutGraphWriter(client: client).insertChildren(of: workout)
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
