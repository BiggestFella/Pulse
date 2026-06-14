import XCTest
@testable import Pulse

@MainActor
final class PlanModelInteractionTests: XCTestCase {
    private func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal().date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func makeModel(plans: [Int: DayPlan], workouts: [Workout])
        -> (PlanModel, FakeScheduleRepository) {
        let sched = FakeScheduleRepository(plansByDay: plans, calendar: cal())
        let lib = FakeWorkoutRepository(workouts: workouts)
        let model = PlanModel(schedule: sched, workouts: lib, calendar: cal(), now: date(2026, 5, 28))
        return (model, sched)
    }
    private func workout(_ name: String) -> Workout {
        Workout(name: name, order: 0, exercises: [])
    }

    func testSelectTodayLaunchesWorkoutAndDoesNotOpenSheet() async {
        let w = workout("Chest & Tris")
        let (model, _) = makeModel(plans: [28: .workout(w.id)], workouts: [w])
        await model.load()
        var launched = false
        model.onStartWorkout = { launched = true }
        model.selectDay(28)
        XCTAssertTrue(launched)
        XCTAssertNil(model.scheduleSheetDay)
    }

    func testSelectPlannedDayOpensSheet() async {
        let w = workout("Shoulders")
        let (model, _) = makeModel(plans: [29: .workout(w.id)], workouts: [w])
        await model.load()
        model.selectDay(29)
        XCTAssertEqual(model.scheduleSheetDay, 29)
    }

    func testSelectEmptyDayOpensSheet() async {
        let (model, _) = makeModel(plans: [:], workouts: [])
        await model.load()
        model.selectDay(15)
        XCTAssertEqual(model.scheduleSheetDay, 15)
    }

    func testSelectDoneDayOpensSheetNeverLaunches() async {
        let (model, _) = makeModel(plans: [20: .done(UUID())], workouts: [])
        await model.load()
        var launched = false
        model.onStartWorkout = { launched = true }
        model.selectDay(20)
        XCTAssertFalse(launched)
        XCTAssertEqual(model.scheduleSheetDay, 20)
    }

    /// Regression (PR #13 HIGH): a *completed today* must not launch a workout.
    /// Tapping today's calendar row / agenda row routes through selectDay, which
    /// for a done day opens the read-only sheet and never starts a workout.
    func testCompletedTodayDoesNotLaunchAndOpensSheet() async {
        // now = 2026-05-28, so day 28 is today; mark it done.
        let (model, _) = makeModel(plans: [28: .done(UUID())], workouts: [])
        await model.load()

        // The today calendar cell is rendered as .done, not .today.
        XCTAssertEqual(model.schedule[28]?.state, .done)

        // The today agenda row is flagged done -> AgendaListView treats it as
        // non-interactive (no launch CTA) and dims it.
        let todayEntry = model.agenda.first { $0.isToday }
        XCTAssertNotNil(todayEntry)
        XCTAssertTrue(todayEntry?.isDone == true)
        XCTAssertEqual(todayEntry?.name, "Completed")

        // Tapping (either row routes through selectDay) must NOT launch.
        var launched = false
        model.onStartWorkout = { launched = true }
        model.selectDay(28)
        XCTAssertFalse(launched, "Completed today must never launch a workout")
        XCTAssertEqual(model.scheduleSheetDay, 28, "Completed today opens read-only sheet")
        XCTAssertEqual(model.sheetTitle(for: 28), "Completed.")
    }

    /// Sanity: a not-yet-done today still launches (the CTA path is preserved).
    func testNotDoneTodayStillLaunches() async {
        let w = workout("Push Day")
        let (model, _) = makeModel(plans: [28: .workout(w.id)], workouts: [w])
        await model.load()

        let todayEntry = model.agenda.first { $0.isToday }
        XCTAssertTrue(todayEntry?.isDone == false)

        var launched = false
        model.onStartWorkout = { launched = true }
        model.selectDay(28)
        XCTAssertTrue(launched)
        XCTAssertNil(model.scheduleSheetDay)
    }

    func testAssignUpdatesDayToPlanAndClosesSheet() async {
        let w = workout("Arms")
        let (model, _) = makeModel(plans: [:], workouts: [w])
        await model.load()
        model.scheduleSheetDay = 15
        await model.assign(day: 15, workout: model.savedWorkouts[0])
        XCTAssertEqual(model.schedule[15]?.state, .plan)
        XCTAssertEqual(model.schedule[15]?.workoutName, "Arms")
        XCTAssertNil(model.scheduleSheetDay)
        XCTAssertEqual(model.summary.planned, 1)
    }

    func testAssignRestDayRecordsRestAndClosesSheet() async {
        let (model, _) = makeModel(plans: [:], workouts: [])
        await model.load()
        model.scheduleSheetDay = 16
        await model.assignRestDay(16)
        XCTAssertEqual(model.schedule[16]?.isRest, true)
        XCTAssertEqual(model.schedule[16]?.state, .empty)
        XCTAssertNil(model.scheduleSheetDay)
    }

    func testClearPlannedDayReturnsToEmptyAndClosesSheet() async {
        let w = workout("Legs")
        let (model, _) = makeModel(plans: [17: .workout(w.id)], workouts: [w])
        await model.load()
        model.scheduleSheetDay = 17
        await model.clear(day: 17)
        XCTAssertEqual(model.schedule[17]?.state, .empty)
        XCTAssertNil(model.scheduleSheetDay)
    }

    func testClearDoneDayIsNoOp() async {
        let (model, sched) = makeModel(plans: [20: .done(UUID())], workouts: [])
        await model.load()
        model.scheduleSheetDay = 20
        await model.clear(day: 20)
        XCTAssertEqual(model.schedule[20]?.state, .done)
        XCTAssertNotNil(sched.plansByDay[20]) // entry untouched
        XCTAssertNil(model.scheduleSheetDay)
    }
}
