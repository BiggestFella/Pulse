import XCTest
@testable import Pulse

final class WorkoutAnalyticsTests: XCTestCase {
    let ex = UUID()

    private func set(_ reps: Int, _ weight: Double, _ type: SetType) -> SessionSet {
        SessionSet(exerciseID: ex, order: 0, reps: reps, weight: weight, type: type)
    }

    func testSetVolumeExcludesWarmups() {
        XCTAssertEqual(WorkoutAnalytics.setVolume(set(10, 50, .working)), 500)
        XCTAssertEqual(WorkoutAnalytics.setVolume(set(10, 50, .amrap)), 500)
        XCTAssertEqual(WorkoutAnalytics.setVolume(set(10, 50, .warmup)), 0)
        XCTAssertEqual(WorkoutAnalytics.setVolume(set(10, 50, .dropset)), 0)
        XCTAssertEqual(WorkoutAnalytics.setVolume(set(10, 50, .failure)), 0)
    }

    func testSessionVolumeSumsCountingSetsOnly() {
        let session = WorkoutSession(
            workoutID: UUID(), startedAt: Date(), endedAt: nil,
            sets: [set(5, 100, .warmup), set(5, 100, .working), set(8, 80, .working)])
        XCTAssertEqual(WorkoutAnalytics.sessionVolume(session), 100 * 5 + 80 * 8)
    }

    func testEpleyOneRepMax() {
        // 100 × (1 + 5/30) = 116.666…
        XCTAssertEqual(WorkoutAnalytics.estimatedOneRepMax(weight: 100, reps: 5),
                       116.6667, accuracy: 0.001)
        // a single rep returns the bar weight
        XCTAssertEqual(WorkoutAnalytics.estimatedOneRepMax(weight: 140, reps: 1), 140)
    }

    func testBestSetByEstimated1RMIgnoresWarmups() {
        let sets = [set(1, 150, .warmup),   // would win on raw weight but is a warmup
                    set(5, 100, .working),  // 1RM ≈ 116.67
                    set(3, 110, .working)]  // 1RM = 121.0  ← best
        let best = WorkoutAnalytics.bestSet(in: sets)
        XCTAssertEqual(best?.weight, 110)
        XCTAssertEqual(best?.reps, 3)
    }

    func testStreakCountsHonoredScheduledDaysAndIgnoresRest() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        let day = { (offset: Int) in cal.date(byAdding: .day, value: offset, to: Date())! }
        // today + yesterday were scheduled & completed; 2-days-ago was a rest day;
        // 3-days-ago was scheduled & completed → streak should be 3 (rest is transparent).
        let plan: [Date: DayPlan] = [
            cal.startOfDay(for: day(0)):  .workout(UUID()),
            cal.startOfDay(for: day(-1)): .workout(UUID()),
            cal.startOfDay(for: day(-2)): .rest,
            cal.startOfDay(for: day(-3)): .workout(UUID())]
        let completedDays: Set<Date> = [
            cal.startOfDay(for: day(0)),
            cal.startOfDay(for: day(-1)),
            cal.startOfDay(for: day(-3))]
        XCTAssertEqual(
            WorkoutAnalytics.streak(plan: plan, completedDays: completedDays,
                                    asOf: day(0), calendar: cal), 3)
    }

    func testStreakBreaksOnMissedScheduledDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let day = { (offset: Int) in cal.date(byAdding: .day, value: offset, to: Date())! }
        let plan: [Date: DayPlan] = [
            cal.startOfDay(for: day(0)):  .workout(UUID()),
            cal.startOfDay(for: day(-1)): .workout(UUID())] // scheduled, NOT completed
        let completedDays: Set<Date> = [cal.startOfDay(for: day(0))]
        XCTAssertEqual(
            WorkoutAnalytics.streak(plan: plan, completedDays: completedDays,
                                    asOf: day(0), calendar: cal), 1)
    }

    func testStreakCountsDoneDaysUnconditionally() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let day = { (offset: Int) in cal.date(byAdding: .day, value: offset, to: Date())! }
        // Both days are `.done` (a session was logged) — they count even though
        // `completedDays` is empty, because `.done` already encodes completion.
        let plan: [Date: DayPlan] = [
            cal.startOfDay(for: day(0)):  .done(UUID()),
            cal.startOfDay(for: day(-1)): .done(UUID())]
        XCTAssertEqual(
            WorkoutAnalytics.streak(plan: plan, completedDays: [],
                                    asOf: day(0), calendar: cal), 2)
    }

    func testStreakStopsAtDayWithNoPlanEntry() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let day = { (offset: Int) in cal.date(byAdding: .day, value: offset, to: Date())! }
        // Today is done; yesterday has no plan entry → the walk stops at 1.
        let plan: [Date: DayPlan] = [cal.startOfDay(for: day(0)): .done(UUID())]
        XCTAssertEqual(
            WorkoutAnalytics.streak(plan: plan, completedDays: [],
                                    asOf: day(0), calendar: cal), 1)
        // Empty plan → no entry at `asOf` → 0.
        XCTAssertEqual(
            WorkoutAnalytics.streak(plan: [:], completedDays: [],
                                    asOf: day(0), calendar: cal), 0)
    }

    func testVolumeAndOneRepMaxEdgeCases() {
        // Zero reps and zero weight both yield zero volume.
        XCTAssertEqual(WorkoutAnalytics.setVolume(set(0, 50, .working)), 0)
        XCTAssertEqual(WorkoutAnalytics.setVolume(set(10, 0, .working)), 0)
        // 1RM: zero reps falls through the `reps > 1` guard and returns the weight;
        // bodyweight (zero weight) returns zero.
        XCTAssertEqual(WorkoutAnalytics.estimatedOneRepMax(weight: 100, reps: 0), 100)
        XCTAssertEqual(WorkoutAnalytics.estimatedOneRepMax(weight: 0, reps: 8), 0)
    }

    func testBestSetReturnsNilWhenNoCountingSets() {
        XCTAssertNil(WorkoutAnalytics.bestSet(in: []))
        XCTAssertNil(WorkoutAnalytics.bestSet(in: [set(5, 100, .warmup),
                                                   set(3, 110, .warmup)]))
    }

    func testBucketLabelIsFixedLocale() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        // 2026-01-05 is a Monday.
        let monday = DateComponents(calendar: cal, year: 2026, month: 1, day: 5).date!
        XCTAssertEqual(WorkoutAnalytics.bucketLabel(for: monday, range: .d7, calendar: cal), "Mon")
        XCTAssertEqual(WorkoutAnalytics.bucketLabel(for: monday, range: .year, calendar: cal), "Jan")
        XCTAssertTrue(WorkoutAnalytics.bucketLabel(for: monday, range: .m3, calendar: cal).hasPrefix("W"))
    }

    // BAK-23: the 3M axis numbers weeks relative to the range start (W1, W2, …)
    // and keeps counting across a year boundary instead of resetting on the
    // absolute calendar week-of-year (…W52, W1).
    func testBucketLabelM3NumbersWeeksRelativeToRangeStart() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
            DateComponents(calendar: cal, year: y, month: m, day: d).date!
        }
        let start = day(2025, 12, 8) // a Monday in December
        XCTAssertEqual(WorkoutAnalytics.bucketLabel(for: start, range: .m3,
                                                    rangeStart: start, calendar: cal), "W1")
        XCTAssertEqual(WorkoutAnalytics.bucketLabel(for: day(2025, 12, 15), range: .m3,
                                                    rangeStart: start, calendar: cal), "W2")
        // Across the year boundary it stays W5, not a reset to W1/W2.
        XCTAssertEqual(WorkoutAnalytics.bucketLabel(for: day(2026, 1, 5), range: .m3,
                                                    rangeStart: start, calendar: cal), "W5")
    }
}
