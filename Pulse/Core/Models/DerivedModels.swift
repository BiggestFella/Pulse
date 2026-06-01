import Foundation

/// One point on a volume chart. `label` is the axis caption ("Mon", "W1", "Jan");
/// `date` is the bucket start for sorting.
struct VolumePoint: Equatable, Identifiable {
    var id = UUID()
    var date: Date
    var label: String
    var volume: Double
}

/// The four hero numbers on the Stats summary card.
struct StatsSummary: Equatable {
    var sessions: Int
    var newPRs: Int
    var averageDuration: TimeInterval
    var streak: Int
}

/// Total working-set volume for one muscle group over a range.
struct MuscleVolume: Equatable, Identifiable {
    var id: String { muscleGroup }
    var muscleGroup: String
    var volume: Double
}

/// A derived personal record (est. 1RM via Epley). Not persisted — computed
/// from logged sets. `isNew` is true when achieved within the queried range.
struct PersonalRecord: Equatable, Identifiable {
    var id = UUID()
    var exerciseID: Exercise.ID
    var variationID: Variation.ID?
    var weight: Double
    var reps: Int
    var estimatedOneRepMax: Double
    var achievedAt: Date
    var isNew: Bool
}

/// The five Stats range chips.
enum StatRange: String, CaseIterable {
    case d7, d30, m3, year, all
}

/// What a calendar day holds on the Plan tab.
enum DayPlan: Equatable {
    case workout(Workout.ID)        // a scheduled training day
    case rest                       // an intentional rest day
    case done(WorkoutSession.ID)    // a day a session was completed
}
