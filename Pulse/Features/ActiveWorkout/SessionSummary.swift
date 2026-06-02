import Foundation

/// Derived receipt totals for the summary screen. All values come from logged sets.
struct SessionSummary: Equatable {
    var totalVolume: Double   // Σ reps×weight over counting sets (warmup/failure excluded)
    var elapsedMinutes: Int
    var completedSets: Int    // doneSteps.count
    var totalSets: Int        // steps.count
    var prCount: Int          // exercises whose session best est-1RM beats baseline
}
