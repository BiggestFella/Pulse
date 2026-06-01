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
}
