import XCTest
@testable import Pulse

@MainActor
final class PlanScheduleResolutionTests: XCTestCase {
    func testRecurringWorkoutAppearsOnItsWeekdayWithoutAPlanEntry() async throws {
        let store = MockStore()
        store.schedule = [:]                    // no per-date entries
        // SampleData.program already contains Push (weekdays:[1]) / Pull (weekdays:[3]) /
        // Legs (weekdays:[5]). MockStore(seeded:true) puts them in store.programs, so
        // InMemoryWorkoutRepository.fetchWorkouts() returns all three via store.allWorkouts.
        let cal = SampleData.calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!  // Monday
        let model = PlanModel(schedule: InMemoryScheduleRepository(store: store),
                              workouts: InMemoryWorkoutRepository(store: store),
                              calendar: cal, now: now)
        await model.load()
        XCTAssertEqual(model.agenda.first?.name, "Push")   // Push recurs on Monday
    }
}
