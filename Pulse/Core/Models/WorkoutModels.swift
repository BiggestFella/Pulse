import Foundation

enum SetType: String, Codable, CaseIterable {
    case working, warmup, dropset, failure, amrap
}

struct SetSpec: Codable, Equatable, Identifiable {
    var id = UUID()
    var reps: Int
    var rir: Int
    var type: SetType
}

struct Variation: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var equipment: String?
}

struct Exercise: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var muscleGroup: String
    var variations: [Variation]
    var defaultVariationID: Variation.ID?
}

struct WorkoutExercise: Codable, Equatable, Identifiable {
    var id = UUID()
    var exercise: Exercise
    var variationID: Variation.ID?
    var supersetGroup: String?   // shared tag groups superset members
    var sets: [SetSpec]
}

struct Workout: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var weekday: Int?            // 1...7, nil = unscheduled
    var order: Int
    var exercises: [WorkoutExercise]
}

struct Program: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var weeks: Int
    var isActive: Bool = false
    var workouts: [Workout]
}

/// A logged set — actual performance against a Workout. `exerciseID` lets logged
/// sets group per-exercise (Session Detail, History, PR derivation); `order`
/// mirrors the SQL `"order"` column so round-trips preserve sequence.
struct SessionSet: Codable, Equatable, Identifiable {
    var id = UUID()
    var exerciseID: Exercise.ID
    var order: Int
    var reps: Int
    var weight: Double            // kilograms (v1 is kg-only)
    var type: SetType
}

struct WorkoutSession: Codable, Equatable, Identifiable {
    var id = UUID()
    var workoutID: Workout.ID
    var startedAt: Date
    var endedAt: Date?
    var sets: [SessionSet]
}
