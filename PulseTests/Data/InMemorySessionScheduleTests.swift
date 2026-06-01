import XCTest
@testable import Pulse

@MainActor
final class InMemorySessionScheduleTests: XCTestCase {

    func testStartAppendFinishRoundTrip() async throws {
        let store = MockStore()
        let repo = InMemorySessionRepository(store: store)
        let started = try await repo.startSession(workoutID: SampleData.pushWorkout.id, at: Date())
        XCTAssertNil(started.endedAt)
        let set = SessionSet(exerciseID: SampleData.exercises[0].id, order: 0,
                             reps: 5, weight: 100, type: .working)
        try await repo.appendSet(set, to: started.id)
        let midOpt = try await repo.fetchSession(id: started.id)
        let mid = try XCTUnwrap(midOpt)
        XCTAssertEqual(mid.sets.count, 1)
        let ended = try await repo.finishSession(id: started.id, endedAt: Date())
        XCTAssertNotNil(ended.endedAt)
    }

    func testFetchSessionsLimitAndOrdering() async throws {
        let repo = InMemorySessionRepository(store: MockStore())
        let two = try await repo.fetchSessions(limit: 2)
        XCTAssertEqual(two.count, 2)
        XCTAssertGreaterThan(two[0].startedAt, two[1].startedAt)
    }

    func testSessionSetsGroupByExercise() async throws {
        let repo = InMemorySessionRepository(store: MockStore())
        let recent = try await repo.fetchSessions(limit: 1)
        let grouped = Dictionary(grouping: recent[0].sets, by: \.exerciseID)
        XCTAssertGreaterThan(grouped.count, 1)
    }

    func testLastSessionsForExercise() async throws {
        let repo = InMemorySessionRepository(store: MockStore())
        let bench = SampleData.exercises.first { $0.name == "Bench Press" }!
        let last = try await repo.lastSessions(forExercise: bench.id, limit: 4)
        XCTAssertTrue(last.allSatisfy { $0.sets.contains { $0.exerciseID == bench.id } })
        XCTAssertLessThanOrEqual(last.count, 4)
    }

    func testSetPlanThenPlanReflectsAndClearRemoves() async throws {
        let store = MockStore()
        let repo = InMemoryScheduleRepository(store: store)
        let day = SampleData.calendar.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 40, to: Date())!)
        try await repo.setPlan(.workout(SampleData.pushWorkout.id), on: day)
        let planAfterSet = try await repo.plan(for: day)
        XCTAssertEqual(planAfterSet, .workout(SampleData.pushWorkout.id))
        try await repo.setPlan(nil, on: day)
        let cleared = try await repo.plan(for: day)
        XCTAssertNil(cleared)
    }

    func testUpcomingReturnsForwardWindow() async throws {
        let repo = InMemoryScheduleRepository(store: MockStore())
        let from = SampleData.calendar.startOfDay(for: Date())
        let up = try await repo.upcoming(from: from, days: 7)
        XCTAssertTrue(up.allSatisfy { $0.date >= from })
        XCTAssertTrue(up.map(\.date) == up.map(\.date).sorted())
    }

    func testForcedErrorThrows() async throws {
        let store = MockStore(); store.forceError = true
        let repo = InMemorySessionRepository(store: store)
        do { _ = try await repo.fetchSessions(limit: nil); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? RepositoryError, .forced) }
    }

    func testEmptyStoreReturnsEmptyNotError() async throws {
        let repo = InMemorySessionRepository(store: MockStore(seeded: false))
        let sessions = try await repo.fetchSessions(limit: nil)
        XCTAssertEqual(sessions, [])
    }

    func testInjectedLatencyIsObserved() async throws {
        let store = MockStore(); store.latency = .milliseconds(50)
        let repo = InMemorySessionRepository(store: store)
        let t0 = ContinuousClock.now
        _ = try await repo.fetchSessions(limit: 1)
        XCTAssertGreaterThanOrEqual((ContinuousClock.now - t0), .milliseconds(45))
    }
}
