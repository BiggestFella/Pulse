import XCTest
@testable import Pulse

final class ActiveWorkoutModelTests: XCTestCase {

    private func makeModel() -> ActiveWorkoutModel {
        ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MockHistoryRepository(),
            sessionWriter: MockSessionWriter()
        )
    }
    private func started() -> ActiveWorkoutModel {
        let m = makeModel(); m.startWorkout(ActiveWorkoutSample.workout); return m
    }

    // AC1
    func testStartWorkoutResetsState() {
        let m = makeModel()
        m.startWorkout(ActiveWorkoutSample.workout)
        XCTAssertEqual(m.phase, .pre)
        XCTAssertEqual(m.stepIdx, 0)
        XCTAssertTrue(m.doneSteps.isEmpty)
        XCTAssertTrue(m.swaps.isEmpty)
        XCTAssertEqual(m.steps, buildSteps(ActiveWorkoutSample.workout))
    }

    // AC2
    func testBeginSetsMovesPreToActiveKeepingStepIdx() {
        let m = started()
        m.beginSets()
        XCTAssertEqual(m.phase, .active)
        XCTAssertEqual(m.stepIdx, 0)
    }

    // AC4 — non-superset set logs → rest, idempotent
    func testLogNonSupersetGoesToRestIdempotently() {
        let m = started(); m.beginSets()           // step 0 = bench warmup, rest == true
        m.logSet(reps: 15, weight: 40)
        XCTAssertEqual(m.phase, .rest)
        XCTAssertEqual(m.stepIdx, 0)
        XCTAssertEqual(m.doneSteps, [0])
        m.logSet(reps: 15, weight: 40)             // logging twice does not duplicate
        XCTAssertEqual(m.doneSteps.count, 1)
    }

    // AC5 — mid-superset set advances without rest
    func testLogMidSupersetAdvancesNoRest() {
        let m = started(); m.beginSets()
        m.jump(toExerciseIndex: 2)                 // first superset step (tri cable)
        let step = m.currentStep
        XCTAssertEqual(step.rest, false)           // first member of round → no rest
        m.logSet(reps: 12, weight: 25)
        XCTAssertEqual(m.phase, .active)
        XCTAssertTrue(m.stepIdx > 0)               // advanced
    }

    func testLogButtonLabelMidSupersetReadsPartner() {
        let m = started(); m.beginSets(); m.jump(toExerciseIndex: 2)
        XCTAssertEqual(m.logButtonLabel, "Log → 1B")
    }

    // AC6 — final step → summary, label "Finish workout"
    func testLogFinalStepGoesToSummary() {
        let m = started(); m.beginSets()
        m.jump(toExerciseIndex: 4)                 // pushup, single failure set = last step
        XCTAssertEqual(m.currentStep, m.steps.last)
        XCTAssertEqual(m.logButtonLabel, "Finish workout")
        m.logSet(reps: 0, weight: 0)
        XCTAssertEqual(m.phase, .summary)
    }

    // AC7 — rest auto-advance / afterRest
    func testAfterRestAdvancesAndClampsAtLast() {
        let m = started(); m.beginSets()
        m.logSet(reps: 15, weight: 40)             // → rest at step 0
        m.afterRest()
        XCTAssertEqual(m.phase, .active)
        XCTAssertEqual(m.stepIdx, 1)
        m.jump(toExerciseIndex: 4)
        m.afterRest()
        XCTAssertEqual(m.stepIdx, m.steps.count - 1) // clamped, not summary
        XCTAssertEqual(m.phase, .active)
    }

    // AC8 — rest adjust clamps at 0, no upper clamp
    func testAdjustRestClampsAtZeroNoUpperClamp() {
        let m = started(); m.beginSets()
        let base = Date(timeIntervalSince1970: 1_000)
        m.logSet(reps: 15, weight: 40, now: base)  // restEndsAt = base + 90
        m.adjustRest(30, now: base)
        XCTAssertEqual(m.remainingRest(now: base), 120, accuracy: 0.5)
        m.adjustRest(-1000, now: base)             // clamp at 0
        XCTAssertEqual(m.remainingRest(now: base), 0, accuracy: 0.5)
    }

    // AC9 — skip advances without logging
    func testSkipSetAdvancesWithoutMarkingDone() {
        let m = started(); m.beginSets()
        m.skipSet()
        XCTAssertEqual(m.stepIdx, 1)
        XCTAssertEqual(m.phase, .active)
        XCTAssertTrue(m.doneSteps.isEmpty)
    }

    // AC10 — jump to first un-logged, fallback to first
    func testJumpLandsOnFirstUnloggedStepWithFallback() {
        let m = started(); m.beginSets()
        m.logSet(reps: 15, weight: 40)             // step 0 done
        m.jump(toExerciseIndex: 0)                 // bench steps [0,1,2,3]; first un-logged = 1
        XCTAssertEqual(m.stepIdx, 1)
        [0, 1, 2, 3].forEach { m.markDoneForTest($0) }
        m.jump(toExerciseIndex: 0)                 // all done → fall back to first (0)
        XCTAssertEqual(m.stepIdx, 0)
        XCTAssertEqual(m.phase, .active)
    }

    // AC11 — swap is session-only, does not mutate workout
    func testSwapWritesOverrideWithoutMutatingWorkout() {
        let m = started()
        let alt = Exercise(name: "Pec Deck", muscleGroup: "Chest", variations: [])
        m.swap(exerciseIndex: 0, to: alt)
        XCTAssertEqual(m.swaps[0], alt)
        XCTAssertEqual(m.displayName(forExercise: 0), "Pec Deck")
        XCTAssertEqual(m.workout.exercises[0].exercise.name, "Flat Machine Press") // untouched
    }

    // AC13 — set-type labels cover all five
    func testSetTypeLabelMapCoversAllFiveCases() {
        let m = makeModel()
        for type in SetType.allCases {
            XCTAssertFalse(m.setTypeLabel(type).isEmpty)
        }
        XCTAssertEqual(m.setTypeLabel(.dropset), "DROP SET")
        XCTAssertEqual(m.setTypeLabel(.working), "WORKING")
    }

    // AC16 — summary derived from logged sets, empty-safe
    func testSummaryDerivesVolumeSetsAndIsEmptySafe() {
        let m = started(); m.beginSets()
        XCTAssertEqual(m.summary.totalVolume, 0)
        XCTAssertEqual(m.summary.completedSets, 0)
        XCTAssertEqual(m.summary.totalSets, m.steps.count)
        XCTAssertEqual(m.summary.prCount, 0)
        // Log two WORKING sets — skip the bench warmup at step 0 so volume counts
        // both (warmups are excluded from volume).
        m.skipSet()                                // step 0 (warmup) → step 1
        m.logSet(reps: 12, weight: 100)            // step 1 working → rest
        m.afterRest()                              // → step 2
        m.logSet(reps: 10, weight: 110)            // step 2 working
        XCTAssertEqual(m.summary.completedSets, 2)
        XCTAssertEqual(m.summary.totalVolume, 12 * 100 + 10 * 110, accuracy: 0.5)
    }

    // AC17 — endWorkout clears session
    func testEndWorkoutClearsSession() {
        let m = started(); m.beginSets()
        m.endWorkout()
        XCTAssertFalse(m.isActive)
    }
}
