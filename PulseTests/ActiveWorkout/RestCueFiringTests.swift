import XCTest
@testable import Pulse

final class RestCueFiringTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000)

    /// Builds a started model wired to a recording mock cue. `sound` toggles the
    /// gating flag. Returns both so tests can inspect the call log.
    private func make(sound: Bool = true) -> (ActiveWorkoutModel, MockRestCueService) {
        let cue = MockRestCueService()
        let m = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MockHistoryRepository(),
            sessionWriter: MockSessionWriter(),
            restCue: cue,
            soundOnRestEnd: sound)
        m.startWorkout(ActiveWorkoutSample.workout)
        m.beginSets()
        return (m, cue)
    }

    /// Drives the model into rest at `base` (step 0 bench warmup → rest).
    private func enterRest(_ m: ActiveWorkoutModel) {
        m.logSet(reps: 15, weight: 40, now: base)
        XCTAssertEqual(m.phase, .rest)
    }

    // Rest start preps the cue service.
    func testStartRestPreparesCue() {
        let (m, cue) = make()
        enterRest(m)
        XCTAssertEqual(cue.prepareCount, 1)
        XCTAssertEqual(cue.endCount, 0)
    }

    // Auto-finish at 0 fires exactly one end() then teardown().
    func testRestEndFiresEndThenTeardown() {
        let (m, cue) = make()
        enterRest(m)
        _ = m.tick(now: base.addingTimeInterval(90))   // remaining == 0
        XCTAssertEqual(cue.endCount, 1)
        XCTAssertEqual(cue.teardownCount, 1)
        XCTAssertEqual(m.phase, .active)
    }

    // "Skip rest" mid-rest plays NO end cue but still tears down the session.
    func testSkipRestPlaysNoEndButTearsDown() {
        let (m, cue) = make()
        enterRest(m)
        // Skip while remaining > 0. Drive `now` explicitly inside the rest window
        // (the fixed 1970 `base` would otherwise make .now read remaining == 0).
        m.afterRest(now: base.addingTimeInterval(30))   // remaining 60 > 0
        XCTAssertEqual(cue.endCount, 0)
        XCTAssertEqual(cue.teardownCount, 1)
        XCTAssertEqual(m.phase, .active)
    }

    // From a 90s rest, exactly one warn() at <= 10s and exactly one end() at 0.
    func testOneWarnAtTenSecondsAndOneEndAtZero() {
        let (m, cue) = make()
        enterRest(m)
        // Tick across the warn boundary multiple times — must not double-warn.
        _ = m.tick(now: base.addingTimeInterval(79))   // remaining 11 → no warn
        XCTAssertEqual(cue.warnCount, 0)
        _ = m.tick(now: base.addingTimeInterval(80))   // remaining 10 → warn
        _ = m.tick(now: base.addingTimeInterval(80.2)) // still in window → no second warn
        _ = m.tick(now: base.addingTimeInterval(85))   // still in window → no second warn
        XCTAssertEqual(cue.warnCount, 1)
        XCTAssertEqual(cue.endCount, 0)
        _ = m.tick(now: base.addingTimeInterval(90))   // remaining 0 → end
        XCTAssertEqual(cue.endCount, 1)
        XCTAssertEqual(cue.warnCount, 1)
    }

    // A stray tick after the model has already left rest does not fire a 2nd end().
    func testStrayTickAfterFinishDoesNotDoubleFire() {
        let (m, cue) = make()
        enterRest(m)
        _ = m.tick(now: base.addingTimeInterval(90))   // ends: end() once, phase → active
        XCTAssertEqual(cue.endCount, 1)
        _ = m.tick(now: base.addingTimeInterval(90.2)) // stray tick, phase == .active
        _ = m.tick(now: base.addingTimeInterval(91))   // stray tick
        XCTAssertEqual(cue.endCount, 1)                // still one
        XCTAssertEqual(cue.teardownCount, 1)           // teardown not repeated
    }

    // Sound off: no warn() / end(), but rest still progresses and advances the step.
    func testSoundOffSilencesCuesButRestStillAdvances() {
        let (m, cue) = make(sound: false)
        enterRest(m)
        let startStep = m.stepIdx
        _ = m.tick(now: base.addingTimeInterval(80))   // warn window
        _ = m.tick(now: base.addingTimeInterval(90))   // end
        XCTAssertEqual(cue.warnCount, 0)
        XCTAssertEqual(cue.endCount, 0)
        XCTAssertEqual(m.phase, .active)               // advanced
        XCTAssertEqual(m.stepIdx, startStep + 1)
    }

    // Warn fires at 10s; +30s pushes remaining back to 40s and re-arms; a later
    // pass through the 10s window warns a SECOND time.
    func testAdjustAboveThresholdReArmsWarn() {
        let (m, cue) = make()
        enterRest(m)                                    // restEndsAt = base + 90
        _ = m.tick(now: base.addingTimeInterval(82))    // remaining 8 → warn (#1)
        XCTAssertEqual(cue.warnCount, 1)
        m.adjustRest(30, now: base.addingTimeInterval(82)) // remaining 8 → 38 (> 10): re-arm
        XCTAssertFalse(m.didWarn)
        _ = m.tick(now: base.addingTimeInterval(82))    // remaining 38 → no warn yet
        XCTAssertEqual(cue.warnCount, 1)
        _ = m.tick(now: base.addingTimeInterval(112))   // remaining 8 again → warn (#2)
        XCTAssertEqual(cue.warnCount, 2)
    }

    // An adjustment that stays within the warn window does NOT re-arm (no extra warn).
    func testAdjustWithinWindowDoesNotReArm() {
        let (m, cue) = make()
        enterRest(m)
        _ = m.tick(now: base.addingTimeInterval(82))    // remaining 8 → warn (#1)
        m.adjustRest(-2, now: base.addingTimeInterval(82)) // remaining 8 → 6 (still <= 10)
        XCTAssertTrue(m.didWarn)
        _ = m.tick(now: base.addingTimeInterval(82))
        XCTAssertEqual(cue.warnCount, 1)                // no second warn
    }
}
