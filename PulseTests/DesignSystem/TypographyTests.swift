import XCTest
import SwiftUI
@testable import Pulse

final class TypographyTests: XCTestCase {
    func testHeroFamilyResolvesToOswaldWhenRegistered() {
        // When the PostScript name is registered, we use it.
        let name = PulseFont.resolvedHeroFontName(isRegistered: { _ in true })
        XCTAssertEqual(name, .custom("Oswald-Bold"))
    }

    func testHeroFamilyFallsBackToCondensedSystemWhenMissing() {
        // When Oswald is NOT registered, fall back to the condensed system face.
        let name = PulseFont.resolvedHeroFontName(isRegistered: { _ in false })
        XCTAssertEqual(name, .systemCondensed)
    }

    func testBodyFamilyAlwaysUsesHanken() {
        XCTAssertEqual(PulseFont.bodyFontName, "HankenGrotesk-Bold")
    }
}
