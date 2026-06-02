import XCTest
@testable import Pulse

@MainActor
final class PersonalRecordsModelTests: XCTestCase {
    private func model(_ store: MockStore) -> PersonalRecordsModel {
        PersonalRecordsModel(prRepo: InMemoryPRRepository(store: store),
                             exerciseRepo: InMemoryExerciseRepository(store: store))
    }

    func testLoadPopulatesRecords() async {
        let m = model(MockStore())
        await m.load()
        XCTAssertEqual(m.phase, .loaded)
        XCTAssertFalse(m.records.isEmpty)
        // names + muscle groups resolved from the catalog (not placeholders)
        XCTAssertFalse(m.records.contains { $0.exerciseName == "Exercise" })
        XCTAssertTrue(m.records.allSatisfy { !$0.muscleGroup.isEmpty })
    }

    func testRecordsSortedByEstimated1RMDescending() async {
        let m = model(MockStore())
        await m.load()
        let oneRMs = m.records.map(\.estimatedOneRepMax)
        XCTAssertEqual(oneRMs, oneRMs.sorted(by: >))
    }

    func testHeroIsHighestAndGridExcludesIt() async {
        let m = model(MockStore())
        await m.load()
        let hero = m.hero
        XCTAssertEqual(hero?.id, m.records.first?.id)
        XCTAssertFalse(m.gridRecords.contains { $0.id == hero?.id })
        XCTAssertEqual(m.gridRecords.count, m.filtered.count - 1)
    }

    func testSelectFiltersByMuscleAndAllClears() async {
        let m = model(MockStore())
        await m.load()
        let muscle = try? XCTUnwrap(m.muscleFilters.first)
        m.select(muscle)
        XCTAssertTrue(m.filtered.allSatisfy { $0.muscleGroup == muscle })
        m.select(nil)
        XCTAssertEqual(m.filtered.count, m.records.count)
    }

    func testFreshThisMonthCountMatchesFreshRecords() async {
        let m = model(MockStore())
        await m.load()
        XCTAssertEqual(m.freshThisMonthCount, m.records.filter(\.isFresh).count)
        XCTAssertEqual(m.trackedCount, m.records.count)
    }

    func testMuscleFiltersAreDistinct() async {
        let m = model(MockStore())
        await m.load()
        XCTAssertEqual(m.muscleFilters.count, Set(m.muscleFilters).count)
    }

    func testEmptyStoreYieldsEmptyPhase() async {
        let m = model(MockStore(seeded: false))
        await m.load()
        XCTAssertEqual(m.phase, .empty)
        XCTAssertNil(m.hero)
    }

    func testErrorThenRetryRecovers() async {
        let store = MockStore(); store.forceError = true
        let m = model(store)
        await m.load()
        XCTAssertEqual(m.phase, .error)
        store.forceError = false
        await m.retry()
        XCTAssertEqual(m.phase, .loaded)
    }
}
