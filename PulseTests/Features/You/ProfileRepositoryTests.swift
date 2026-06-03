import XCTest
@testable import Pulse

final class ProfileRepositoryTests: XCTestCase {
    func testMockUserRepositoryReturnsSampleProfile() async throws {
        let profile = try await InMemoryUserRepository().currentProfile()
        XCTAssertEqual(profile.displayName, "Alex Mason")
        XCTAssertEqual(profile.programLabel, "PPL")
    }

    func testMockUserRepositoryReturnsSampleSummary() async throws {
        let stats = try await InMemoryUserRepository().profileSummary()
        XCTAssertEqual(stats.streakDays, 27)
        XCTAssertEqual(stats.totalSessions, 183)
        XCTAssertEqual(stats.totalVolumeKg, 2_100_000)
        XCTAssertEqual(stats.liftsTracked, 8)
        XCTAssertEqual(stats.sessionsLogged, 183)
    }

    func testMockSettingsRepositoryLoadReturnsDefaults() async throws {
        let s = try await InMemorySettingsRepository().load()
        XCTAssertEqual(s, .default)
    }

    func testMockSettingsRepositorySavePersistsForNextLoad() async throws {
        let repo = InMemorySettingsRepository()
        var s = try await repo.load()
        s.autoProgressWeight = false
        try await repo.save(s)
        let reloaded = try await repo.load()
        XCTAssertFalse(reloaded.autoProgressWeight)
    }

    func testFailingMocksThrow() async {
        await assertThrowsAsync(try await InMemoryUserRepository(shouldFail: true).currentProfile())
        await assertThrowsAsync(try await InMemoryUserRepository(shouldFail: true).profileSummary())
        await assertThrowsAsync(try await InMemorySettingsRepository(shouldFailLoad: true).load())
    }

    func testEmptyUserStatsAreZero() async throws {
        let stats = try await InMemoryUserRepository(variant: .emptyUser).profileSummary()
        XCTAssertEqual(stats, .empty)
    }
}

/// Local async throwing-assertion helper (uniquely named to avoid global collisions).
func assertThrowsAsync(_ expression: @autoclosure () async throws -> some Any,
                       file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) }
    catch { /* expected */ }
}
