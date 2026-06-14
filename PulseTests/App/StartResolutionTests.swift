import XCTest
@testable import Pulse

@MainActor
final class StartResolutionTests: XCTestCase {
    func testResolvesTodaysRecurringWorkout() async throws {
        let store = MockStore(); store.schedule = [:]   // recurrence-only path
        let cal = SampleData.calendar
        let monday = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let w = try await TodayWorkoutResolver.workout(on: monday,
                  schedule: InMemoryScheduleRepository(store: store),
                  workouts: InMemoryWorkoutRepository(store: store), calendar: cal)
        XCTAssertEqual(w?.id, SampleData.pushWorkout.id)
    }
}
