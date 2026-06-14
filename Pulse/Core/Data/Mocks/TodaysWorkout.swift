import Foundation

/// Leon's real "Upper" day, pinned to the UUIDs seeded in Supabase
/// (supabase/seed_dev.sql) so the active flow logs against real rows — session
/// FKs (workout_id, exercise_id, variation_id) resolve. Temporary stand-in until
/// the active flow fetches today's workout from the repository (BAK-27 follow-up).
enum TodaysWorkout {
    private static func uid(_ s: String) -> UUID { UUID(uuidString: s)! }

    private static func exercise(_ id: String, _ name: String, _ muscle: String,
                                 varID: String, varName: String, equip: String?) -> Exercise {
        let v = Variation(id: uid(varID), name: varName, equipment: equip)
        return Exercise(id: uid(id), name: name, muscleGroup: muscle,
                        variations: [v], defaultVariationID: v.id)
    }

    /// n working sets with the given rep ladder, rir descending to 0.
    private static func working(_ reps: [Int]) -> [SetSpec] {
        reps.enumerated().map { i, r in
            SetSpec(reps: r, rir: max(0, reps.count - 1 - i), type: .working)
        }
    }
    private static func failure(_ n: Int) -> [SetSpec] {
        (0..<n).map { _ in SetSpec(reps: 0, rir: 0, type: .failure) }
    }

    static let workout: Workout = {
        let incline = exercise("59d41db7-85fc-4749-9347-e14d086f18f5", "Incline Chest Press", "Chest",
                               varID: "ce0e5e04-94d9-4adb-9b42-635faf5a191d", varName: "Machine", equip: "Machine")
        let lat = exercise("ad971ed1-7ebe-40e9-99bb-47d404020037", "Lat Pulldown", "Back",
                           varID: "cbbb3cff-0ade-4c81-b31c-c74f8530aac9", varName: "D-bar", equip: "Cable")
        let shoulder = exercise("ba11b697-5f0a-4c8c-ab39-37669ec0d154", "Shoulder Press", "Shoulders",
                                varID: "c2229eca-465f-426e-91b6-af426eef76ba", varName: "Seated Machine", equip: "Machine")
        let tricep = exercise("30ff4dba-6e0f-4b5d-b9cf-1acd2ed0b755", "Tricep Extension", "Triceps",
                              varID: "89553dae-bcaf-4031-9821-a7e4fd5d1e0e", varName: "Plate Loaded", equip: "Plate Loaded")
        let preacher = exercise("908a7e05-0635-4aaf-8de7-5a9eed2e91f9", "Preacher Curl", "Biceps",
                                varID: "6342839f-3025-405c-977a-da849d1b1083", varName: "Machine", equip: "Machine")
        let pushup = exercise("d23e3b5d-9c0f-460a-8cad-f28271f26280", "Push-Up", "Chest",
                              varID: "d9dae16f-24d2-4c9d-8a92-a710d0a9ae6f", varName: "Deficit", equip: "Bodyweight")

        func we(_ ex: Exercise, _ sets: [SetSpec]) -> WorkoutExercise {
            WorkoutExercise(exercise: ex, variationID: ex.defaultVariationID, supersetGroup: nil, sets: sets)
        }

        return Workout(
            id: uid("512251d0-5c9d-4018-a24e-87e9b639d2be"),
            name: "Upper", order: 0,
            exercises: [
                we(incline, working([12, 10, 8, 6])),
                we(lat, working([12, 10, 8, 6])),
                we(shoulder, working([12, 10, 8])),
                we(tricep, working([12, 10, 8])),
                we(preacher, failure(3)),
                we(pushup, working([12, 12, 12])),
            ])
    }()
}
