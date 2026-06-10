import XCTest
@testable import Pulse

final class WidgetSnapshotStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    func testReadsBackWhatWasWritten() {
        let store = WidgetSnapshotStore(defaults: freshDefaults())
        store.write(.sample)
        XCTAssertEqual(store.read(), .sample)
    }

    func testFallsBackToSampleWhenAbsent() {
        let store = WidgetSnapshotStore(defaults: freshDefaults())
        XCTAssertEqual(store.read(), .sample)
    }

    func testFallsBackToSampleWhenCorrupt() {
        let store = WidgetSnapshotStore(defaults: freshDefaults())
        store.writeRaw(Data("not json".utf8))
        XCTAssertEqual(store.read(), .sample)
    }

    func testFallsBackWhenWeekNotSeven() {
        let store = WidgetSnapshotStore(defaults: freshDefaults())
        var bad = WidgetSnapshot.sample
        bad.week = Array(bad.week.prefix(5))   // corrupt: not 7 cells
        store.write(bad)
        XCTAssertEqual(store.read(), .sample)  // invalid → sample
    }
}
