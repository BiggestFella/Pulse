import XCTest
@testable import Pulse

final class AppConfigTests: XCTestCase {
    func testParsesValuesFromDictionary() throws {
        let cfg = try AppConfig(info: [
            "SUPABASE_URL": "https://x.supabase.co",
            "SUPABASE_ANON_KEY": "anon",
            "DEV_USER_EMAIL": "dev@pulse.app",
            "DEV_USER_PASSWORD": "pw",
        ])
        XCTAssertEqual(cfg.supabaseURL.absoluteString, "https://x.supabase.co")
        XCTAssertEqual(cfg.anonKey, "anon")
        XCTAssertEqual(cfg.devEmail, "dev@pulse.app")
        XCTAssertEqual(cfg.devPassword, "pw")
    }

    func testThrowsOnMissingKey() {
        XCTAssertThrowsError(try AppConfig(info: ["SUPABASE_URL": "https://x.supabase.co"]))
    }
}
