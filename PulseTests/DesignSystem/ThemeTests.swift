import XCTest
import SwiftUI
@testable import Pulse

final class ThemeTests: XCTestCase {
    private let key = "pulse-pal"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: key)
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    private func rgba(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    func testDefaultsToCoastalWithNoStoredValue() {
        let theme = Theme()
        XCTAssertEqual(theme.palette, .coastal)
    }

    func testUnknownStoredValueFallsBackToCoastal() {
        UserDefaults.standard.set("teal", forKey: key)
        let theme = Theme()
        XCTAssertEqual(theme.palette, .coastal)
    }

    func testSettingPalettePersists() {
        let theme = Theme()
        theme.palette = .mint
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "mint")
    }

    func testAccentTokenResolvesPerPalette() {
        let theme = Theme()
        theme.palette = .coastal
        let coastal = rgba(theme.accent)
        XCTAssertEqual(coastal.r, 0x26 / 255, accuracy: 0.01)

        theme.palette = .mint
        let mint = rgba(theme.accent)
        XCTAssertEqual(mint.g, 0xD9 / 255, accuracy: 0.01) // #00D9B8
    }

    func testInkSoftAndFaintUsePerPaletteOpacity() {
        let theme = Theme()
        theme.palette = .coastal
        XCTAssertEqual(rgba(theme.inkSoft).a, 0.62, accuracy: 0.01)
        XCTAssertEqual(rgba(theme.inkFaint).a, 0.16, accuracy: 0.01)

        theme.palette = .mint
        XCTAssertEqual(rgba(theme.inkSoft).a, 0.64, accuracy: 0.01)
    }
}
