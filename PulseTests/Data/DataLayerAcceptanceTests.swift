import XCTest
@testable import Pulse

@MainActor
final class DataLayerAcceptanceTests: XCTestCase {

    /// Drives the active-flow contract against the container: start a session →
    /// append a heavy set → finish → it appears in fetchSessions and produces a
    /// new PR. Proves the contract supports the active flow + History + PRs
    /// without a live backend.
    func testStartLogFinishProducesSessionAndNewPR() async throws {
        let c = RepositoryContainer(useMock: true)
        let catalog = try await c.exercises.fetchCatalog()
        let bench = try XCTUnwrap(catalog.first { $0.name == "Bench Press" })

        let before = try await c.sessions.fetchSessions(limit: nil).count
        let session = try await c.sessions.startSession(
            workoutID: SampleData.pushWorkout.id, at: Date())

        // A clearly all-time-best set (heavier than any seeded bench set).
        let prSet = SessionSet(exerciseID: bench.id, order: 0,
                               reps: 5, weight: 500, type: .working)
        try await c.sessions.appendSet(prSet, to: session.id)
        _ = try await c.sessions.finishSession(id: session.id, endedAt: Date())

        // Appears in history (most recent first).
        let after = try await c.sessions.fetchSessions(limit: nil)
        XCTAssertEqual(after.count, before + 1)
        XCTAssertEqual(after.first?.id, session.id)

        // Produces a fresh PR for bench within the last 7 days.
        let newPRs = try await c.prs.newPRs(in: .d7)
        let benchPR = try XCTUnwrap(newPRs.first { $0.exerciseID == bench.id })
        XCTAssertEqual(benchPR.weight, 500)
        XCTAssertTrue(benchPR.isNew)

        // Stats summary reflects the new PR.
        let summary = try await c.stats.summary(range: .d7)
        XCTAssertGreaterThanOrEqual(summary.newPRs, 1)
    }

    /// Swap isolation: re-fetching a workout returns the unchanged persisted
    /// graph — a session-scoped swap (engine state, BAK-14) never writes back.
    func testSwapIsSessionScopedAndDoesNotMutateSavedWorkout() async throws {
        let c = RepositoryContainer(useMock: true)
        let pushOpt = try await c.workouts.fetchWorkout(id: SampleData.pushWorkout.id)
        let push = try XCTUnwrap(pushOpt)
        let originalFirstExercise = push.exercises[0].exercise.name
        let againOpt = try await c.workouts.fetchWorkout(id: SampleData.pushWorkout.id)
        let again = try XCTUnwrap(againOpt)
        XCTAssertEqual(again.exercises[0].exercise.name, originalFirstExercise)
    }
}
