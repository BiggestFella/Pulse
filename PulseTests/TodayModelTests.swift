import XCTest
@testable import Pulse

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

    func testFailureSetsErrorThenRecovers() async {
        let model = TodayModel(repository: MockTodayRepository.failing)
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.error)
        // Recover by swapping in a working repo and reloading.
        model.replaceRepository(MockTodayRepository.sample)
        await model.load()
        XCTAssertEqual(model.phase, TodayModel.Phase.loaded)
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
