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
}
