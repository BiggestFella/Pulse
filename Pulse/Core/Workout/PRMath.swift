import Foundation

// Thin convenience wrappers over the canonical `WorkoutAnalytics` so the active
// flow has free-function ergonomics while keeping one source of truth for the math.

/// Epley estimated one-rep max: weight × (1 + reps/30) (one rep returns the bar weight).
func epley1RM(weight: Double, reps: Int) -> Double {
    WorkoutAnalytics.estimatedOneRepMax(weight: weight, reps: reps)
}

/// Best est-1RM among qualifying sets (working/amrap only; warmup & failure
/// excluded). Returns nil when no set qualifies.
func bestEpley(in sets: [SessionSet]) -> Double? {
    WorkoutAnalytics.bestSet(in: sets).map(WorkoutAnalytics.estimatedOneRepMax)
}
