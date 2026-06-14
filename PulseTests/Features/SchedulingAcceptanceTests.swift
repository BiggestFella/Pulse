import XCTest
@testable import Pulse

/// End-to-end acceptance coverage for the per-workout scheduling feature (BAK-57).
/// Uses InMemory* repos + a shared MockStore so no network or DB is involved.
///
/// Assertions:
///  (a) Weekday recurrence:  setting Mon+Fri on Push → resolver returns Push on
///      2026-06-15 (Mon) and 2026-06-19 (Fri); returns *something else* on 2026-06-16 (Tue).
///  (b) Specific overrides recurrence: a `plan_entry` for a *different* workout on Monday
///      beats the recurring Push.
///  (c) PlanModel agenda: the recurring workout appears in the next-7-day agenda when
///      no specific entry exists for its weekday.
@MainActor
final class SchedulingAcceptanceTests: XCTestCase {

    // MARK: - Helpers

    private func settingsModel(_ store: MockStore, _ w: Workout) -> WorkoutSettingsModel {
        WorkoutSettingsModel(
            workoutID: w.id,
            workoutRepo: InMemoryWorkoutRepository(store: store),
            scheduleRepo: InMemoryScheduleRepository(store: store),
            folderRepo: InMemoryFolderRepository(store: store))
    }

    // MARK: - (a) Weekday recurrence

    func testRecurrenceOnMondayAndFriday() async throws {
        let store = MockStore()
        store.schedule = [:]   // no per-date entries; pure recurrence path

        let cal = SampleData.calendar

        // Set Push → Mon (1) + Fri (5) via the per-workout Settings model
        let m = settingsModel(store, SampleData.pushWorkout)
        await m.load()
        // Push already has weekdays [1] (Mon); add Friday
        await m.toggleWeekday(5)
        // Confirm it persisted
        let reloaded = try await InMemoryWorkoutRepository(store: store)
            .fetchWorkout(id: SampleData.pushWorkout.id)
        XCTAssertEqual(Set(reloaded?.weekdays ?? []), [1, 5],
                       "toggleWeekday(5) should have added Friday to Push")

        let monday = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!   // Mon
        let friday = cal.date(from: DateComponents(year: 2026, month: 6, day: 19))!   // Fri
        let tuesday = cal.date(from: DateComponents(year: 2026, month: 6, day: 16))!  // Tue (no workout)

        let schedRepo = InMemoryScheduleRepository(store: store)
        let wkRepo    = InMemoryWorkoutRepository(store: store)

        let onMonday = try await TodayWorkoutResolver.workout(
            on: monday, schedule: schedRepo, workouts: wkRepo, calendar: cal)
        XCTAssertEqual(onMonday?.id, SampleData.pushWorkout.id,
                       "Push should resolve on Monday (weekday 1)")

        let onFriday = try await TodayWorkoutResolver.workout(
            on: friday, schedule: schedRepo, workouts: wkRepo, calendar: cal)
        XCTAssertEqual(onFriday?.id, SampleData.pushWorkout.id,
                       "Push should resolve on Friday (weekday 5)")

        // Tuesday: no workout has weekday 3 in Push's set; Pull has weekday 3 (Gregorian Wed = appWD 3)
        // so Tuesday (appWD 2) should return nil (no recurring workout on appWD 2)
        let onTuesday = try await TodayWorkoutResolver.workout(
            on: tuesday, schedule: schedRepo, workouts: wkRepo, calendar: cal)
        XCTAssertNil(onTuesday,
                     "No workout recurs on Tuesday; resolver should return nil")
    }

    // MARK: - (b) Specific plan entry overrides recurrence

    func testSpecificEntryOverridesRecurrence() async throws {
        let store = MockStore()
        store.schedule = [:]   // start clean

        let cal = SampleData.calendar
        let monday = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        // Push already recurs on Monday (weekdays [1]); confirm baseline
        let schedRepo = InMemoryScheduleRepository(store: store)
        let wkRepo    = InMemoryWorkoutRepository(store: store)

        let baseline = try await TodayWorkoutResolver.workout(
            on: monday, schedule: schedRepo, workouts: wkRepo, calendar: cal)
        XCTAssertEqual(baseline?.id, SampleData.pushWorkout.id,
                       "Baseline: Push recurs on Monday before any specific entry")

        // Write a specific entry for Pull on that Monday
        try await schedRepo.setPlan(.workout(SampleData.pullWorkout.id), on: monday)

        let overridden = try await TodayWorkoutResolver.workout(
            on: monday, schedule: schedRepo, workouts: wkRepo, calendar: cal)
        XCTAssertEqual(overridden?.id, SampleData.pullWorkout.id,
                       "Specific plan entry for Pull must override Push recurrence on Monday")
        XCTAssertNotEqual(overridden?.id, SampleData.pushWorkout.id,
                          "Push should NOT be returned once Pull has a specific entry on Monday")
    }

    // MARK: - (c) PlanModel agenda reflects recurrence

    func testPlanAgendaShowsRecurringWorkout() async throws {
        let store = MockStore()
        store.schedule = [:]   // no per-date entries

        let cal = SampleData.calendar
        // now = Monday 2026-06-15; Push recurs on Monday (weekday 1)
        let monday = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!

        let model = PlanModel(
            schedule: InMemoryScheduleRepository(store: store),
            workouts: InMemoryWorkoutRepository(store: store),
            calendar: cal,
            now: monday)
        await model.load()

        XCTAssertFalse(model.agenda.isEmpty, "Agenda should contain entries for the upcoming 7 days")
        XCTAssertEqual(model.agenda.first?.name, SampleData.pushWorkout.name,
                       "First agenda entry (today = Monday) should be Push (recurs on weekday 1)")
    }
}
