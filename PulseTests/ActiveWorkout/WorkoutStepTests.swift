import XCTest
@testable import Pulse

final class WorkoutStepTests: XCTestCase {

    private func ex(_ name: String, group: String = "Chest",
                    superset: String? = nil, setCount: Int) -> WorkoutExercise {
        WorkoutExercise(
            exercise: Exercise(name: name, muscleGroup: group, variations: []),
            variationID: nil,
            supersetGroup: superset,
            sets: (0..<setCount).map { _ in SetSpec(reps: 10, rir: 2, type: .working) }
        )
    }
    private func workout(_ exercises: [WorkoutExercise]) -> Workout {
        Workout(name: "W", weekday: nil, order: 0, exercises: exercises)
    }

    func testNonSupersetOneStepPerSetAllRestExceptLast() {
        let w = workout([ex("Bench", setCount: 3)])
        let steps = buildSteps(w)
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(steps.map(\.exIdx), [0, 0, 0])
        XCTAssertEqual(steps.map(\.setIdx), [0, 1, 2])
        XCTAssertEqual(steps.map(\.rest), [true, true, false])
        XCTAssertTrue(steps.allSatisfy { $0.supersetPartnerExIdx == nil })
    }

    func testSupersetInterleavesRoundsAndRestsOnLastMember() {
        let a = ex("A", superset: "ss1", setCount: 2)
        let b = ex("B", superset: "ss1", setCount: 2)
        let steps = buildSteps(workout([a, b]))
        XCTAssertEqual(steps.map(\.exIdx), [0, 1, 0, 1])
        XCTAssertEqual(steps.map(\.setIdx), [0, 0, 1, 1])
        XCTAssertEqual(steps.map(\.rest), [false, true, false, false])
        XCTAssertEqual(steps.map(\.supersetPartnerExIdx), [1, 0, 1, 0])
    }

    func testSupersetMemberWithFewerSetsSkippedInLaterRounds() {
        let a = ex("A", superset: "ss1", setCount: 3)
        let b = ex("B", superset: "ss1", setCount: 1)
        let steps = buildSteps(workout([a, b]))
        XCTAssertEqual(steps.map(\.exIdx), [0, 1, 0, 0])
        XCTAssertEqual(steps.map(\.setIdx), [0, 0, 1, 2])
    }

    func testSsLabelDerivedFromGroupPosition() {
        let a = ex("A", superset: "ss1", setCount: 1)
        let b = ex("B", superset: "ss1", setCount: 1)
        let w = workout([a, b])
        let steps = buildSteps(w)
        XCTAssertEqual(steps[0].ssLabel(in: w), "1A")
        XCTAssertEqual(steps[1].ssLabel(in: w), "1B")
    }

    func testExerciseStepsMapsExIdxToStepIndices() {
        let a = ex("A", superset: "ss1", setCount: 2)
        let b = ex("B", superset: "ss1", setCount: 2)
        let map = exerciseSteps(buildSteps(workout([a, b])))
        XCTAssertEqual(map[0], [0, 2])
        XCTAssertEqual(map[1], [1, 3])
    }

    func testSingleSetWorkoutLastStepNoRest() {
        let steps = buildSteps(workout([ex("Solo", setCount: 1)]))
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].rest, false)
    }
}
