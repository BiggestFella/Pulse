import XCTest
@testable import Pulse

@MainActor
final class WorkoutLiveActivityIntegrationTests: XCTestCase {
    override func tearDown() {
        SkipRestIntent.target = nil
        super.tearDown()
    }

    private func startedModel() -> ActiveWorkoutModel {
        let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                                   historyRepo: MockHistoryRepository(),
                                   sessionWriter: MockSessionWriter())
        m.startWorkout(ActiveWorkoutSample.workout)
        m.beginSets()
        return m
    }

    // AC7: swapping the current exercise re-pushes content with the new display name
    func testSwapRePushesUpdatedName() {
        let model = startedModel()
        let handle = MockActivityHandle()
        let c = WorkoutLiveActivityController(model: model, handle: handle, paletteProvider: { .coastal })
        c.sync()                                   // start: current = bench
        XCTAssertEqual(handle.lastState?.exerciseName, "Flat Machine Press")

        let alt = Exercise(name: "Barbell Bench", muscleGroup: "Chest", variations: [])
        model.swap(exerciseIndex: 0, to: alt)
        c.sync()
        XCTAssertEqual(handle.lastState?.exerciseName, "Barbell Bench")
    }

    // Edge case: Live Activities unavailable → start is a no-op; the flow is unaffected and nothing crashes
    func testDeniedActivityDoesNotCrashFlow() {
        let model = startedModel()
        let handle = DenyingActivityHandle()
        let c = WorkoutLiveActivityController(model: model, handle: handle, paletteProvider: { .coastal })
        c.sync()                                   // start attempted but denied
        XCTAssertFalse(handle.isRunning)
        model.jump(toExerciseIndex: 0); c.sync()   // transitions still safe
        model.endWorkout(); c.sync()               // end is a no-op (never running)
        XCTAssertFalse(handle.isRunning)
    }
}

/// Simulates Live Activities disabled — start never takes effect.
@MainActor
final class DenyingActivityHandle: LiveActivityHandle {
    var isRunning: Bool { false }
    func start(_ state: WorkoutActivityAttributes.ContentState, name: String) {}
    func update(_ state: WorkoutActivityAttributes.ContentState) {}
    func end() {}
}
