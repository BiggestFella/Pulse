import Foundation
import Supabase

/// Encodable rows for the program/workout write graph. Encoded with the client's
/// `convertToSnakeCase` encoder. Optionals are encoded **explicitly** (as `null`,
/// never omitted) so every object in a PostgREST bulk insert carries the same
/// keys — mixed key sets are rejected by the bulk endpoint.
///
/// `order` is synthesized from array position on write (the domain models don't
/// store it); reads sort children back by the `"order"` column.

struct ProgramWriteRow: Encodable {
    let id: UUID
    let userId: UUID
    let name: String
    let weeks: Int
    let isActive: Bool
}

struct WorkoutWriteRow: Encodable {
    let id: UUID
    let programId: UUID
    let name: String
    let weekday: Int?
    let order: Int

    enum CodingKeys: String, CodingKey { case id, programId, name, weekday, order }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(programId, forKey: .programId)
        try c.encode(name, forKey: .name)
        try c.encode(weekday, forKey: .weekday)   // null when nil
        try c.encode(order, forKey: .order)
    }
}

struct WorkoutExerciseWriteRow: Encodable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    let variationId: UUID?
    let supersetGroup: String?
    let order: Int

    enum CodingKeys: String, CodingKey {
        case id, workoutId, exerciseId, variationId, supersetGroup, order
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workoutId, forKey: .workoutId)
        try c.encode(exerciseId, forKey: .exerciseId)
        try c.encode(variationId, forKey: .variationId)       // null when nil
        try c.encode(supersetGroup, forKey: .supersetGroup)   // null when nil
        try c.encode(order, forKey: .order)
    }
}

struct SetSpecWriteRow: Encodable {
    let id: UUID
    let workoutExerciseId: UUID
    let reps: Int
    let rir: Int
    let type: String
    let order: Int
}

/// Inserts a list of workouts and their nested exercises/sets under a program, in
/// FK dependency order (workouts → workout_exercises → set_specs). Shared by the
/// program and workout repositories so the graph write lives in one place.
struct WorkoutGraphWriter {
    let client: SupabaseClient

    func insert(_ workouts: [Workout], programID: Program.ID) async throws {
        guard !workouts.isEmpty else { return }

        let workoutRows = workouts.map {
            WorkoutWriteRow(id: $0.id, programId: programID, name: $0.name,
                            weekday: $0.weekday, order: $0.order)
        }
        try await client.from("workouts").insert(workoutRows).execute()

        var exerciseRows: [WorkoutExerciseWriteRow] = []
        var setRows: [SetSpecWriteRow] = []
        for workout in workouts {
            for (exIndex, we) in workout.exercises.enumerated() {
                exerciseRows.append(WorkoutExerciseWriteRow(
                    id: we.id, workoutId: workout.id, exerciseId: we.exercise.id,
                    variationId: we.variationID, supersetGroup: we.supersetGroup, order: exIndex))
                for (setIndex, spec) in we.sets.enumerated() {
                    setRows.append(SetSpecWriteRow(
                        id: spec.id, workoutExerciseId: we.id, reps: spec.reps,
                        rir: spec.rir, type: spec.type.rawValue, order: setIndex))
                }
            }
        }
        if !exerciseRows.isEmpty {
            try await client.from("workout_exercises").insert(exerciseRows).execute()
        }
        if !setRows.isEmpty {
            try await client.from("set_specs").insert(setRows).execute()
        }
    }
}
