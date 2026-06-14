import XCTest
@testable import Pulse

@MainActor
final class WorkoutWeekdaysTests: XCTestCase {
    func testDefaultIsEmpty() {
        XCTAssertEqual(Workout(name: "x", order: 0, exercises: []).weekdays, [])
    }
    func testTodaysWorkoutMatchesAnyWeekdayInSet() async throws {
        let store = MockStore()
        let repo = InMemoryWorkoutRepository(store: store)
        let monday = SampleData.calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))! // Monday
        let hero = try await repo.todaysWorkout(on: monday)
        XCTAssertEqual(hero?.id, SampleData.pushWorkout.id)   // Push recurs on [1]
    }
}
