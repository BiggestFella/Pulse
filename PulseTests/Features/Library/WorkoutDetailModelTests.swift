import XCTest
@testable import Pulse

@MainActor
final class WorkoutDetailModelTests: XCTestCase {

    private func legExtension(reps: [Int]) -> WorkoutExercise {
        let v = Variation(name: "Machine", equipment: "Machine")
        let ex = Exercise(name: "Leg Extension", muscleGroup: "Legs",
                          variations: [v], defaultVariationID: v.id)
        let sets = reps.map { SetSpec(reps: $0, rir: 1, type: .working) }
        return WorkoutExercise(exercise: ex, variationID: v.id, supersetGroup: nil, sets: sets)
    }

    private func workout(_ exercises: [WorkoutExercise]) -> Workout {
        Workout(name: "Legs B", order: 0, exercises: exercises)
    }

    func testLoadBuildsRowsFromWorkout() async {
        let w = workout([legExtension(reps: [12, 10, 8, 6])])
        let repo = FakeWorkoutRepository(workouts: [w])
        let model = WorkoutDetailModel(workoutID: w.id, title: "Legs B",
                                       workoutRepo: repo,                                       onStart: { _ in })
        await model.load()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.rows[0].exerciseName, "Leg Extension")
        XCTAssertEqual(model.rows[0].variationName, "Machine")
        XCTAssertEqual(model.rows[0].setSummary, "4 sets · 12·10·8·6")
        XCTAssertTrue(model.canStart)
    }

    func testStartInvokesCallbackWithWorkout() async {
        let w = workout([legExtension(reps: [10])])
        let repo = FakeWorkoutRepository(workouts: [w])
        var started: Workout?
        let model = WorkoutDetailModel(workoutID: w.id, title: "Legs B",
                                       workoutRepo: repo,                                       onStart: { started = $0 })
        await model.load()
        model.start()
        XCTAssertEqual(started?.id, w.id)
    }

    func testEmptyWorkoutDisablesStart() async {
        let w = workout([])
        let repo = FakeWorkoutRepository(workouts: [w])
        var started: Workout?
        let model = WorkoutDetailModel(workoutID: w.id, title: "Empty",
                                       workoutRepo: repo,                                       onStart: { started = $0 })
        await model.load()
        XCTAssertFalse(model.canStart)
        model.start()
        XCTAssertNil(started, "start() must be a no-op when there are no exercises")
    }

    func testMissingWorkoutIsError() async {
        let repo = FakeWorkoutRepository(workouts: [])
        let model = WorkoutDetailModel(workoutID: UUID(), title: "Gone",
                                       workoutRepo: repo,                                       onStart: { _ in })
        await model.load()
        XCTAssertEqual(model.loadState, .error)
        XCTAssertFalse(model.canStart)
    }

    func testVariationNameFallsBackToDefaultWhenUnset() async {
        let v = Variation(name: "Hammer Strength", equipment: "Machine")
        let ex = Exercise(name: "Flat Chest Press", muscleGroup: "Chest",
                          variations: [v], defaultVariationID: v.id)
        // variationID nil → row should resolve the name via defaultVariationID.
        let we = WorkoutExercise(exercise: ex, variationID: nil, supersetGroup: nil,
                                 sets: [SetSpec(reps: 8, rir: 1, type: .working)])
        let w = workout([we])
        let repo = FakeWorkoutRepository(workouts: [w])
        let model = WorkoutDetailModel(workoutID: w.id, title: "Push",
                                       workoutRepo: repo,                                       onStart: { _ in })
        await model.load()
        XCTAssertEqual(model.rows.first?.variationName, "Hammer Strength")
    }
}
