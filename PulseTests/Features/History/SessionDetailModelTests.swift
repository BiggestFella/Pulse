import XCTest
@testable import Pulse

@MainActor
final class SessionDetailModelTests: XCTestCase {
    private func model(_ store: MockStore, id: WorkoutSession.ID) -> SessionDetailModel {
        SessionDetailModel(sessionID: id,
                           sessionRepo: InMemorySessionRepository(store: store),
                           workoutRepo: InMemoryWorkoutRepository(store: store),
                           programRepo: InMemoryProgramRepository(store: store),
                           exerciseRepo: InMemoryExerciseRepository(store: store))
    }

    private func anySessionID(_ store: MockStore) -> WorkoutSession.ID {
        store.sessions.sorted { $0.startedAt > $1.startedAt }.first!.id
    }

    func testLoadPopulatesSessionAndLoadedPhase() async {
        let store = MockStore()
        let id = anySessionID(store)
        let m = model(store, id: id)
        await m.load()
        XCTAssertEqual(m.phase, .loaded)
        XCTAssertNotNil(m.session)
        XCTAssertFalse(m.session?.name.isEmpty ?? true)
    }

    func testLogRowsPreserveExerciseOrderAndMapFields() async {
        // The legs workout (4 days ago in SampleData) has a known structure.
        let store = MockStore()
        let legsSession = store.sessions.first { $0.workoutID == SampleData.legsWorkout.id }!
        let m = model(store, id: legsSession.id)
        await m.load()
        let log = m.session?.log ?? []
        XCTAssertFalse(log.isEmpty)
        // First logged exercise in the legs workout is Back Squat.
        XCTAssertEqual(log.first?.name, "Back Squat")
        // Detail strings carry "@ <weight>kg".
        XCTAssertTrue(log.first?.detail.contains("kg") ?? false)
        // Per-exercise volume label is non-empty.
        XCTAssertFalse(log.first?.volumeLabel.isEmpty ?? true)
    }

    func testSupersetMembersCombineIntoOneRow() async {
        // Legs workout has a "B" superset: Leg Curl + Calf Raise.
        let store = MockStore()
        let legsSession = store.sessions.first { $0.workoutID == SampleData.legsWorkout.id }!
        let m = model(store, id: legsSession.id)
        await m.load()
        let log = m.session?.log ?? []
        // Neither superset member appears as its own standalone row.
        XCTAssertFalse(log.contains { $0.name == "Leg Curl" })
        XCTAssertFalse(log.contains { $0.name == "Calf Raise" })
        // A combined superset row exists.
        XCTAssertTrue(log.contains { $0.name.contains("superset") })
    }

    func testBodyweightAndFailureRowsRender() async {
        // Build a one-exercise session with a failure bodyweight set.
        let store = MockStore(seeded: false)
        let pushup = SampleData.exercises.first { $0.name == "Push-Up" }!
        store.exercises = [pushup]
        let workout = Workout(name: "Bodyweight", order: 0,
                              exercises: [WorkoutExercise(exercise: pushup, variationID: nil,
                                                          supersetGroup: nil,
                                                          sets: [SetSpec(reps: 18, rir: 0, type: .failure)])])
        store.programs = [Program(name: "P", weeks: 1, isActive: true, workouts: [workout])]
        let session = WorkoutSession(
            workoutID: workout.id, startedAt: Date(), endedAt: Date(),
            sets: [SessionSet(exerciseID: pushup.id, order: 0, reps: 18, weight: 0, type: .failure)])
        store.sessions = [session]
        let m = model(store, id: session.id)
        await m.load()
        let row = m.session?.log.first
        XCTAssertEqual(row?.name, "Push-Up")
        XCTAssertEqual(row?.detail, "To failure · 18")
        XCTAssertEqual(row?.volumeLabel, "BW")
    }

    func testZeroPRDetailRendersPlusZeroDash() async {
        // A session with only warmups → no PR.
        let store = MockStore(seeded: false)
        let ex = SampleData.exercises.first!
        store.exercises = [ex]
        let workout = Workout(name: "Warmups", order: 0,
                              exercises: [WorkoutExercise(exercise: ex, variationID: nil,
                                                          supersetGroup: nil,
                                                          sets: [SetSpec(reps: 8, rir: 0, type: .warmup)])])
        store.programs = [Program(name: "P", weeks: 1, isActive: true, workouts: [workout])]
        let session = WorkoutSession(
            workoutID: workout.id, startedAt: Date(), endedAt: Date(),
            sets: [SessionSet(exerciseID: ex.id, order: 0, reps: 8, weight: 40, type: .warmup)])
        store.sessions = [session]
        let m = model(store, id: session.id)
        await m.load()
        XCTAssertEqual(m.session?.prCount, 0)
        XCTAssertNil(m.session?.prSource)
        XCTAssertEqual(m.prValueLabel, "+0")
        XCTAssertEqual(m.prSubLabel, "—")
        XCTAssertFalse(m.prIsAccent)
    }

    func testUnknownIDSetsErrorPhase() async {
        let m = model(MockStore(), id: UUID())
        await m.load()
        XCTAssertEqual(m.phase, .error)
        XCTAssertNil(m.session)
    }

    func testFailingRepoSetsErrorPhase() async {
        let store = MockStore()
        let id = anySessionID(store)
        store.forceError = true
        let m = model(store, id: id)
        await m.load()
        XCTAssertEqual(m.phase, .error)
    }

    func testDuplicateAndRepeatInvokeHooks() async {
        let store = MockStore()
        let id = anySessionID(store)
        var duplicated: WorkoutSession.ID?
        var repeated: WorkoutSession.ID?
        let m = SessionDetailModel(
            sessionID: id,
            sessionRepo: InMemorySessionRepository(store: store),
            workoutRepo: InMemoryWorkoutRepository(store: store),
            programRepo: InMemoryProgramRepository(store: store),
            exerciseRepo: InMemoryExerciseRepository(store: store),
            onDuplicate: { duplicated = $0 },
            onRepeat: { repeated = $0 })
        await m.load()
        m.duplicate()
        m.repeatWorkout()
        XCTAssertEqual(duplicated, id)
        XCTAssertEqual(repeated, id)
    }
}
