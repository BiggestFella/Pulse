import XCTest
@testable import Pulse

@MainActor
final class PendingSessionStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func session() -> WorkoutSession {
        WorkoutSession(workoutID: UUID(), startedAt: .now, endedAt: .now,
                       sets: [SessionSet(exerciseID: UUID(), order: 0, reps: 5, weight: 100, type: .working)])
    }

    func testEnqueuePersistsAndReloads() {
        let dir = tempDir()
        let store = PendingSessionStore(directory: dir)
        let s = session()
        store.enqueue(s)
        XCTAssertEqual(store.pendingCount, 1)
        // A new instance pointed at the same dir == app relaunch: it reloads.
        let reloaded = PendingSessionStore(directory: dir)
        XCTAssertEqual(reloaded.pendingCount, 1)
        XCTAssertEqual(reloaded.all().first?.id, s.id)
    }

    func testRemoveClearsAndPersists() {
        let dir = tempDir()
        let store = PendingSessionStore(directory: dir)
        let s = session(); store.enqueue(s)
        store.remove(id: s.id)
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(PendingSessionStore(directory: dir).isEmpty)
    }

    func testEnqueueReplacesByID() {
        let store = PendingSessionStore(directory: tempDir())
        let s = session()
        store.enqueue(s); store.enqueue(s)
        XCTAssertEqual(store.pendingCount, 1)   // same id replaces — no duplicates
    }

    func testRoundTripsSetData() {
        let dir = tempDir()
        let s = session()
        PendingSessionStore(directory: dir).enqueue(s)
        let reloaded = PendingSessionStore(directory: dir).all().first
        XCTAssertEqual(reloaded?.sets.first?.reps, 5)
        XCTAssertEqual(reloaded?.sets.first?.weight, 100)
    }
}
