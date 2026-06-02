import XCTest
@testable import Pulse

@MainActor
final class StatsModelTests: XCTestCase {
    private func model(_ store: MockStore) -> StatsModel {
        StatsModel(repository: InMemoryStatsRepository(store: store))
    }

    func testInitialStateIsD30Loading() {
        let m = model(MockStore())
        XCTAssertEqual(m.selectedRange, .d30)
        XCTAssertEqual(m.phase, .loading)
    }

    func testLoadPopulatesLoaded() async {
        let m = model(MockStore())
        await m.load()
        XCTAssertEqual(m.phase, .loaded)
        XCTAssertEqual(m.sessions, 10)            // SampleData: 10 sessions within 30 days
        XCTAssertFalse(m.muscles.isEmpty)
        XCTAssertGreaterThan(m.totalVolume, 0)
        XCTAssertFalse(m.volumeDisplay.isEmpty)
    }

    func testSelectChangesRangeAndReloads() async {
        let m = model(MockStore())
        await m.load()
        await m.select(.d7)
        XCTAssertEqual(m.selectedRange, .d7)
        XCTAssertEqual(m.phase, .loaded)
    }

    func testMaxVolumeMuscleIsHighest() async {
        let m = model(MockStore())
        await m.load()
        let maxVol = m.muscles.map(\.volume).max()
        XCTAssertEqual(m.muscles.first { $0.id == m.maxVolumeMuscleID }?.volume, maxVol)
    }

    func testVolumeChartMaxHasFloor() async {
        let m = model(MockStore(seeded: false))
        await m.load()
        XCTAssertGreaterThanOrEqual(m.volumeChartMax, 1)   // floor — never collapses to 0
    }

    func testEmptyStoreYieldsEmptyPhase() async {
        let m = model(MockStore(seeded: false))
        await m.load()
        XCTAssertEqual(m.phase, .empty)
    }

    func testErrorThenRetryRecovers() async {
        let store = MockStore(); store.forceError = true
        let m = StatsModel(repository: InMemoryStatsRepository(store: store))
        await m.load()
        XCTAssertEqual(m.phase, .error)
        store.forceError = false
        await m.retry()
        XCTAssertEqual(m.phase, .loaded)
    }

    func testAbbreviate() {
        XCTAssertEqual(StatsModel.abbreviate(920), "920")
        XCTAssertEqual(StatsModel.abbreviate(184_000), "184K")
        XCTAssertEqual(StatsModel.abbreviate(1_200_000), "1.2M")
    }
}
