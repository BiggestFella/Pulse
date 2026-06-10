import XCTest
@testable import Pulse

/// Fails the first `loadToday()` then succeeds — models a transient outage so we
/// can verify retry against the SAME repository (the production recovery path).
private final class FlakyRepository: TodayRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    func loadToday() async throws -> TodaySnapshot {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        if calls == 1 { throw MockTodayRepository.Failure.unavailable }
        return .sample
    }
}

@MainActor
final class TodayModelTests: XCTestCase {
    func testLoadPopulatesAllFields() async {
        let model = TodayModel(repository: MockTodayRepository.sample)
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.loaded)
        XCTAssertEqual(model.dateEyebrow, "WED · MAY 28")
        XCTAssertEqual(model.greetingName, "Alex")
        XCTAssertEqual(model.streak, 27)
        XCTAssertEqual(model.today?.name, "Chest & Tris")
        XCTAssertEqual(model.week.count, 7)
        XCTAssertEqual(model.yesterday?.name, "Legs")
    }

    func testCountsFromSampleWeek() async {
        let model = TodayModel(repository: MockTodayRepository.sample)
        await model.load()
        XCTAssertEqual(model.doneCount, 3)
        XCTAssertEqual(model.plannedCount, 5)
        XCTAssertEqual(model.weekProgressLabel, "3 OF 5 DONE")
        XCTAssertEqual(model.streakLabel, "27D")
    }

    func testStreakLabelIsZeroDNotHidden() async {
        let model = TodayModel(repository: MockTodayRepository.allRest)
        await model.load()
        XCTAssertEqual(model.streakLabel, "0D")
    }

    func testRestDayLoadsEmptyPhase() async {
        let model = TodayModel(repository: MockTodayRepository.restDay)
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.empty)
        XCTAssertNil(model.today)
    }

    func testNoHistoryHasNilYesterday() async {
        let model = TodayModel(repository: MockTodayRepository.noHistory)
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.loaded)
        XCTAssertNil(model.yesterday)
    }

    func testAllRestWeekCountsZeroNoCrash() async {
        let model = TodayModel(repository: MockTodayRepository.allRest)
        await model.load()
        XCTAssertEqual(model.doneCount, 0)
        XCTAssertEqual(model.plannedCount, 0)
    }

    /// The real error-recovery path: the View's Retry button calls `load()` again
    /// on the SAME repository. A transient failure should clear on the next load.
    func testRetryOnSameRepositoryRecoversAfterTransientFailure() async {
        let flaky = FlakyRepository()
        let model = TodayModel(repository: flaky)
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.error)
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.loaded)
    }

    /// Two loads issued concurrently (e.g. initial load + pull-to-refresh) settle
    /// to a single consistent state without crashing — the in-flight guard cancels
    /// the superseded load rather than letting it clobber the winner.
    func testConcurrentLoadsSettleConsistently() async {
        let model = TodayModel(repository: MockTodayRepository.sample)
        async let a: Void = model.load()
        async let b: Void = model.load()
        _ = await (a, b)
        XCTAssertEqual(model.phase, TodayModel.Phase.loaded)
        XCTAssertEqual(model.today?.name, "Chest & Tris")
    }

    func testStartTodaysWorkoutInvokesCallbackOnceWithWorkoutID() async {
        var started: [UUID] = []
        let model = TodayModel(repository: MockTodayRepository.sample,
                               onStartWorkout: { started.append($0) })
        await model.load()
        model.startTodaysWorkout()
        XCTAssertEqual(started, [TodaySnapshot.sampleWorkoutID])
    }

    func testStartTodaysWorkoutDoesNothingOnRestDay() async {
        var started: [UUID] = []
        let model = TodayModel(repository: MockTodayRepository.restDay,
                               onStartWorkout: { started.append($0) })
        await model.load()
        model.startTodaysWorkout()
        XCTAssertTrue(started.isEmpty)
    }

    func testOpenYesterdayPushesOnlyWhenRecapExists() async {
        var opened: [UUID] = []
        let model = TodayModel(repository: MockTodayRepository.sample,
                               onOpenSession: { opened.append($0) })
        await model.load()
        model.openYesterday()
        XCTAssertEqual(opened.count, 1)

        let empty = TodayModel(repository: MockTodayRepository.noHistory,
                               onOpenSession: { opened.append($0) })
        await empty.load()
        empty.openYesterday()
        XCTAssertEqual(opened.count, 1)   // unchanged
    }
}
