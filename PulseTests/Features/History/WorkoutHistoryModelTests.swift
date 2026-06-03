import XCTest
@testable import Pulse

@MainActor
final class WorkoutHistoryModelTests: XCTestCase {
    private func model(_ store: MockStore) -> WorkoutHistoryModel {
        WorkoutHistoryModel(sessionRepo: InMemorySessionRepository(store: store),
                            workoutRepo: InMemoryWorkoutRepository(store: store),
                            programRepo: InMemoryProgramRepository(store: store))
    }

    func testLoadPopulatesSessionsMostRecentFirstAndLoadedPhase() async {
        let m = model(MockStore())
        await m.load()
        XCTAssertEqual(m.phase, .loaded)
        XCTAssertEqual(m.sessions.count, 10)
        // SampleData's freshest session is 1 day ago — first in the list.
        let dates = m.sessions.map(\.date)
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    func testVolumeLabelIsKilograms() async {
        let m = model(MockStore())
        await m.load()
        XCTAssertTrue(m.sessions.first?.volumeLabel.hasSuffix("KG") ?? false)
    }

    func testDefaultFilterIsAll() {
        let m = model(MockStore())
        XCTAssertEqual(m.selectedFilter, .all)
    }

    func testFilterPRShowsOnlyPRSessions() async {
        let m = model(MockStore())
        await m.load()
        m.select(.pr)
        let shown = m.filteredGroups.flatMap { $0.sessions }
        XCTAssertFalse(shown.isEmpty)
        XCTAssertTrue(shown.allSatisfy(\.hasPR))
    }

    func testFilterProgramAndOneOff() async {
        let m = model(MockStore())
        await m.load()
        // All SampleData sessions belong to the active program.
        m.select(.program)
        XCTAssertTrue(m.filteredGroups.flatMap { $0.sessions }.allSatisfy(\.isProgram))
        m.select(.oneOff)
        XCTAssertTrue(m.filteredGroups.flatMap { $0.sessions }.allSatisfy { !$0.isProgram })
    }

    func testSelectAllRestoresEverything() async {
        let m = model(MockStore())
        await m.load()
        m.select(.pr); m.select(.all)
        XCTAssertEqual(m.filteredGroups.flatMap { $0.sessions }.count, 10)
    }

    func testFilteredGroupsHaveRecencyLabels() async {
        let m = model(MockStore())
        await m.load()
        XCTAssertFalse(m.filteredGroups.isEmpty)
        // The most-recent session (1 day ago) lands in THIS WEEK.
        XCTAssertEqual(m.filteredGroups.first?.label, "THIS WEEK")
    }

    func testFilterWithNoMatchesIsEmptyAndProducesNoGroups() async {
        // A store whose only session is a one-off; .pr yields nothing for it.
        let store = MockStore(seeded: false)
        let oneOffWorkout = Workout(name: "Solo", weekday: nil, order: 0, exercises: [])
        store.programs = [Program(name: "Inactive", weeks: 1, isActive: false,
                                  workouts: [oneOffWorkout])]
        store.sessions = [WorkoutSession(workoutID: oneOffWorkout.id,
                                         startedAt: Date(), endedAt: Date(), sets: [])]
        let m = model(store)
        await m.load()
        m.select(.pr)
        XCTAssertTrue(m.isEmpty)
        XCTAssertTrue(m.filteredGroups.isEmpty)
    }

    func testEmptyRepoSetsEmptyPhase() async {
        let m = model(MockStore(seeded: false))
        await m.load()
        XCTAssertEqual(m.phase, .empty)
    }

    func testFailingRepoSetsErrorPhaseAndNoStaleData() async {
        let store = MockStore(); store.forceError = true
        let m = model(store)
        await m.load()
        XCTAssertEqual(m.phase, .error)
        XCTAssertTrue(m.sessions.isEmpty)
    }

    func testHeaderCountAndSinceLabel() async {
        let m = model(MockStore())
        await m.load()
        XCTAssertEqual(m.headerCount, 10)
        XCTAssertFalse(m.sinceLabel.isEmpty)
    }
}
