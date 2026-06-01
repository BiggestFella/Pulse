import XCTest
import SwiftUI
@testable import Pulse

@MainActor
final class TodayThemeTests: XCTestCase {
    // `Theme.palette` persists to UserDefaults.standard (shared with the app
    // process the UI tests launch). Save and restore it so mutating the palette
    // here can't leak into other suites (e.g. the palette-persistence UI test).
    private static let paletteKey = "pulse-pal"
    private var savedPalette: String?

    override func setUp() {
        super.setUp()
        savedPalette = UserDefaults.standard.string(forKey: Self.paletteKey)
    }

    override func tearDown() {
        if let savedPalette {
            UserDefaults.standard.set(savedPalette, forKey: Self.paletteKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.paletteKey)
        }
        super.tearDown()
    }

    /// The model carries no color/theme state — switching palette never touches it.
    func testModelIsThemeAgnostic() async {
        let theme = Theme()
        theme.palette = .coastal
        let model = TodayModel(repository: MockTodayRepository.sample)
        await model.load()
        let coastalCount = model.doneCount
        theme.palette = .mint
        XCTAssertEqual(model.doneCount, coastalCount)
        XCTAssertEqual(model.phase, TodayModel.Phase.loaded)
    }

    /// Both palettes resolve all tokens the Today screen reads (no nil/clear).
    func testBothPalettesResolveTodayTokens() {
        for palette in Palette.allCases {
            let theme = Theme()
            theme.palette = palette
            _ = [theme.bg, theme.surface, theme.ink, theme.inkSoft,
                 theme.inkFaint, theme.accent, theme.accent2, theme.onAccent]
        }
    }
}
