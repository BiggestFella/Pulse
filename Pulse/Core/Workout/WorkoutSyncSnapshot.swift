import Foundation

/// Phone → watch session-state snapshot. A trimmed projection of the engine —
/// only the fields the watch renders plus the `soundOnRestEnd` haptic gate.
/// Pure value type with no UIKit/WatchKit imports so it compiles on both
/// iOS and watchOS. Sibling of `WorkoutActivityAttributes.ContentState`.
struct WorkoutSyncSnapshot: Codable, Hashable {
    enum Phase: String, Codable { case idle, active, rest, summary }

    var isActive: Bool
    var phase: Phase
    var exerciseName: String        // resolves session swaps
    var ssLabel: String?            // "1A"/"1B" for supersets
    var setIndex: Int               // 1-based
    var totalSets: Int
    var setTypeLabel: String        // WORKING / WARMUP / DROPSET / TO FAILURE / AMRAP
    var targetReps: Int?            // nil → render ∞ for failure
    var targetWeight: Double?       // nil/0 → bodyweight / failure (no weight)
    var isFailure: Bool
    var nextExerciseName: String?   // UP NEXT preview on the rest screen
    var nextReps: Int?
    var restEndsAt: Date?           // absolute end; nil when not resting
    var totalRest: TimeInterval     // ring fraction base; 0 when not resting
    var soundOnRestEnd: Bool        // gates the wrist haptics

    /// Shown when no session is running (join-only: phone hasn't started one).
    static let idle = WorkoutSyncSnapshot(
        isActive: false, phase: .idle, exerciseName: "", ssLabel: nil,
        setIndex: 0, totalSets: 0, setTypeLabel: "", targetReps: nil,
        targetWeight: nil, isFailure: false, nextExerciseName: nil, nextReps: nil,
        restEndsAt: nil, totalRest: 0, soundOnRestEnd: true)

    /// remaining / totalRest, clamped to 0...1. Drives the watch rest ring.
    func restFraction(now: Date = Date()) -> Double {
        guard let end = restEndsAt, totalRest > 0 else { return 0 }
        return min(max(end.timeIntervalSince(now) / totalRest, 0), 1)
    }

    /// Seconds remaining on rest from `now`, clamped at 0.
    func remainingRest(now: Date = Date()) -> TimeInterval {
        guard let end = restEndsAt else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }
}

/// Watch → phone command. The phone applies it to `ActiveWorkoutModel` then
/// re-broadcasts; the watch never mutates session truth locally.
enum WorkoutCommand: Codable, Hashable {
    case logSet          // log current set with the phone's seeded reps × weight
    case skipSet         // advance without logging
    case skipRest        // end rest early (== afterRest)
    case nextSet         // explicit advance (alias used by the set screen)
    case adjustRest(delta: TimeInterval)
}

/// Transport seam. The phone sends snapshots and receives commands; the watch
/// receives snapshots and sends commands. Two conforming impls (`WCSession`)
/// plus a `MockWorkoutSyncChannel` for tests.
protocol WorkoutSyncChannel: AnyObject {
    /// Phone: broadcast latest state. Watch: no-op (or send last command echo).
    func send(state: WorkoutSyncSnapshot)
    /// Phone: send a command (used by the watch impl). Phone impl is a no-op.
    func send(command: WorkoutCommand)
    /// Register a handler for inbound snapshots (watch side).
    func onState(_ handler: @escaping (WorkoutSyncSnapshot) -> Void)
    /// Register a handler for inbound commands (phone side).
    func onCommand(_ handler: @escaping (WorkoutCommand) -> Void)
}
