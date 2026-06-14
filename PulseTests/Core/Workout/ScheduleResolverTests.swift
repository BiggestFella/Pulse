import XCTest
@testable import Pulse

final class ScheduleResolverTests: XCTestCase {
    private let cal = SampleData.calendar
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func workout(_ name: String, order: Int, weekdays: [Int]) -> Workout {
        Workout(name: name, weekdays: weekdays, order: order, exercises: [])
    }
    func testAppWeekdayMapsMondayTo1AndSundayTo7() {
        XCTAssertEqual(ScheduleResolver.appWeekday(of: date(2026, 6, 15), calendar: cal), 1) // Mon
        XCTAssertEqual(ScheduleResolver.appWeekday(of: date(2026, 6, 21), calendar: cal), 7) // Sun
    }
    func testSpecificEntryWins() {
        let w = workout("A", order: 0, weekdays: [1])
        XCTAssertEqual(ScheduleResolver.plan(for: date(2026, 6, 15), entry: .rest, workouts: [w], calendar: cal), .rest)
    }
    func testRecurringWeekdayWhenNoEntry() {
        let w = workout("A", order: 0, weekdays: [1])
        XCTAssertEqual(ScheduleResolver.plan(for: date(2026, 6, 15), entry: nil, workouts: [w], calendar: cal), .workout(w.id))
    }
    func testEmptyWhenNeither() {
        let w = workout("A", order: 0, weekdays: [3])
        XCTAssertNil(ScheduleResolver.plan(for: date(2026, 6, 15), entry: nil, workouts: [w], calendar: cal)) // Mon; w is Wed-only
    }
    func testTiebreakByLowestOrder() {
        let a = workout("A", order: 1, weekdays: [1])
        let b = workout("B", order: 0, weekdays: [1])
        XCTAssertEqual(ScheduleResolver.plan(for: date(2026, 6, 15), entry: nil, workouts: [a, b], calendar: cal), .workout(b.id))
    }
}
