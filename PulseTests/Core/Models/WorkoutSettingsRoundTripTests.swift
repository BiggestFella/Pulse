import XCTest
@testable import Pulse

@MainActor
final class WorkoutSettingsRoundTripTests: XCTestCase {
    func testRestSecondsAndNotesRoundTripThroughInMemoryRepo() async throws {
        let store = MockStore(seeded: true)
        let repo = InMemoryWorkoutRepository(store: store)
        var w = Workout(name: "Cfg", order: 0, exercises: [], targets: [])
        w.restSeconds = 120
        w.notes = "Heavy day — belt on top sets."
        _ = try await repo.saveWorkout(w)
        let fetched = try await repo.fetchWorkout(id: w.id)
        XCTAssertEqual(fetched?.restSeconds, 120)
        XCTAssertEqual(fetched?.notes, "Heavy day — belt on top sets.")
    }

    func testDefaultsAreNilRestAndEmptyNotes() {
        let w = Workout(name: "Plain", order: 0, exercises: [], targets: [])
        XCTAssertNil(w.restSeconds)
        XCTAssertEqual(w.notes, "")
    }
}
