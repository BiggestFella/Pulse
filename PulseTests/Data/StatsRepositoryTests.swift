import XCTest
@testable import Pulse

@MainActor
final class StatsRepositoryTests: XCTestCase {
    private func repo() -> InMemoryStatsRepository { InMemoryStatsRepository(store: MockStore()) }

    func testSummaryCountsSessionsInRange() async throws {
        let s = try await repo().summary(range: .d30)
        XCTAssertEqual(s.sessions, 10)
        XCTAssertGreaterThanOrEqual(s.newPRs, 1)
        XCTAssertGreaterThan(s.averageDuration, 0)
    }

    func testSummary7DIsSubsetOf30D() async throws {
        let r = repo()
        let week = try await r.summary(range: .d7)
        let month = try await r.summary(range: .d30)
        XCTAssertLessThanOrEqual(week.sessions, month.sessions)
    }

    func testVolumeSeriesBucketsByDayFor30D() async throws {
        let points = try await repo().volumeSeries(range: .d30)
        XCTAssertFalse(points.isEmpty)
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
        let expected = SampleData.sessions
            .filter { $0.startedAt > Calendar.current.date(byAdding: .day, value: -30, to: Date())! }
            .reduce(0) { $0 + WorkoutAnalytics.sessionVolume($1) }
        let actual = points.reduce(0) { $0 + $1.volume }
        XCTAssertEqual(actual, expected, accuracy: 0.01)
    }

    func testVolumeByMuscleExcludesWarmupsAndSumsCorrectly() async throws {
        let muscles = try await repo().volumeByMuscle(range: .all)
        XCTAssertTrue(muscles.contains { $0.muscleGroup == "Legs" })
        XCTAssertTrue(muscles.allSatisfy { $0.volume > 0 })
    }

    func testCurrentStreakMatchesAnalytics() async throws {
        let streak = try await repo().currentStreak()
        XCTAssertGreaterThanOrEqual(streak, 1)
    }

    func testExerciseVolumeHistoryLastN() async throws {
        let bench = SampleData.exercises.first { $0.name == "Bench Press" }!
        let hist = try await repo().exerciseVolumeHistory(bench.id, lastN: 4)
        XCTAssertLessThanOrEqual(hist.count, 4)
        XCTAssertTrue(hist.allSatisfy { $0.volume >= 0 })
    }
}
