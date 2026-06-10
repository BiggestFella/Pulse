import XCTest
@testable import Pulse

@MainActor
final class BufferedSessionWriterTests: XCTestCase {
    private func session() -> WorkoutSession {
        WorkoutSession(workoutID: UUID(), startedAt: .now, endedAt: .now, sets: [])
    }
    private func makeStore() -> PendingSessionStore {
        PendingSessionStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString))
    }

    func testSuccessLeavesNothingBuffered() async throws {
        let inner = MockSessionWriter()
        let store = makeStore()
        let w = BufferedSessionWriter(wrapping: inner, store: store,
                                      monitor: MockConnectivityMonitor(isOnline: true))
        try await w.save(session())
        XCTAssertEqual(inner.saved.count, 1)
        XCTAssertTrue(store.isEmpty)          // persisted, then removed on success
    }

    func testFailureKeepsBufferedAndRethrows() async {
        let inner = MockSessionWriter(); inner.failAlways = URLError(.notConnectedToInternet)
        let store = makeStore()
        let w = BufferedSessionWriter(wrapping: inner, store: store,
                                      monitor: MockConnectivityMonitor(isOnline: false))
        do { try await w.save(session()); XCTFail("expected throw") }
        catch { /* expected */ }
        XCTAssertEqual(store.pendingCount, 1)  // not lost
    }

    func testFlushDrainsWhenWriterRecovers() async throws {
        let inner = MockSessionWriter(); inner.failAlways = URLError(.networkConnectionLost)
        let store = makeStore()
        let w = BufferedSessionWriter(wrapping: inner, store: store,
                                      monitor: MockConnectivityMonitor(isOnline: false))
        _ = try? await w.save(session())
        XCTAssertEqual(store.pendingCount, 1)
        inner.failAlways = nil                 // connectivity restored
        await w.flushPending()
        XCTAssertTrue(store.isEmpty)
        XCTAssertEqual(inner.saved.count, 1)
    }

    func testBecameReachableTriggersFlush() async throws {
        let inner = MockSessionWriter(); inner.failAlways = URLError(.notConnectedToInternet)
        let store = makeStore()
        let monitor = MockConnectivityMonitor(isOnline: false)
        let w = BufferedSessionWriter(wrapping: inner, store: store, monitor: monitor)
        _ = try? await w.save(session())
        XCTAssertEqual(store.pendingCount, 1)
        inner.failAlways = nil
        monitor.simulateOnline()               // fires onBecameReachable → flush Task
        // Let the detached flush Task run to completion.
        for _ in 0..<10 where !store.isEmpty { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(store.isEmpty)
        _ = w   // keep the writer alive for the duration of the test
    }
}
