import XCTest
@testable import Pulse

@MainActor
final class WorkoutBuilderModelTests: XCTestCase {
    // The manipulation tests below need a non-empty builder, so the fixture seeds
    // the sample items explicitly (a real new workout now starts empty — see
    // testNewBuilderStartsEmpty).
    private func makeModel(store: MockStore? = nil) -> WorkoutBuilderModel {
        let store = store ?? MockStore()
        return WorkoutBuilderModel(
            catalog: InMemoryExerciseRepository(store: store),
            workouts: InMemoryWorkoutRepository(store: store),
            items: BuilderSampleData.defaultWorkoutItems)
    }

    func testNewBuilderStartsEmpty() {
        let store = MockStore()
        let model = WorkoutBuilderModel(
            catalog: InMemoryExerciseRepository(store: store),
            workouts: InMemoryWorkoutRepository(store: store))
        XCTAssertTrue(model.items.isEmpty)
    }

    func testSeededFixtureHasTwoItems() {
        let model = makeModel()
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.items.first?.exercise.name, "Flat bench")
    }

    func testUpdateVariationChangesSelection() {
        let v1 = Variation(name: "Barbell", equipment: "barbell")
        let v2 = Variation(name: "Dumbbell", equipment: "dumbbell")
        let ex = Exercise(name: "Press", muscleGroup: "Chest",
                          variations: [v1, v2], defaultVariationID: v1.id)
        let item = BuilderExercise(exercise: ex, variationID: v1.id,
                                   supersetGroup: nil,
                                   sets: [SetSpec(reps: 8, rir: 2, type: .working)])
        let store = MockStore()
        let model = WorkoutBuilderModel(
            catalog: InMemoryExerciseRepository(store: store),
            workouts: InMemoryWorkoutRepository(store: store),
            items: [item])
        model.updateVariation(itemID: item.id, variationID: v2.id)
        XCTAssertEqual(model.items.first?.variationID, v2.id)
    }

    func testTotalSetsSumsSetCounts() {
        let model = makeModel()
        XCTAssertEqual(model.totalSets, 9) // 5 + 4
    }

    func testAddExercisesAppendsAndSkipsDuplicates() async {
        let model = makeModel()
        await model.loadCatalog()
        // Pick a catalog exercise not in the seeded list (seeds are Flat bench /
        // Incline press by name; the SampleData catalog uses different names).
        let newID = model.catalog[1].exercises[0].id
        let before = model.items.count
        model.addExercises([newID, newID]) // duplicate id in the same call
        XCTAssertEqual(model.items.count, before + 1)
        // Adding the same id again is skipped.
        model.addExercises([newID])
        XCTAssertEqual(model.items.count, before + 1)
    }

    func testAddedExerciseSeedsADefaultWorkingSet() async {
        let model = makeModel()
        await model.loadCatalog()
        let newID = model.catalog[1].exercises[0].id
        model.addExercises([newID])
        XCTAssertEqual(model.items.last?.sets.count, 1)
        XCTAssertEqual(model.items.last?.sets.first?.type, .working)
    }

    func testAddedExerciseSeedsDefaultVariation() async {
        let model = makeModel()
        await model.loadCatalog()
        let picked = model.catalog[0].exercises[0]
        model.addExercises([picked.id])
        XCTAssertEqual(model.items.last?.variationID, picked.defaultVariationID)
    }

    func testRemoveItemDropsMatch() {
        let model = makeModel()
        let id = model.items[0].id
        model.removeItem(id: id)
        XCTAssertFalse(model.items.contains { $0.id == id })
        XCTAssertEqual(model.items.count, 1)
    }

    func testToggleLinkAssignsSharedGroupThenUnlinks() {
        let model = makeModel()
        model.toggleLink(at: 0)
        let g0 = model.items[0].supersetGroup
        let g1 = model.items[1].supersetGroup
        XCTAssertNotNil(g0)
        XCTAssertEqual(g0, g1)
        // Toggling again breaks the lower row out.
        model.toggleLink(at: 0)
        XCTAssertNil(model.items[1].supersetGroup)
    }

    func testToggleLinkLastRowIsNoOp() {
        let model = makeModel()
        let last = model.items.count - 1
        model.toggleLink(at: last)
        XCTAssertNil(model.items[last].supersetGroup)
    }

    func testAddSetClonesLastAsWorking() {
        let model = makeModel()
        let id = model.items[0].id
        let before = model.items[0].sets.count
        model.addSet(itemID: id)
        XCTAssertEqual(model.items[0].sets.count, before + 1)
        XCTAssertEqual(model.items[0].sets.last?.type, .working)
    }

    func testRemoveSetRefusesWhenOneRemains() {
        let model = makeModel()
        let id = model.items[1].id
        while model.items.first(where: { $0.id == id })!.sets.count > 1 {
            model.removeSet(itemID: id, index: 0)
        }
        XCTAssertEqual(model.items.first(where: { $0.id == id })!.sets.count, 1)
        model.removeSet(itemID: id, index: 0) // refused
        XCTAssertEqual(model.items.first(where: { $0.id == id })!.sets.count, 1)
    }

    func testUpdateSetClampsRIRToZeroFive() {
        let model = makeModel()
        let id = model.items[0].id
        model.updateSet(itemID: id, index: 0, reps: 9, rir: 99, type: .working)
        XCTAssertEqual(model.items[0].sets[0].rir, 5)
        XCTAssertEqual(model.items[0].sets[0].reps, 9)
        model.updateSet(itemID: id, index: 0, reps: 9, rir: -3, type: .amrap)
        XCTAssertEqual(model.items[0].sets[0].rir, 0)
        XCTAssertEqual(model.items[0].sets[0].type, .amrap)
    }

    func testSaveCallsRepositoryAndSetsSaved() async {
        let store = MockStore()
        let workouts = InMemoryWorkoutRepository(store: store)
        let model = WorkoutBuilderModel(
            catalog: InMemoryExerciseRepository(store: store), workouts: workouts)
        await model.save()
        XCTAssertEqual(model.saveState, .saved)
        // The draft was persisted into the active program's workouts.
        let saved = try? await workouts.fetchWorkouts()
        XCTAssertTrue(saved?.contains { $0.name == model.name } ?? false)
    }

    func testSaveErrorWhenRepositoryThrows() async {
        let store = MockStore()
        store.forceError = true
        let model = WorkoutBuilderModel(
            catalog: InMemoryExerciseRepository(store: store),
            workouts: InMemoryWorkoutRepository(store: store))
        await model.save()
        if case .error = model.saveState { } else { XCTFail("expected .error") }
    }

    func testMoveReordersItems() {
        let model = makeModel()                 // seeded: [Flat bench, Incline press]
        let firstID = model.items[0].id
        model.move(from: IndexSet(integer: 0), to: 2)   // move row 0 to the end
        XCTAssertEqual(model.items.last?.id, firstID)
        XCTAssertEqual(model.items.count, 2)
    }

    func testAddExercisesPreservesPassedOrder() async {
        let model = makeModel()
        await model.loadCatalog()
        // Three distinct catalog ids in a deliberate order.
        let a = model.catalog[0].exercises[0].id
        let b = model.catalog[1].exercises[0].id
        let c = model.catalog[1].exercises[1].id
        let before = model.items.count
        model.addExercises([c, a, b])
        let addedIDs = Array(model.items.suffix(model.items.count - before)).map { $0.exercise.id }
        XCTAssertEqual(addedIDs, [c, a, b])  // exact insertion order preserved
    }

    func testToggleTargetAddsAndRemoves() {
        let model = makeModel()
        model.toggleTarget(.chest)
        model.toggleTarget(.triceps)
        XCTAssertEqual(model.targets, [.chest, .triceps])
        model.toggleTarget(.chest)
        XCTAssertEqual(model.targets, [.triceps])
    }

    func testMakeDraftIncludesTargetsInCanonicalOrder() {
        let model = makeModel()
        model.toggleTarget(.triceps)
        model.toggleTarget(.chest)            // toggled out of order
        XCTAssertEqual(model.makeDraft().targets, [.chest, .triceps]) // canonical allCases order
    }
}
