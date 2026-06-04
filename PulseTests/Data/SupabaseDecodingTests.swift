import XCTest
@testable import Pulse

final class SupabaseDecodingTests: XCTestCase {
    struct Row: Codable, Equatable { let startedAt: Date; let userId: String }

    func testSnakeCaseAndTimestamptzDecode() throws {
        let json = #"{"started_at":"2026-06-04T08:00:00.123456+00:00","user_id":"abc"}"#.data(using: .utf8)!
        let row = try SupabaseDecoding.decoder.decode(Row.self, from: json)
        XCTAssertEqual(row.userId, "abc")
        XCTAssertEqual(row.startedAt.timeIntervalSince1970, 1780560000.123, accuracy: 0.5)
    }

    func testTimestamptzWithoutFractionalSeconds() throws {
        let json = #"{"started_at":"2026-06-04T08:00:00+00:00","user_id":"x"}"#.data(using: .utf8)!
        let row = try SupabaseDecoding.decoder.decode(Row.self, from: json)
        XCTAssertEqual(row.startedAt.timeIntervalSince1970, 1780560000, accuracy: 0.5)
    }
}
