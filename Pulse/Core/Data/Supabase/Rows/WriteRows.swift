import Foundation
import Supabase

/// Encodable rows for the program/workout write graph. Encoded with the client's
/// `convertToSnakeCase` encoder. Optionals are encoded **explicitly** (as `null`,
/// never omitted) so every object in a PostgREST bulk insert carries the same
/// keys — mixed key sets are rejected by the bulk endpoint.
///
/// `order` is synthesized from array position on write (the domain models don't
/// store it); reads sort children back by the `"order"` column.

struct FolderWriteRow: Encodable {
    let id: UUID
    let userId: UUID
    let parentFolderId: UUID?
    let name: String
    let colorToken: String

    enum CodingKeys: String, CodingKey { case id, userId, parentFolderId, name, colorToken }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(parentFolderId, forKey: .parentFolderId)   // null when nil
        try c.encode(name, forKey: .name)
        try c.encode(colorToken, forKey: .colorToken)
    }
}

/// Updates only the `folder_id` of a workout/program row (explicit null on nil).
struct FolderIDUpdate: Encodable {
    let folderId: Folder.ID?
    enum CodingKeys: String, CodingKey { case folderId }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(folderId, forKey: .folderId)   // null when nil
    }
}

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
    let weekdays: [Int]
    let order: Int
    let targets: [String]

    enum CodingKeys: String, CodingKey { case id, programId, name, weekdays, order, targets }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(programId, forKey: .programId)
        try c.encode(name, forKey: .name)
        try c.encode(weekdays, forKey: .weekdays)
        try c.encode(order, forKey: .order)
        try c.encode(targets, forKey: .targets)
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
                            weekdays: $0.weekdays, order: $0.order,
                            targets: $0.targets.map(\.rawValue))
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
