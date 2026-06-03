import XCTest
@testable import Pulse

@MainActor
final class PlanModelLoadTests: XCTestCase {
    private func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal().date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func makeModel(
        plans: [Int: DayPlan],
        workouts: [Workout] = []
    ) -> (PlanModel, FakeScheduleRepository, FakeWorkoutRepository) {
        let sched = FakeScheduleRepository(plansByDay: plans, calendar: cal())
        let lib = FakeWorkoutRepository(workouts: workouts)
        let model = PlanModel(schedule: sched, workouts: lib, calendar: cal(), now: date(2026, 5, 28))
        return (model, sched, lib)
    }

    private func workout(_ name: String) -> Workout {
        Workout(name: name, weekday: nil, order: 0, exercises: [])
    }

    func testLoadPopulatesEverythingAndMarksLoaded() async {
        let w = workout("Chest & Tris")
        // day 20 done, day 28 done-today, day 29 planned, others empty
        let plans: [Int: DayPlan] = [
            20: .done(UUID()),
            28: .done(UUID()),
            29: .workout(w.id)
        ]
        let (model, _, _) = makeModel(plans: plans, workouts: [w])
        await model.load()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.month.daysInMonth, 31)
        XCTAssertEqual(model.month.monthStartOffset, 4)
        XCTAssertEqual(model.schedule[20]?.state, .done)
        XCTAssertEqual(model.schedule[29]?.state, .plan)
        XCTAssertEqual(model.schedule[15]?.state, .empty)
        XCTAssertEqual(model.summary.done, 2)
        XCTAssertEqual(model.summary.planned, 3) // 2 done + 1 plan
    }

    func testTodayNotDoneMapsToTodayState() async {
        let w = workout("Chest & Tris")
        let (model, _, _) = makeModel(plans: [28: .workout(w.id)], workouts: [w])
        await model.load()
        XCTAssertEqual(model.schedule[28]?.state, .today)
    }

    func testTodayDoneStaysDone() async {
        let (model, _, _) = makeModel(plans: [28: .done(UUID())])
        await model.load()
        XCTAssertEqual(model.schedule[28]?.state, .done)
    }

    func testRestDayMapsToEmptyAndIsRest() async {
        let (model, _, _) = makeModel(plans: [29: .rest])
        await model.load()
        XCTAssertEqual(model.schedule[29]?.state, .empty)
        XCTAssertEqual(model.schedule[29]?.isRest, true)
    }

    func testEmptyMonthSummaryIsZeroOverZero() async {
        let (model, _, _) = makeModel(plans: [:])
        await model.load()
        XCTAssertEqual(model.summary.done, 0)
        XCTAssertEqual(model.summary.planned, 0)
        XCTAssertEqual(model.summary.pct, 0)
    }

    func testLoadFailureSetsFailedState() async {
        let (model, sched, _) = makeModel(plans: [:])
        sched.shouldThrow = true
        await model.load()
        XCTAssertEqual(model.loadState, .failed)
        XCTAssertTrue(model.schedule.isEmpty)
    }

    func testModeTogglesBetweenCalendarAndAgenda() {
        let (model, _, _) = makeModel(plans: [:])
        XCTAssertEqual(model.mode, .calendar)
        model.mode = .agenda
        XCTAssertEqual(model.mode, .agenda)
    }
}
