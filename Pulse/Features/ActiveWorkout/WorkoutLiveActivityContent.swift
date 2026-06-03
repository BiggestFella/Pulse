import Foundation

/// Pure projection: maps the live `ActiveWorkoutModel` (BAK-14 session engine)
/// onto a `WorkoutActivityAttributes.ContentState`. No ActivityKit — fully
/// testable against the real engine. Reads engine state only; never fetches data.
///
/// Precondition: call only with a started session in `.active` or `.rest`
/// (`steps` non-empty). The Live Activity controller gates this — `pre`/`summary`
/// have no Activity presentation, so the builder force-indexes the current step.
enum WorkoutLiveActivityContent {
    static func make(from model: ActiveWorkoutModel,
                     palette: Palette) -> WorkoutActivityAttributes.ContentState {
        let step = model.currentStep
        let ex = model.workout.exercises[step.exIdx]
        let spec = ex.sets[step.setIdx]
        let cur = target(model, stepIndex: model.stepIdx)
        let next = model.nextStep
        let nextTarget = target(model, stepIndex: model.stepIdx + 1)
        let isRest = model.phase == .rest

        return WorkoutActivityAttributes.ContentState(
            phase: isRest ? .rest : .active,
            exerciseName: model.displayName(forExercise: step.exIdx),
            setIndex: step.setIdx + 1,
            totalSets: ex.sets.count,
            setTypeLabel: SetTypeLabel.text(for: spec.type),
            targetReps: cur.reps,
            targetWeight: cur.weight,
            ssLabel: step.ssLabel(in: model.workout),
            isMidPair: !step.rest && step.supersetPartnerExIdx != nil,
            restEndsAt: isRest ? model.restEndsAt : nil,
            totalRest: model.restTotal,
            nextExerciseName: next.map { model.displayName(forExercise: $0.exIdx) },
            nextReps: nextTarget.reps,
            nextWeight: nextTarget.weight,
            nextSsLabel: next?.ssLabel(in: model.workout),
            completedSets: model.doneSteps.count,
            totalStepCount: model.steps.count,
            palette: palette)
    }

    /// Target reps/weight for a step; failure sets carry nil (render ∞ / no weight).
    private static func target(_ model: ActiveWorkoutModel,
                               stepIndex: Int) -> (reps: Int?, weight: Double?) {
        // Bounds-guarded because this is also called for stepIdx+1 (the UP NEXT
        // preview), which is out of range on the final step.
        guard model.steps.indices.contains(stepIndex) else { return (nil, nil) }
        let step = model.steps[stepIndex]
        let sets = model.workout.exercises[step.exIdx].sets
        guard step.setIdx < sets.count else { return (nil, nil) }
        let spec = sets[step.setIdx]
        if spec.type == .failure { return (nil, nil) }
        return (spec.reps, model.plannedWeight(forStepIndex: stepIndex))
    }
}
