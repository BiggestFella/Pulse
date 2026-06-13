import Foundation

/// Lifecycle flag every builder exposes; the screen reads it to surface
/// saving / saved / error and to decide whether to pop.
enum SaveState: Equatable {
    case idle, saving, saved
    case error(String)
}

/// A mutable editing view over `WorkoutExercise`. Consecutive items sharing a
/// non-nil `supersetGroup` render as one superset card.
struct BuilderExercise: Identifiable, Equatable {
    var id = UUID()
    var exercise: Exercise
    var variationID: Variation.ID?
    var supersetGroup: String?
    var sets: [SetSpec]

    /// Working-set reps joined by "-", e.g. "8-10-10".
    var repsSummary: String {
        sets.filter { $0.type == .working }.map { String($0.reps) }.joined(separator: "-")
    }

    /// True when any set is not a working set (drives the " · MIXED" suffix).
    var isMixed: Bool { sets.contains { $0.type != .working } }

    /// `{n} sets · {reps}` (+ " · MIXED").
    var subLine: String {
        let base = "\(sets.count) sets · \(repsSummary)"
        return isMixed ? "\(base) · MIXED" : base
    }
}

/// Exercise-picker catalog section: a muscle group with its full `Exercise`
/// models (the builder needs the whole `Exercise` to seed a `BuilderExercise`,
/// so this is distinct from the Library's display-only `MuscleGroupCatalog`).
struct BuilderCatalogGroup: Identifiable, Equatable {
    var id: String { muscle }
    var muscle: String
    var exercises: [Exercise]
}

/// One exercise chosen in the picker, with the variation selected inline.
struct PickedExercise: Identifiable, Equatable {
    let id: Exercise.ID
    let variationID: Variation.ID?
}

/// One ordered slot in a routine's weekly split. A rest day carries no source.
struct BuilderDay: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sub: String
    var isRest: Bool = false
    var sourceWorkoutID: Workout.ID? = nil
}

/// Seed data so the builders open non-empty exactly as the prototype does. The
/// exercise catalog and the saved-workout list come from the merged data-layer
/// repositories (`ExerciseRepository` / `WorkoutRepository`); only these default
/// drafts are prototype-local.
enum BuilderSampleData {
    private static func exercise(_ name: String, _ muscle: String) -> Exercise {
        Exercise(name: name, muscleGroup: muscle, variations: [], defaultVariationID: nil)
    }

    /// Default Workout Builder items: Flat bench (warmup/working×3/failure) +
    /// Incline (4 working).
    static var defaultWorkoutItems: [BuilderExercise] {
        [
            BuilderExercise(
                exercise: exercise("Flat bench", "Chest"), variationID: nil, supersetGroup: nil,
                sets: [
                    SetSpec(reps: 12, rir: 4, type: .warmup),
                    SetSpec(reps: 8, rir: 2, type: .working),
                    SetSpec(reps: 8, rir: 2, type: .working),
                    SetSpec(reps: 8, rir: 1, type: .working),
                    SetSpec(reps: 6, rir: 0, type: .failure),
                ]),
            BuilderExercise(
                exercise: exercise("Incline press", "Chest"), variationID: nil, supersetGroup: nil,
                sets: [
                    SetSpec(reps: 10, rir: 2, type: .working),
                    SetSpec(reps: 10, rir: 2, type: .working),
                    SetSpec(reps: 10, rir: 2, type: .working),
                    SetSpec(reps: 10, rir: 1, type: .working),
                ]),
        ]
    }

    /// Default Routine: 8 weeks, 5-day split (4 workouts + 1 rest).
    static var defaultRoutineDays: [BuilderDay] {
        [
            BuilderDay(name: "Chest & Tris", sub: "7 exercises"),
            BuilderDay(name: "Back & Bis", sub: "6 exercises"),
            BuilderDay(name: "Legs", sub: "5 exercises"),
            BuilderDay(name: "Rest", sub: "Recovery", isRest: true),
            BuilderDay(name: "Shoulders & Arms", sub: "6 exercises"),
        ]
    }
}
