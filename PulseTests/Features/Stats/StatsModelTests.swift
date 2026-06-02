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
        XCTAssertEqual(StatsModel.abbreviate(999_950), "1.0M")   // boundary promotes to M
    }

    func testTrendDerivation() {
        XCTAssertNil(StatsModel.trend(forVolumes: []))
        XCTAssertNil(StatsModel.trend(forVolumes: [100]))         // too few points
        XCTAssertEqual(StatsModel.trend(forVolumes: [50, 50, 50, 50]), 0)   // flat
        XCTAssertEqual(StatsModel.trend(forVolumes: [100, 100, 150, 150]), 50) // +50%
        XCTAssertEqual(StatsModel.trend(forVolumes: [100, 100, 80, 80]), -20) // -20%
        XCTAssertNil(StatsModel.trend(forVolumes: [0, 0, 80, 80]))           // no baseline
    }
}
