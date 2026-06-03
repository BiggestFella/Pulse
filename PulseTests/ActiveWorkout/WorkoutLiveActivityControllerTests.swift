import XCTest
@testable import Pulse

@MainActor
final class WorkoutLiveActivityControllerTests: XCTestCase {
    override func tearDown() {
        SkipRestIntent.target = nil
        super.tearDown()
    }

    private func freshModel() -> ActiveWorkoutModel {
        ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                           historyRepo: MockHistoryRepository(),
                           sessionWriter: MockSessionWriter())
    }

    private func makeController(_ model: ActiveWorkoutModel)
        -> (WorkoutLiveActivityController, MockActivityHandle) {
        let handle = MockActivityHandle()
        let c = WorkoutLiveActivityController(model: model, handle: handle,
                                              paletteProvider: { .coastal })
        return (c, handle)
    }

    // AC1: no Activity during pre; first .active starts it
    func testFirstActiveStartsActivity() {
        let model = freshModel()
        let (c, handle) = makeController(model)
        c.sync()                                  // not started → isActive false
        XCTAssertEqual(handle.startCount, 0)
        model.startWorkout(ActiveWorkoutSample.workout)
        c.sync()                                  // pre → still no Activity
        XCTAssertEqual(handle.startCount, 0)
        model.beginSets()                         // → active
        c.sync()
        XCTAssertEqual(handle.startCount, 1)
        XCTAssertTrue(handle.isRunning)
    }

    // AC1: reaching summary ends the Activity
    func testSummaryEndsActivity() {
        let model = freshModel()
        let (c, handle) = makeController(model)
        model.startWorkout(ActiveWorkoutSample.workout); model.beginSets(); c.sync()
        let lastExIdx = ActiveWorkoutSample.workout.exercises.count - 1
        model.jump(toExerciseIndex: lastExIdx); c.sync()  // last step (pushup), active
        model.logSet(reps: 0, weight: 0); c.sync() // logging last step → summary
        XCTAssertEqual(handle.endCount, 1)
        XCTAssertFalse(handle.isRunning)
    }

    // AC1: endWorkout ends the Activity
    func testEndWorkoutEndsActivity() {
        let model = freshModel()
        let (c, handle) = makeController(model)
        model.startWorkout(ActiveWorkoutSample.workout); model.beginSets(); c.sync()
        model.endWorkout(); c.sync()
        XCTAssertEqual(handle.endCount, 1)
    }

    // AC7: each transition re-pushes content
    func testTransitionPushesUpdate() {
        let model = freshModel()
        let (c, handle) = makeController(model)
        model.startWorkout(ActiveWorkoutSample.workout); model.beginSets(); c.sync() // start
        let before = handle.updateCount
        model.logSet(reps: 15, weight: 60); c.sync()  // warmup → rest
        XCTAssertEqual(handle.updateCount, before + 1)
    }

    // AC8: rest adjust clamps remaining at 0 (no negative); +30 has no upper clamp; both re-push
    func testRestAdjustClampAndPush() {
        let model = freshModel()
        let (c, handle) = makeController(model)
        model.startWorkout(ActiveWorkoutSample.workout); model.beginSets(); c.sync()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        model.logSet(reps: 15, weight: 60, now: t0); c.sync() // → rest, restEndsAt t0+90
        let before = handle.updateCount

        c.adjustRest(by: -1000, now: t0)             // clamp remaining to 0
        XCTAssertEqual(model.restEndsAt, t0)
        XCTAssertEqual(handle.updateCount, before + 1)

        c.adjustRest(by: 30, now: t0)                // no upper clamp
        XCTAssertEqual(model.restEndsAt, t0.addingTimeInterval(30))
        XCTAssertEqual(handle.updateCount, before + 2)
    }

    // AC10: Skip rest routes through model.afterRest then re-pushes
    func testAfterRestAdvancesAndPushes() {
        let model = freshModel()
        let (c, handle) = makeController(model)
        model.startWorkout(ActiveWorkoutSample.workout); model.beginSets(); c.sync()
        let t0 = Date(timeIntervalSince1970: 3_000_000)
        model.logSet(reps: 15, weight: 60, now: t0); c.sync() // → rest at step 0
        let before = handle.updateCount
        c.afterRest()                                // skip rest → advance
        XCTAssertEqual(model.phase, .active)
        XCTAssertEqual(model.stepIdx, 1)
        XCTAssertEqual(handle.updateCount, before + 1)
    }

    // Controller registers itself as the SkipRestIntent target
    func testRegistersAsSkipRestTarget() {
        let model = freshModel()
        let (c, _) = makeController(model)
        XCTAssertTrue(SkipRestIntent.target === c)
    }
}

/// Test double for the ActivityKit handle.
@MainActor
final class MockActivityHandle: LiveActivityHandle {
    private(set) var startCount = 0, updateCount = 0, endCount = 0
    private var running = false
    var isRunning: Bool { running }
    private(set) var lastState: WorkoutActivityAttributes.ContentState?
    func start(_ state: WorkoutActivityAttributes.ContentState, name: String) {
        startCount += 1; running = true; lastState = state
    }
    func update(_ state: WorkoutActivityAttributes.ContentState) {
        updateCount += 1; lastState = state
    }
    func end() { endCount += 1; running = false }
}
