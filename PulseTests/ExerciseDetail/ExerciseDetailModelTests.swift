import XCTest
@testable import Pulse

@MainActor
final class ExerciseDetailModelTests: XCTestCase {

    // MARK: - Fixtures

    /// Builds a model over a fresh mock store. `bodyweight` swaps in a 0-weight
    /// exercise; `empty` uses a catalog exercise with no logged sessions;
    /// `failing` flips the store into forced-error mode.
    private func makeModel(
        bodyweight: Bool = false,
        empty: Bool = false,
        failing: Bool = false
    ) -> (ExerciseDetailModel, Exercise) {
        let store = MockStore()
        // A bodyweight exercise + a never-logged exercise, both added to the catalog.
        let bw = Exercise(name: "Tricep Push Up", muscleGroup: "Triceps",
                          variations: [], defaultVariationID: nil)
        let unlogged = Exercise(name: "Incline DB Press", muscleGroup: "Chest",
                                variations: [], defaultVariationID: nil)
        store.exercises.append(bw)
        store.exercises.append(unlogged)
        // Body-weight sessions: log Push-Up–style sets at weight 0 for `bw`.
        if bodyweight {
            for daysAgo in [1, 5, 9, 13] {
                let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
                let sets = [
                    SessionSet(exerciseID: bw.id, order: 0, reps: 20, weight: 0, type: .working),
                    SessionSet(exerciseID: bw.id, order: 1, reps: 18, weight: 0, type: .working),
                ]
                store.sessions.append(WorkoutSession(workoutID: UUID(), startedAt: start,
                                                     endedAt: start, sets: sets))
            }
        }
        store.forceError = failing

        let target: Exercise
        if bodyweight { target = bw }
        else if empty { target = unlogged }
        else { target = store.exercises.first { $0.name == "Bench Press" }! }

        let model = ExerciseDetailModel(
            exerciseID: target.id,
            exerciseRepo: InMemoryExerciseRepository(store: store),
            sessionRepo: InMemorySessionRepository(store: store),
            prRepo: InMemoryPRRepository(store: store))
        return (model, target)
    }

    // MARK: - Load

    func testLoadPopulatesAndSetsLoaded() async {
        let (m, target) = makeModel()
        await m.load()
        XCTAssertEqual(m.exercise?.id, target.id)
        XCTAssertFalse(m.sessions.isEmpty)
        guard case .loaded = m.phase else { return XCTFail("expected .loaded, got \(m.phase)") }
    }

    func testSessionsAreMostRecentFirstAndCappedAtFour() async {
        let (m, _) = makeModel()
        await m.load()
        XCTAssertLessThanOrEqual(m.sessions.count, 4)
        if m.sessions.count >= 2 {
            XCTAssertGreaterThan(m.sessions[0].date, m.sessions[1].date, "most recent first")
        }
    }

    // MARK: - Personal best

    func testShowsPersonalBestTrueWhenTopWeightPositive() async {
        let (m, _) = makeModel()
        await m.load()
        XCTAssertTrue(m.showsPersonalBest)
        XCTAssertNotNil(m.personalBest)
        XCTAssertGreaterThan(m.personalBest!.topWeight, 0)
    }

    func testShowsPersonalBestFalseForBodyweight() async {
        let (m, _) = makeModel(bodyweight: true)
        await m.load()
        XCTAssertFalse(m.showsPersonalBest)
        XCTAssertNil(m.personalBest)
    }

    // MARK: - Variations

    func testVariationsPrependAllAndDefaultSelectionMulti() async {
        let (m, _) = makeModel()  // Bench Press → ["Barbell","Dumbbell","Smith"]
        await m.load()
        XCTAssertEqual(m.variations.first?.label, "All")
        XCTAssertEqual(m.variations.count, 4)
        XCTAssertTrue(m.showsVariationPills)
        XCTAssertEqual(m.selectedVariationIndex, 1, "first named variation is default")
    }

    func testNoVariationsHidesPillsAndSelectsAll() async {
        let (m, _) = makeModel(bodyweight: true)  // no variations
        await m.load()
        XCTAssertEqual(m.variations.map(\.label), ["All"])
        XCTAssertFalse(m.showsVariationPills)
        XCTAssertEqual(m.selectedVariationIndex, 0)
    }

    func testSelectVariationUpdatesIndexOnly() async {
        let (m, _) = makeModel()
        await m.load()
        let before = m.sessions
        m.selectVariation(2)
        XCTAssertEqual(m.selectedVariationIndex, 2)
        XCTAssertEqual(m.sessions, before, "cosmetic for v1 — does not re-query")
    }

    func testSelectVariationIgnoresOutOfRange() async {
        let (m, _) = makeModel()
        await m.load()
        m.selectVariation(99)
        XCTAssertEqual(m.selectedVariationIndex, 1)
    }

    // MARK: - Chart scaling

    func testMaxVolumeIsNeverZero() async {
        let (m, _) = makeModel(bodyweight: true)  // all volumes 0
        await m.load()
        XCTAssertGreaterThan(m.maxVolume, 0)
    }

    // MARK: - Empty / error

    func testEmptyHistorySetsEmptyPhase() async {
        let (m, _) = makeModel(empty: true)
        await m.load()
        XCTAssertTrue(m.sessions.isEmpty)
        guard case .empty = m.phase else { return XCTFail("expected .empty, got \(m.phase)") }
    }

    func testRepositoryFailureSetsErrorPhaseAndNoStaleData() async {
        let (m, _) = makeModel(failing: true)
        await m.load()
        guard case .error = m.phase else { return XCTFail("expected .error, got \(m.phase)") }
        XCTAssertTrue(m.sessions.isEmpty)
        XCTAssertNil(m.personalBest)
    }

    // MARK: - Header strings

    func testEyebrowReflectsMuscleGroup() async {
        let (m, _) = makeModel()
        await m.load()
        XCTAssertTrue(m.eyebrowText.hasPrefix("CHEST"))
        XCTAssertTrue(m.eyebrowText.contains("·"))
    }
}
