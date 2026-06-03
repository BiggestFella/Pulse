import XCTest
@testable import Pulse

final class ProfileModelsTests: XCTestCase {
    func testUserSettingsDefaultsAreKgRest90AutoOnSoundOn() {
        let s = UserSettings.default
        XCTAssertEqual(s.units, .kg)
        XCTAssertEqual(s.defaultRestSeconds, 90)
        XCTAssertTrue(s.autoProgressWeight)
        XCTAssertTrue(s.soundOnRestEnd)
    }

    func testUnitsDisplayLabelIsKgMetric() {
        XCTAssertEqual(Units.kg.displayLabel, "KG · METRIC")
    }

    func testRestTimerDisplayLabelFormatsSeconds() {
        XCTAssertEqual(UserSettings.default.restTimerLabel, "90s")
    }

    func testProfileStatsEmptyIsAllZero() {
        let z = ProfileStats.empty
        XCTAssertEqual(z.streakDays, 0)
        XCTAssertEqual(z.totalSessions, 0)
        XCTAssertEqual(z.totalVolumeKg, 0)
        XCTAssertEqual(z.liftsTracked, 0)
        XCTAssertEqual(z.sessionsLogged, 0)
    }

    func testUserSettingsCodableRoundTrip() throws {
        let original = UserSettings(units: .kg, defaultRestSeconds: 120,
                                    autoProgressWeight: false, soundOnRestEnd: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testProfileFallbackInitialIsQuestionMarkWhenNameEmpty() {
        let p = UserProfile(displayName: "", memberSince: Date(), programLabel: "PPL")
        XCTAssertEqual(p.avatarInitial, "?")
    }

    func testProfileInitialIsFirstLetterUppercased() {
        let p = UserProfile(displayName: "alex mason", memberSince: Date(), programLabel: "PPL")
        XCTAssertEqual(p.avatarInitial, "A")
    }

    func testProfileSubtitleFormatsMonthYearAndProgram() {
        var comps = DateComponents()
        comps.year = 2024; comps.month = 2; comps.day = 1
        let date = Calendar.current.date(from: comps)!
        let p = UserProfile(displayName: "Alex Mason", memberSince: date, programLabel: "PPL")
        XCTAssertEqual(p.subtitle, "Member since Feb 2024 · PPL")
    }
}
