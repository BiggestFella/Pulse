import XCTest
@testable import Pulse

final class WidgetSnapshotWriterTests: XCTestCase {
    private func makeStore() -> WidgetSnapshotStore {
        WidgetSnapshotStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    }

    func testMapsWorkoutDaySnapshotAndReloads() {
        var reloads = 0
        let store = makeStore()
        let writer = WidgetSnapshotWriter(store: store, reload: { reloads += 1 })
        writer.update(from: .sample, palette: .coastal)
        let s = store.read()
        XCTAssertEqual(s.todayWorkoutName, "Chest & Tris")
        XCTAssertEqual(s.exerciseCount, 7)
        XCTAssertEqual(s.programLabel, "PPL")
        XCTAssertEqual(s.dayLabel, "Day 23")
        XCTAssertEqual(s.streak, 27)
        XCTAssertEqual(s.week.count, 7)
        XCTAssertEqual(s.week.first, WeekCellSnapshot(dayLetter: "M", state: "done"))
        XCTAssertEqual(s.palette, "coastal")
        XCTAssertEqual(s.startRoute, WidgetDeepLink.startToday.url.absoluteString)
        XCTAssertEqual(reloads, 1)
    }

    func testMapsRestDaySnapshotToTodayRoute() {
        let store = makeStore()
        let writer = WidgetSnapshotWriter(store: store, reload: {})
        writer.update(from: .restDay, palette: .mint)
        let s = store.read()
        XCTAssertNil(s.todayWorkoutName)
        XCTAssertNil(s.exerciseCount)
        XCTAssertEqual(s.palette, "mint")
        XCTAssertEqual(s.startRoute, WidgetDeepLink.today.url.absoluteString)
    }

    func testRepaintSwapsPaletteKeepingData() {
        let store = makeStore()
        var reloads = 0
        let writer = WidgetSnapshotWriter(store: store, reload: { reloads += 1 })
        writer.update(from: .sample, palette: .coastal)
        writer.repaint(palette: .mint)
        let s = store.read()
        XCTAssertEqual(s.palette, "mint")
        XCTAssertEqual(s.todayWorkoutName, "Chest & Tris")   // data preserved
        XCTAssertEqual(reloads, 2)
    }
}
