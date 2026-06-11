import XCTest
@testable import Pulse

final class WorkoutSyncTests: XCTestCase {

    // AC3: snapshot encodes the fields the watch needs and round-trips.
    func testSnapshotCodableRoundTrip() throws {
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        let original = WorkoutSyncSnapshot(
            isActive: true,
            phase: .rest,
            exerciseName: "Bench Press",
            ssLabel: "1A",
            setIndex: 2,
            totalSets: 4,
            setTypeLabel: "WORKING",
            targetReps: 8,
            targetWeight: 60,
            isFailure: false,
            nextExerciseName: "Incline DB",
            nextReps: 10,
            restEndsAt: end,
            totalRest: 90,
            soundOnRestEnd: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutSyncSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // AC3: nil weight / nil reps (failure / bodyweight) round-trip.
    func testSnapshotNilFieldsRoundTrip() throws {
        let original = WorkoutSyncSnapshot(
            isActive: true, phase: .active, exerciseName: "Pushups",
            ssLabel: nil, setIndex: 1, totalSets: 3, setTypeLabel: "TO FAILURE",
            targetReps: nil, targetWeight: nil, isFailure: true,
            nextExerciseName: nil, nextReps: nil,
            restEndsAt: nil, totalRest: 0, soundOnRestEnd: false)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutSyncSnapshot.self, from: data), original)
    }

    // AC3: idle (no session) snapshot round-trips.
    func testIdleSnapshotRoundTrip() throws {
        let data = try JSONEncoder().encode(WorkoutSyncSnapshot.idle)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutSyncSnapshot.self, from: data),
                       WorkoutSyncSnapshot.idle)
    }

    // Command codec round-trips for every case (sendMessage uses a dictionary,
    // so the codec is the safety net for the payload).
    func testCommandCodableRoundTrip() throws {
        let commands: [WorkoutCommand] = [
            .logSet, .skipSet, .skipRest, .nextSet, .adjustRest(delta: 15), .adjustRest(delta: -15)
        ]
        for c in commands {
            let data = try JSONEncoder().encode(c)
            XCTAssertEqual(try JSONDecoder().decode(WorkoutCommand.self, from: data), c)
        }
    }
}

@MainActor
extension WorkoutSyncTests {

    private func started() -> ActiveWorkoutModel {
        let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                                   historyRepo: MockHistoryRepository(),
                                   sessionWriter: MockSessionWriter())
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
        return m
    }

    // AC3: builder pulls the engine's current step, seeds, phase, restEndsAt.
    func testBuilderProjectsActiveStep() {
        let m = started()                                   // step 0 = bench warmup
        let snap = WorkoutSyncSnapshotBuilder.make(from: m, soundOnRestEnd: true)
        XCTAssertTrue(snap.isActive)
        XCTAssertEqual(snap.phase, .active)
        XCTAssertEqual(snap.exerciseName, m.displayName(forExercise: m.currentStep.exIdx))
        XCTAssertEqual(snap.setIndex, m.currentStep.setIdx + 1)
        XCTAssertEqual(snap.targetReps, m.seedReps)
        XCTAssertEqual(snap.targetWeight, m.seedWeight)
        XCTAssertNil(snap.restEndsAt)
        XCTAssertTrue(snap.soundOnRestEnd)
    }

    // AC3: rest snapshot carries the absolute restEndsAt + totalRest for the ring.
    func testBuilderProjectsRest() {
        let m = started()
        let t0 = Date(timeIntervalSince1970: 5_000_000)
        m.logSet(reps: 15, weight: 40, now: t0)             // → rest
        let snap = WorkoutSyncSnapshotBuilder.make(from: m, soundOnRestEnd: false)
        XCTAssertEqual(snap.phase, .rest)
        XCTAssertEqual(snap.restEndsAt, t0.addingTimeInterval(m.restTotal))
        XCTAssertEqual(snap.totalRest, m.restTotal)
        XCTAssertFalse(snap.soundOnRestEnd)
    }

    // AC3: a not-started model projects the idle snapshot (join-only).
    func testBuilderIdleWhenInactive() {
        let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                                   historyRepo: MockHistoryRepository(),
                                   sessionWriter: MockSessionWriter())
        let snap = WorkoutSyncSnapshotBuilder.make(from: m, soundOnRestEnd: true)
        XCTAssertFalse(snap.isActive)
        XCTAssertEqual(snap.phase, .idle)
    }
}

/// In-memory channel for unit tests. Records what was sent and lets a test
/// drive the inbound handlers directly (simulating the paired device).
final class MockWorkoutSyncChannel: WorkoutSyncChannel {
    private(set) var sentStates: [WorkoutSyncSnapshot] = []
    private(set) var sentCommands: [WorkoutCommand] = []
    private var stateHandler: ((WorkoutSyncSnapshot) -> Void)?
    private var commandHandler: ((WorkoutCommand) -> Void)?

    func send(state: WorkoutSyncSnapshot) { sentStates.append(state) }
    func send(command: WorkoutCommand) { sentCommands.append(command) }
    func onState(_ handler: @escaping (WorkoutSyncSnapshot) -> Void) { stateHandler = handler }
    func onCommand(_ handler: @escaping (WorkoutCommand) -> Void) { commandHandler = handler }

    /// Simulate the watch receiving a snapshot.
    func deliver(state: WorkoutSyncSnapshot) { stateHandler?(state) }
    /// Simulate the phone receiving a command.
    func deliver(command: WorkoutCommand) { commandHandler?(command) }
}
