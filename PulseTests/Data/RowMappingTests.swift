import XCTest
@testable import Pulse

/// Pure mapping tests for the Supabase row DTOs. The network repos can't run in
/// CI, but the row → domain-model decoding is pure and is exercised here against
/// representative embedded-select payloads.
final class RowMappingTests: XCTestCase {

    func testExerciseRowMapsWithVariations() throws {
        let json = #"""
        {"id":"11111111-1111-1111-1111-111111111111","name":"Bench Press",
         "muscle_group":"Chest","default_variation_id":"22222222-2222-2222-2222-222222222222",
         "variations":[{"id":"22222222-2222-2222-2222-222222222222","name":"Barbell","equipment":"Barbell"}]}
        """#.data(using: .utf8)!
        let model = try SupabaseDecoding.decoder.decode(ExerciseRow.self, from: json).toModel()
        XCTAssertEqual(model.name, "Bench Press")
        XCTAssertEqual(model.muscleGroup, "Chest")
        XCTAssertEqual(model.variations.first?.name, "Barbell")
        XCTAssertEqual(model.defaultVariationID?.uuidString, "22222222-2222-2222-2222-222222222222")
    }

    func testProgramRowHydratesAndSortsByOrder() throws {
        // workout_exercises and set_specs deliberately out of order to prove sorting.
        let json = #"""
        {"id":"00000000-0000-0000-0000-0000000000a1","name":"PPL","weeks":8,"is_active":true,
         "workouts":[
           {"id":"00000000-0000-0000-0000-0000000000b2","name":"Pull","weekday":2,"order":1,
            "workout_exercises":[]},
           {"id":"00000000-0000-0000-0000-0000000000b1","name":"Push","weekday":1,"order":0,
            "workout_exercises":[
              {"id":"00000000-0000-0000-0000-0000000000c2","exercise_id":"00000000-0000-0000-0000-0000000000e1",
               "variation_id":null,"superset_group":null,"order":1,
               "exercises":{"id":"00000000-0000-0000-0000-0000000000e1","name":"Dip","muscle_group":"Chest",
                            "default_variation_id":null,"variations":[]},
               "set_specs":[]},
              {"id":"00000000-0000-0000-0000-0000000000c1","exercise_id":"00000000-0000-0000-0000-0000000000e2",
               "variation_id":null,"superset_group":"sg","order":0,
               "exercises":{"id":"00000000-0000-0000-0000-0000000000e2","name":"Bench","muscle_group":"Chest",
                            "default_variation_id":null,"variations":[]},
               "set_specs":[
                 {"id":"00000000-0000-0000-0000-0000000000d2","reps":8,"rir":2,"type":"working","order":1},
                 {"id":"00000000-0000-0000-0000-0000000000d1","reps":5,"rir":3,"type":"warmup","order":0}]}]}]}
        """#.data(using: .utf8)!

        let program = try SupabaseDecoding.decoder.decode(ProgramRow.self, from: json).toModel()

        XCTAssertEqual(program.name, "PPL")
        XCTAssertTrue(program.isActive)
        // Workouts sorted by order: Push (0) before Pull (1).
        XCTAssertEqual(program.workouts.map(\.name), ["Push", "Pull"])

        let push = program.workouts[0]
        // Exercises sorted by order: Bench (0) before Dip (1).
        XCTAssertEqual(push.exercises.map(\.exercise.name), ["Bench", "Dip"])
        XCTAssertEqual(push.exercises[0].supersetGroup, "sg")
        // Set specs sorted by order: warmup (0) before working (1).
        XCTAssertEqual(push.exercises[0].sets.map(\.type), [.warmup, .working])
        XCTAssertEqual(push.exercises[0].sets.map(\.reps), [5, 8])
    }

    func testWorkoutExerciseRowDropsWhenParentMissing() throws {
        // No `exercises` embed → unmappable → compactMap drops it.
        let json = #"""
        {"id":"00000000-0000-0000-0000-0000000000b1","name":"Push","weekday":1,"order":0,
         "workout_exercises":[
           {"id":"00000000-0000-0000-0000-0000000000c1","exercise_id":"00000000-0000-0000-0000-0000000000e2",
            "variation_id":null,"superset_group":null,"order":0,"set_specs":[]}]}
        """#.data(using: .utf8)!
        let workout = try SupabaseDecoding.decoder.decode(WorkoutRow.self, from: json).toModel()
        XCTAssertTrue(workout.exercises.isEmpty)
    }

    func testSessionRowMapsAndSortsSets() throws {
        let json = #"""
        {"id":"00000000-0000-0000-0000-00000000f001","workout_id":"00000000-0000-0000-0000-00000000f0aa",
         "started_at":"2026-06-04T08:00:00+00:00","ended_at":"2026-06-04T09:00:00+00:00",
         "session_sets":[
           {"id":"00000000-0000-0000-0000-00000000f102","exercise_id":"00000000-0000-0000-0000-00000000f0e1",
            "variation_id":null,"reps":8,"weight":100,"type":"working","order":1},
           {"id":"00000000-0000-0000-0000-00000000f101","exercise_id":"00000000-0000-0000-0000-00000000f0e1",
            "variation_id":null,"reps":5,"weight":60,"type":"warmup","order":0}]}
        """#.data(using: .utf8)!
        let session = try SupabaseDecoding.decoder.decode(SessionReadRow.self, from: json).toModel()
        XCTAssertNotNil(session.endedAt)
        XCTAssertEqual(session.sets.map(\.order), [0, 1])
        XCTAssertEqual(session.sets.map(\.weight), [60, 100])
    }

    func testSessionSetRowMapsRIRWhenPresentAndNilWhenAbsent() throws {
        // First set carries `rir`; second omits the key entirely (a legacy row
        // written before migration 0006) → must decode to nil.
        let json = #"""
        {"id":"00000000-0000-0000-0000-00000000f001","workout_id":"00000000-0000-0000-0000-00000000f0aa",
         "started_at":"2026-06-04T08:00:00+00:00","ended_at":"2026-06-04T09:00:00+00:00",
         "session_sets":[
           {"id":"00000000-0000-0000-0000-00000000f101","exercise_id":"00000000-0000-0000-0000-00000000f0e1",
            "variation_id":null,"reps":8,"weight":100,"type":"working","order":0,"rir":2},
           {"id":"00000000-0000-0000-0000-00000000f102","exercise_id":"00000000-0000-0000-0000-00000000f0e1",
            "variation_id":null,"reps":5,"weight":60,"type":"warmup","order":1}]}
        """#.data(using: .utf8)!
        let session = try SupabaseDecoding.decoder.decode(SessionReadRow.self, from: json).toModel()
        XCTAssertEqual(session.sets.map(\.rir), [2, nil])
    }
}
