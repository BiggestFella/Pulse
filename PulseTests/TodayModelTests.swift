import XCTest
@testable import Pulse

@MainActor
final class TodayModelTests: XCTestCase {
    // The model composes from the shared repositories now (BAK-24). On a training
    // day, SampleData's Monday workout (`Push`, 5 exercises) is today's card, and
    // the most-recent logged session (Push, 1 day ago) is the Yesterday recap.
    func testLoadComposesFromRepositories() async {
        let model = TodayTestSupport.model(now: TodayTestSupport.trainingDay())
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.loaded)
        XCTAssertEqual(model.greetingName, "Alex")          // "Alex Mason" → first name
        XCTAssertEqual(model.today?.name, "Push")
        XCTAssertEqual(model.today?.exerciseCount, 5)
        XCTAssertEqual(model.today?.programLabel, "PPL")
        XCTAssertEqual(model.week.count, 7)
        XCTAssertNotNil(model.yesterday)
        XCTAssertEqual(model.yesterday?.name, "Push")
        // Eyebrow is a fixed-locale "EEE · MMM d" token.
        XCTAssertTrue(model.dateEyebrow.range(of: #"^[A-Z]{3} · [A-Z]{3} \d{1,2}$"#,
                                              options: .regularExpression) != nil,
                      "Unexpected eyebrow: \(model.dateEyebrow)")
    }

    func testWeekCountsAreSelfConsistent() async {
        let model = TodayTestSupport.model(now: TodayTestSupport.trainingDay())
        await model.load()
        XCTAssertEqual(model.week.count, 7)
        XCTAssertLessThanOrEqual(model.doneCount, model.plannedCount)
        XCTAssertEqual(model.weekProgressLabel, "\(model.doneCount) OF \(model.plannedCount) DONE")
        XCTAssertEqual(model.streakLabel, "\(model.streak)D")
    }

    func testStreakLabelIsZeroDNotHidden() async {
        // Empty world → no schedule/sessions → zero streak, never hidden.
        let model = TodayTestSupport.model(store: MockStore(seeded: false),
                                           now: TodayTestSupport.trainingDay())
        await model.load()
        XCTAssertEqual(model.streakLabel, "0D")
    }

    func testRestDayLoadsEmptyPhase() async {
        let model = TodayTestSupport.model(now: TodayTestSupport.restDay())
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.empty)
        XCTAssertNil(model.today)
    }

    func testCompletedTodaySuppressesHeroCard() async {
        // Once today's session is logged the schedule reads `.done`; the hero must
        // not offer a startable card that contradicts the week strip (BAK-24 review).
        let store = MockStore()
        let now = TodayTestSupport.trainingDay()
        store.schedule[SampleData.calendar.startOfDay(for: now)] = .done(UUID())
        let model = TodayTestSupport.model(store: store, now: now)
        await model.load()
        XCTAssertNil(model.today, "Hero should be suppressed when today is already done")
        XCTAssertEqual(model.phase, TodayModel.Phase.empty)
    }

    func testNoHistoryHasNilYesterday() async {
        let store = MockStore()
        store.sessions = []                                  // no prior sessions
        let model = TodayTestSupport.model(store: store, now: TodayTestSupport.trainingDay())
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.loaded)
        XCTAssertNil(model.yesterday)
    }

    func testEmptyWorldWeekCountsZeroNoCrash() async {
        let model = TodayTestSupport.model(store: MockStore(seeded: false),
                                           now: TodayTestSupport.trainingDay())
        await model.load()
        XCTAssertEqual(model.week.count, 7)
        XCTAssertEqual(model.doneCount, 0)
        XCTAssertEqual(model.plannedCount, 0)
    }

    /// The real error-recovery path: the View's Retry button calls `load()` again
    /// on the SAME repositories. A transient failure should clear on the next load.
    func testRetryRecoversAfterTransientFailure() async {
        let store = MockStore()
        store.forceError = true
        let model = TodayTestSupport.model(store: store, now: TodayTestSupport.trainingDay())
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.error)
        store.forceError = false
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.loaded)
    }

    /// Two loads issued concurrently (initial load + pull-to-refresh) settle to a
    /// single consistent state without crashing — the in-flight guard cancels the
    /// superseded load rather than letting it clobber the winner.
    func testConcurrentLoadsSettleConsistently() async {
        let model = TodayTestSupport.model(now: TodayTestSupport.trainingDay())
        async let a: Void = model.load()
        async let b: Void = model.load()
        _ = await (a, b)
        XCTAssertEqual(model.phase, TodayModel.Phase.loaded)
        XCTAssertEqual(model.today?.name, "Push")
    }

    func testStartTodaysWorkoutInvokesCallbackOnceWithWorkoutID() async {
        var started: [UUID] = []
        let model = TodayTestSupport.model(now: TodayTestSupport.trainingDay(),
                                           onStartWorkout: { started.append($0) })
        await model.load()
        let expected = model.today?.workoutID
        XCTAssertNotNil(expected)
        model.startTodaysWorkout()
        XCTAssertEqual(started, [expected].compactMap { $0 })
    }

    func testStartTodaysWorkoutDoesNothingOnRestDay() async {
        var started: [UUID] = []
        let model = TodayTestSupport.model(now: TodayTestSupport.restDay(),
                                           onStartWorkout: { started.append($0) })
        await model.load()
        model.startTodaysWorkout()
        XCTAssertTrue(started.isEmpty)
    }

    func testOpenYesterdayPushesOnlyWhenRecapExists() async {
        var opened: [UUID] = []
        let model = TodayTestSupport.model(now: TodayTestSupport.trainingDay(),
                                           onOpenSession: { opened.append($0) })
        await model.load()
        model.openYesterday()
        XCTAssertEqual(opened.count, 1)

        let empty = MockStore(); empty.sessions = []
        let emptyModel = TodayTestSupport.model(store: empty, now: TodayTestSupport.trainingDay(),
                                                onOpenSession: { opened.append($0) })
        await emptyModel.load()
        emptyModel.openYesterday()
        XCTAssertEqual(opened.count, 1)   // unchanged
    }

    // BAK-36 — the deload banner appears under the heuristic and is dismissible.
    private func storeWithHardRecentSessions() -> MockStore {
        let store = MockStore()
        let exID = UUID()
        store.sessions = (0..<6).map { i in
            let start = Calendar.current.date(byAdding: .day, value: -i * 2, to: .now)!
            let set = SessionSet(exerciseID: exID, order: 0, reps: 5,
                                 weight: 100, type: .working, rir: 1)
            return WorkoutSession(workoutID: UUID(), startedAt: start, endedAt: start, sets: [set])
        }
        return store
    }

    func testDeloadBannerShowsThenDismisses() async {
        let model = TodayTestSupport.model(store: storeWithHardRecentSessions(),
                                           now: TodayTestSupport.trainingDay())
        await model.load()
        XCTAssertNotNil(model.deloadBanner)
        model.dismissDeload()
        XCTAssertNil(model.deloadBanner)
    }

    func testNoDeloadBannerWithoutQualifyingSessions() async {
        let store = MockStore(); store.sessions = []
        let model = TodayTestSupport.model(store: store, now: TodayTestSupport.trainingDay())
        await model.load()
        XCTAssertNil(model.deloadBanner)
    }
}
