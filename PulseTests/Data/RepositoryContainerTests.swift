import XCTest
@testable import Pulse

@MainActor
final class RepositoryContainerTests: XCTestCase {

    func testMockFlagSelectsInMemoryRepositories() {
        let c = RepositoryContainer(useMock: true)
        XCTAssertTrue(c.programs is InMemoryProgramRepository)
        XCTAssertTrue(c.sessions is InMemorySessionRepository)
        XCTAssertTrue(c.stats is InMemoryStatsRepository)
        XCTAssertTrue(c.prs is InMemoryPRRepository)
    }

    func testLiveFlagSelectsSupabaseRepositories() {
        let c = RepositoryContainer(useMock: false)
        XCTAssertTrue(c.programs is SupabaseProgramRepository)
        XCTAssertTrue(c.sessions is SupabaseSessionRepository)
    }

    func testMockReposShareOneStoreSoWritesAreVisibleAcrossRepos() async throws {
        let c = RepositoryContainer(useMock: true)
        let new = Workout(name: "Mobility", order: 99, exercises: [])
        _ = try await c.workouts.saveWorkout(new)
        let activeOpt = try await c.programs.activeProgram()
        let active = try XCTUnwrap(activeOpt)
        XCTAssertTrue(active.workouts.contains { $0.name == "Mobility" })
    }

    func testLaunchArgumentParsing() {
        XCTAssertTrue(RepositoryContainer.useMock(arguments: ["app", "-uiMock"]))
        XCTAssertFalse(RepositoryContainer.useMock(arguments: ["app"]))
    }
}
