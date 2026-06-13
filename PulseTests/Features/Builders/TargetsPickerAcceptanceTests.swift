import XCTest
@testable import Pulse

// MARK: - Adjustment note
// The spec used .chest + .triceps as the two targets, but SampleData has no
// exercise with muscleGroup == "Triceps" (arm exercises live under "Arms").
// Replaced .triceps → .back so both targets resolve to real catalog groups
// ("Chest", "Back"), preserving all four intents:
//   (a) targets → sectioned filter works
//   (b) a chosen variation is applied on add
//   (c) makeDraft persists targets in canonical allCases order
//   (d) search forces alphabetical + sorted

@MainActor
final class TargetsPickerAcceptanceTests: XCTestCase {
    private func model() -> WorkoutBuilderModel {
        let store = MockStore()
        let m = WorkoutBuilderModel(catalog: InMemoryExerciseRepository(store: store),
                                    workouts: InMemoryWorkoutRepository(store: store))
        m.catalog = WorkoutBuilderModel.group(SampleData.exercises)
        return m
    }

    func testTargetsDriveThePickerFilterThenPersist() async {
        let m = model()
        m.toggleTarget(.chest); m.toggleTarget(.back)

        // The picker opens pre-filtered to the workout's targets.
        let active = Set(m.targets.map(\.rawValue))
        XCTAssertEqual(ExercisePickerLogic.mode(activeMuscles: active, search: ""), .sectioned)
        let sections = ExercisePickerLogic.sectioned(WorkoutBuilderModel.group(SampleData.exercises),
                                                     activeMuscles: active).map(\.muscle)
        XCTAssertEqual(Set(sections), ["Chest", "Back"])

        // Add an exercise with a chosen variation; the draft persists targets.
        let ex = SampleData.exercises.first { $0.muscleGroup == "Chest" && $0.variations.count > 1 }!
        m.addExercises([PickedExercise(id: ex.id, variationID: ex.variations[1].id)])
        XCTAssertEqual(m.items.first?.variationID, ex.variations[1].id)
        // canonical allCases order: legs, chest, back, shoulders, biceps, triceps, other
        XCTAssertEqual(m.makeDraft().targets, [.chest, .back])
    }

    func testSearchSwitchesToAlphabeticalAcrossMuscles() {
        let catalog = WorkoutBuilderModel.group(SampleData.exercises)
        XCTAssertEqual(ExercisePickerLogic.mode(activeMuscles: ["Chest"], search: "row"), .alphabetical)
        let rows = ExercisePickerLogic.alphabetical(catalog, activeMuscles: [], search: "row")
        XCTAssertEqual(rows.map(\.name), rows.map(\.name).sorted())
    }
}
