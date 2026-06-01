import XCTest
@testable import Pulse

final class MockTodayRepositoryTests: XCTestCase {
    func testSampleReturnsSevenDayWeek() async throws {
        let repo = MockTodayRepository.sample
        let snapshot = try await repo.loadToday()
        XCTAssertEqual(snapshot.week.count, 7)
        XCTAssertEqual(snapshot.greetingName, "Alex")
        XCTAssertEqual(snapshot.streak, 27)
        XCTAssertEqual(snapshot.dateEyebrow, "WED · MAY 28")
        XCTAssertEqual(snapshot.today?.name, "Chest & Tris")
        XCTAssertEqual(snapshot.yesterday?.name, "Legs")
    }

    func testSampleWeekHasThreeDoneFivePlanned() async throws {
        let snapshot = try await MockTodayRepository.sample.loadToday()
        let done = snapshot.week.filter { $0.state == .done }.count
        let planned = snapshot.week.filter { $0.state != .rest }.count
        XCTAssertEqual(done, 3)
        XCTAssertEqual(planned, 5)
    }

    func testRestDayVariantHasNoToday() async throws {
        let snapshot = try await MockTodayRepository.restDay.loadToday()
        XCTAssertNil(snapshot.today)
    }

    func testNoHistoryVariantHasNoYesterday() async throws {
        let snapshot = try await MockTodayRepository.noHistory.loadToday()
        XCTAssertNil(snapshot.yesterday)
    }

    func testFailingVariantThrows() async {
        do {
            _ = try await MockTodayRepository.failing.loadToday()
            XCTFail("expected loadToday to throw")
        } catch {
            // expected
        }
    }
}
