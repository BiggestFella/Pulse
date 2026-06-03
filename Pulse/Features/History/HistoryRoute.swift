import Foundation

/// Destinations reachable from the You → Workout history stack.
enum HistoryRoute: Hashable {
    case history
    case sessionDetail(WorkoutSession.ID)
}
