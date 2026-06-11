import Foundation

/// Applies a watch-originated `WorkoutCommand` to the phone's `ActiveWorkoutModel`,
/// mapping each command to the same mutation the in-app UI triggers. Commands
/// received in the wrong phase are ignored (the watch reflects truth on the next
/// snapshot). Pure side-effecting function — no transport.
enum WorkoutCommandApplier {
    @MainActor
    static func apply(_ command: WorkoutCommand,
                      to model: ActiveWorkoutModel,
                      now: Date = .now) {
        switch command {
        case .logSet:
            // In-app: "Log set" logs the current step with the seeded reps × weight.
            // Only valid while actively on a set.
            guard model.phase == .active else { return }
            model.logSet(reps: model.seedReps, weight: model.seedWeight, now: now)

        case .skipSet, .nextSet:
            // In-app: "Skip set" advances without logging. Only while active.
            guard model.phase == .active else { return }
            model.skipSet()

        case .skipRest:
            // In-app: "Skip rest" == afterRest. afterRest already guards phase == .rest.
            model.afterRest()

        case .adjustRest(let delta):
            // In-app: ±15/+30 chips. adjustRest already guards restEndsAt != nil,
            // so it is a no-op outside rest.
            guard model.phase == .rest else { return }
            model.adjustRest(delta, now: now)
        }
    }
}
