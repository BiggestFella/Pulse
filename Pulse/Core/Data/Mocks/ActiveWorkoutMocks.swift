import Foundation

/// Deterministic sample workout for the active flow: straight exercises, one
/// superset pair, and a bodyweight-to-failure finisher — enough to drive every
/// screen state (warmup / working / dropset / amrap / failure). Named distinctly
/// from BAK-6's `SampleData` (the data-layer catalog world).
enum ActiveWorkoutSample {
    static let bench = Exercise(name: "Flat Machine Press", muscleGroup: "Chest",
                                variations: [Variation(name: "Wide", equipment: nil)])
    static let incline = Exercise(name: "Incline DB Press", muscleGroup: "Chest", variations: [])
    static let triCable = Exercise(name: "Tricep Cable Ext.", muscleGroup: "Triceps",
                                   variations: [Variation(name: "Rope", equipment: nil)])
    static let latRaise = Exercise(name: "Single Arm Lateral Raise", muscleGroup: "Delts",
                                   variations: [Variation(name: "Cable", equipment: nil)])
    static let pushup = Exercise(name: "Tricep Pushup", muscleGroup: "Triceps", variations: [])

    /// Planned weight per (exIdx, setIdx). Stepper seeds read from here (kg).
    static func plannedWeight(exIdx: Int, setIdx: Int) -> Double {
        switch exIdx {
        case 0: return 60      // bench
        case 1: return 28      // incline
        case 2: return 25      // tri cable
        case 3: return 12      // lat raise
        default: return 0      // pushup (failure / bodyweight)
        }
    }

    static let workout = Workout(
        name: "Chest & Tris", weekday: 1, order: 0,
        exercises: [
            WorkoutExercise(exercise: bench, variationID: bench.variations.first?.id,
                            supersetGroup: nil,
                            sets: [SetSpec(reps: 15, rir: 3, type: .warmup),
                                   SetSpec(reps: 12, rir: 2, type: .working),
                                   SetSpec(reps: 10, rir: 1, type: .working),
                                   SetSpec(reps: 8,  rir: 0, type: .working)]),
            WorkoutExercise(exercise: incline, variationID: nil, supersetGroup: nil,
                            sets: [SetSpec(reps: 12, rir: 2, type: .working),
                                   SetSpec(reps: 10, rir: 1, type: .dropset)]),
            WorkoutExercise(exercise: triCable, variationID: triCable.variations.first?.id,
                            supersetGroup: "ss1",
                            sets: [SetSpec(reps: 12, rir: 2, type: .working),
                                   SetSpec(reps: 12, rir: 1, type: .working)]),
            WorkoutExercise(exercise: latRaise, variationID: latRaise.variations.first?.id,
                            supersetGroup: "ss1",
                            sets: [SetSpec(reps: 15, rir: 2, type: .working),
                                   SetSpec(reps: 15, rir: 1, type: .amrap)]),
            WorkoutExercise(exercise: pushup, variationID: nil, supersetGroup: nil,
                            sets: [SetSpec(reps: 0, rir: 0, type: .failure)]),
        ])
}

struct MockSwapAlternativesRepository: SwapAlternativesProviding {
    func alternatives(muscleGroup: String) async throws -> [Exercise] {
        switch muscleGroup {
        case "Chest":
            return [Exercise(name: "Barbell Bench", muscleGroup: "Chest", variations: []),
                    Exercise(name: "Cable Fly", muscleGroup: "Chest", variations: []),
                    Exercise(name: "Pec Deck", muscleGroup: "Chest", variations: [])]
        case "Triceps":
            return [Exercise(name: "Skullcrusher", muscleGroup: "Triceps", variations: []),
                    Exercise(name: "Overhead Ext.", muscleGroup: "Triceps", variations: [])]
        default:
            return [Exercise(name: "Alt \(muscleGroup)", muscleGroup: muscleGroup, variations: [])]
        }
    }
}

struct MockHistoryRepository: HistoryRepository {
    func recentSets(exerciseID: Exercise.ID) async throws -> [SessionSet] {
        [SessionSet(exerciseID: exerciseID, order: 0, reps: 10, weight: 55, type: .working),
         SessionSet(exerciseID: exerciseID, order: 1, reps: 8,  weight: 60, type: .working),
         SessionSet(exerciseID: exerciseID, order: 2, reps: 6,  weight: 62.5, type: .working)]
    }
}

final class MockSessionWriter: SessionWriter {
    private(set) var saved: [WorkoutSession] = []
    func save(_ session: WorkoutSession) async throws { saved.append(session) }
}
