import XCTest
@testable import Pulse

@MainActor
final class SessionSetPersistenceTests: XCTestCase {
    private func makeRepo() -> (InMemorySessionRepository, MockStore) {
        let store = MockStore()
        store.sessions = []   // isolate from seeded sample sessions
        return (InMemorySessionRepository(store: store), store)
    }

    func testAppendedSetPreservesRIRThroughReadBack() async throws {
        let (repo, _) = makeRepo()
        let session = try await repo.startSession(workoutID: UUID(), at: .now)
        let exID = UUID()
        try await repo.appendSet(
            SessionSet(exerciseID: exID, order: 0, reps: 8, weight: 100,
                       type: .working, rir: 2),
            to: session.id)

        let read = try await repo.fetchSession(id: session.id)
        XCTAssertEqual(read?.sets.first?.rir, 2)
    }

    func testLegacyShapedSetReadsBackAsNilRIR() async throws {
        let (repo, _) = makeRepo()
        let session = try await repo.startSession(workoutID: UUID(), at: .now)
        // No `rir:` argument — the fast log path / legacy construction.
        try await repo.appendSet(
            SessionSet(exerciseID: UUID(), order: 0, reps: 10, weight: 80,
                       type: .working),
            to: session.id)

        let read = try await repo.fetchSession(id: session.id)
        XCTAssertNil(read?.sets.first?.rir)
    }
}
