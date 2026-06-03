import ActivityKit
import Foundation

/// Shared between the app (which publishes state) and the PulseWidgets extension
/// (which renders it). The Live Activity is a projection of the session engine.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case active, rest }

        var phase: Phase
        var exerciseName: String        // resolves session swaps
        var setIndex: Int               // 1-based
        var totalSets: Int
        var setTypeLabel: String        // defined for all 5 types incl dropset
        var isFilledChip: Bool          // working → filled accent chip; others outlined
        var targetReps: Int?            // nil → render ∞ for failure
        var targetWeight: Double?       // nil/0 → omit for failure / bodyweight
        var ssLabel: String?            // "1A"/"1B" for supersets
        var isMidPair: Bool             // engine step.rest == false within a pair
        var restEndsAt: Date?           // absolute end; nil when phase == .active
        var totalRest: TimeInterval     // ring fraction base; 0 when active / no rest (restFraction guards on it)
        var nextExerciseName: String?   // UP NEXT preview
        var nextReps: Int?
        var nextWeight: Double?
        var nextSsLabel: String?
        var completedSets: Int          // doneSteps.count
        var totalStepCount: Int         // steps.count
        var palette: Palette            // theme token snapshot for the widget

        /// remaining / totalRest, clamped to 0...1. Drives the rest ring.
        func restFraction(now: Date = Date()) -> Double {
            guard let end = restEndsAt, totalRest > 0 else { return 0 }
            let remaining = end.timeIntervalSince(now)
            return min(max(remaining / totalRest, 0), 1)
        }
    }

    // Static attributes (set once at Activity start).
    var workoutName: String
}
