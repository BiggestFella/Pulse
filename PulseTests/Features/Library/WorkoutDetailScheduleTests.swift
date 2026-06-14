import XCTest
@testable import Pulse

@MainActor
final class WorkoutDetailScheduleTests: XCTestCase {
    private func model(_ store: MockStore, _ w: Workout) -> WorkoutDetailModel {
        WorkoutDetailModel(workoutID: w.id, title: w.name,
                           workoutRepo: InMemoryWorkoutRepository(store: store),
                           scheduleRepo: InMemoryScheduleRepository(store: store),
                           onStart: { _ in })
    }
    func testToggleWeekdayPersists() async {
        let store = MockStore()                 // seeded with SampleData.program which includes pushWorkout (weekdays [1])
        let m = model(store, SampleData.pushWorkout)
        await m.load()
        await m.toggleWeekday(5)                        // add Friday
        let reloaded = try? await InMemoryWorkoutRepository(store: store).fetchWorkout(id: SampleData.pushWorkout.id)
        XCTAssertEqual(Set(reloaded?.weekdays ?? []), [1, 5])
    }
    func testScheduleOnDateWritesPlanEntry() async {
        let store = MockStore()
        let date = SampleData.calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!
        let m = model(store, SampleData.pushWorkout)
        await m.load()
        await m.scheduleOnDate(date)
        let entry = try? await InMemoryScheduleRepository(store: store).plan(for: date)
        XCTAssertEqual(entry, .workout(SampleData.pushWorkout.id))
    }
}
