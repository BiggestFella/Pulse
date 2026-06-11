import Foundation

/// Pure projection: maps the live `ActiveWorkoutModel` onto a
/// `WorkoutSyncSnapshot`. No transport, no WatchKit — fully testable against
/// the real engine. Sibling of `WorkoutLiveActivityContent`.
enum WorkoutSyncSnapshotBuilder {
    @MainActor
    static func make(from model: ActiveWorkoutModel,
                     soundOnRestEnd: Bool) -> WorkoutSyncSnapshot {
        // Join-only: nothing to mirror until the phone starts & begins sets.
        guard model.isActive, !model.steps.isEmpty, model.phase != .pre else {
            var idle = WorkoutSyncSnapshot.idle
            idle.soundOnRestEnd = soundOnRestEnd
            return idle
        }

        let step = model.currentStep
        let ex = model.workout.exercises[step.exIdx]
        let spec = ex.sets.indices.contains(step.setIdx) ? ex.sets[step.setIdx] : nil
        let isRest = model.phase == .rest
        let isFailure = spec?.type == .failure
        let next = model.nextStep

        return WorkoutSyncSnapshot(
            isActive: true,
            phase: model.phase == .summary ? .summary : (isRest ? .rest : .active),
            exerciseName: model.displayName(forExercise: step.exIdx),
            ssLabel: step.ssLabel(in: model.workout),
            setIndex: step.setIdx + 1,
            totalSets: ex.sets.count,
            setTypeLabel: spec.map { SetTypeLabel.text(for: $0.type) } ?? "",
            targetReps: isFailure ? nil : model.seedReps,
            targetWeight: isFailure ? nil : model.seedWeight,
            isFailure: isFailure,
            nextExerciseName: next.map { model.displayName(forExercise: $0.exIdx) },
            nextReps: next.flatMap { n in
                let nx = model.workout.exercises[n.exIdx].sets
                guard nx.indices.contains(n.setIdx), nx[n.setIdx].type != .failure
                else { return nil }
                return nx[n.setIdx].reps
            },
            restEndsAt: isRest ? model.restEndsAt : nil,
            totalRest: isRest ? model.restTotal : 0,
            soundOnRestEnd: soundOnRestEnd)
    }
}
