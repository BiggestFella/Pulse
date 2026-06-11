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
