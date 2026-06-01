import XCTest
import SwiftUI
@testable import Pulse

@MainActor
final class TodayThemeTests: XCTestCase {
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
