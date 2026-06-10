import XCTest
@testable import Pulse

final class ActiveWorkoutModelTests: XCTestCase {

    private struct SaveFailed: Error {}

    private func makeModel(writer: MockSessionWriter = MockSessionWriter()) -> ActiveWorkoutModel {
        ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MockHistoryRepository(),
            sessionWriter: writer
        )
    }
    private func started() -> ActiveWorkoutModel {
        let m = makeModel(); m.startWorkout(ActiveWorkoutSample.workout); return m
    }
    private func started(writer: MockSessionWriter) -> ActiveWorkoutModel {
        let m = makeModel(writer: writer); m.startWorkout(ActiveWorkoutSample.workout); return m
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

    // afterRest is idempotent — a stray timer tick after leaving rest is a no-op.
    func testAfterRestIsIdempotentAcrossStrayTicks() {
        let m = started(); m.beginSets()
        m.logSet(reps: 15, weight: 40)   // → rest at step 0
        XCTAssertEqual(m.phase, .rest)
        m.afterRest()                    // rest → active, advance to step 1
        XCTAssertEqual(m.stepIdx, 1)
        m.afterRest()                    // stray tick while already active → no-op
        XCTAssertEqual(m.stepIdx, 1)
        XCTAssertEqual(m.phase, .active)
    }

    // MARK: - BAK-30: failure/AMRAP sets record actual reps + weight

    // A to-failure set with real reps logged shows the actual work, not just "To failure".
    func testFailureSetLogsActualRepsAndWeightInLogRows() {
        let m = started(); m.beginSets()
        m.jump(toExerciseIndex: 4)                 // pushup, single failure set
        XCTAssertEqual(m.currentStep.exIdx, 4)
        m.logSet(reps: 8, weight: 60)              // entered actual reps + weight
        let row = m.logRows.first { $0.id == 4 }
        XCTAssertNotNil(row)
        XCTAssertTrue(row!.summaryLine.contains("8"), "expected logged reps in: \(row!.summaryLine)")
        XCTAssertTrue(row!.summaryLine.contains("60 kg"), "expected logged weight in: \(row!.summaryLine)")
        XCTAssertTrue(row!.summaryLine.contains("To failure"), "set type still legible: \(row!.summaryLine)")
    }

    // A failure set with nothing entered still reads "To failure" (no "0 @ 0 kg").
    func testFailureSetWithNoRepsStillReadsToFailure() {
        let m = started(); m.beginSets()
        m.jump(toExerciseIndex: 4)
        m.logSet(reps: 0, weight: 0)
        let row = m.logRows.first { $0.id == 4 }
        XCTAssertEqual(row?.summaryLine, "To failure")
    }

    // MARK: - BAK-31: finished workout persists; saves surface success/failure

    func testFinishAndSaveSuccessMarksSavedAndTearsDown() async {
        let writer = MockSessionWriter()
        let m = started(writer: writer); m.beginSets()
        m.logSet(reps: 12, weight: 100)
        await m.finishAndSave()
        XCTAssertEqual(m.saveState, .saved)
        XCTAssertFalse(m.isActive)                 // teardown only on success
        XCTAssertEqual(writer.saved.count, 1)
    }

    func testFinishAndSaveFailureSurfacesErrorAndKeepsSession() async {
        let writer = MockSessionWriter(); writer.failAlways = SaveFailed()
        let m = started(writer: writer); m.beginSets()
        m.logSet(reps: 12, weight: 100)
        await m.finishAndSave()
        if case .failed = m.saveState {} else { XCTFail("expected .failed, got \(m.saveState)") }
        XCTAssertTrue(m.isActive)                  // workout NOT silently dropped
        XCTAssertTrue(writer.saved.isEmpty)
    }

    func testRetrySaveSucceedsAfterTransientFailure() async {
        let writer = MockSessionWriter(); writer.failOnce = SaveFailed()
        let m = started(writer: writer); m.beginSets()
        m.logSet(reps: 12, weight: 100)
        await m.finishAndSave()                     // first attempt throws
        if case .failed = m.saveState {} else { XCTFail("expected .failed, got \(m.saveState)") }
        await m.retrySave()                         // second attempt succeeds
        XCTAssertEqual(m.saveState, .saved)
        XCTAssertFalse(m.isActive)
        XCTAssertEqual(writer.saved.count, 1)
        XCTAssertEqual(writer.attempts, 2)
    }

    // MARK: - BAK-32: offline finish buffers + surfaces a calm pending-sync state

    // An offline (URLError) save means the writer has buffered the session
    // on-device, so the model finishes calmly as .pendingSync and keeps the
    // summary up (Done tears it down) rather than blocking on .failed.
    func testOfflineFinishSurfacesPendingSyncAndKeepsSummary() async {
        let writer = MockSessionWriter(); writer.failAlways = URLError(.notConnectedToInternet)
        let m = started(writer: writer); m.beginSets()
        m.logSet(reps: 12, weight: 100)
        await m.finishAndSave()
        XCTAssertEqual(m.saveState, .pendingSync)
        XCTAssertTrue(m.isActive)                  // summary stays up to show the note
        m.endWorkout()                             // Done button
        XCTAssertFalse(m.isActive)
    }

    // A non-connectivity error is a hard failure: keep the blocking BAK-31 UI.
    func testHardFailureStillBlocksWithRetry() async {
        let writer = MockSessionWriter(); writer.failAlways = NSError(domain: "server", code: 500)
        let m = started(writer: writer); m.beginSets()
        m.logSet(reps: 12, weight: 100)
        await m.finishAndSave()
        if case .failed = m.saveState {} else { XCTFail("expected .failed, got \(m.saveState)") }
        XCTAssertTrue(m.isActive)
    }

    // PR count consults the history baseline (not trivially "everything is a PR").
    func testPRCountUsesHistoryBaseline() async {
        let m = started(); m.beginSets()
        await m.loadPRBaselines()        // mock history best est-1RM ≈ 76 kg
        m.skipSet()                      // skip bench warmup (step 0) → step 1 (working)
        m.logSet(reps: 1, weight: 10)    // est-1RM 10 ≪ baseline → not a PR
        XCTAssertEqual(m.summary.prCount, 0)
    }

    // Spec AC6 — progressionSuggestion(forStep:) bumps by increment after a session
    // that met targets (via a history mock).
    func testProgressionSuggestionBumpsAfterMetTarget() async throws {
        let m = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MetTargetHistoryRepository(),
            sessionWriter: MockSessionWriter(),
            autoProgress: true)
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
        m.skipSet() // step 0 is bench warmup → step 1 (working, target 12 reps)
        await m.loadSuggestion(forStepIndex: m.stepIdx)
        let s = try XCTUnwrap(m.currentSuggestion)
        XCTAssertEqual(s.weight, 62.5, accuracy: 0.001) // 60 + 2.5
        XCTAssertEqual(s.reps, 12)
        // Spec AC7 — seeds reflect the suggestion when present.
        XCTAssertEqual(m.seedWeight, 62.5, accuracy: 0.001)
        XCTAssertEqual(m.seedReps, 12)
    }

    // Spec AC7 — no history → no suggestion → seeds fall back to SetSpec / planned weight.
    func testNoSuggestionFallsBackToPlannedSeeds() async {
        let m = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: EmptyHistoryRepository(),
            sessionWriter: MockSessionWriter(),
            autoProgress: true)
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
        m.skipSet() // → step 1 (bench working, planned 60 kg, 12 reps)
        await m.loadSuggestion(forStepIndex: m.stepIdx)
        XCTAssertNil(m.currentSuggestion)
        XCTAssertEqual(m.seedWeight, 60, accuracy: 0.001)   // ActiveWorkoutSample.plannedWeight(1,*)
        XCTAssertEqual(m.seedReps, 12)                      // SetSpec.reps
    }

    // Warmup sets get no suggestion even with history.
    func testWarmupStepHasNoSuggestion() async {
        let m = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MetTargetHistoryRepository(),
            sessionWriter: MockSessionWriter(),
            autoProgress: true)
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets() // step 0 = warmup
        await m.loadSuggestion(forStepIndex: m.stepIdx)
        XCTAssertNil(m.currentSuggestion)
    }
}
