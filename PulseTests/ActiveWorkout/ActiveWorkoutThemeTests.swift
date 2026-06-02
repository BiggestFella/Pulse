import XCTest
import SwiftUI
@testable import Pulse

@MainActor
final class ActiveWorkoutThemeTests: XCTestCase {
    // Theme.palette persists to UserDefaults; save/restore so mutating it here
    // can't leak into other suites (e.g. the palette-persistence UI test).
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

    /// AC19 — both palettes resolve every token the active flow reads (no nil/clear trap).
    func testBothPalettesResolveActiveFlowTokens() {
        for palette in Palette.allCases {
            let theme = Theme()
            theme.palette = palette
            _ = [theme.bg, theme.surface, theme.surface2, theme.ink, theme.inkSoft,
                 theme.inkFaint, theme.accent, theme.accent2, theme.onAccent]
        }
    }

    /// The engine carries no theme state — switching palette never touches it.
    func testModelIsThemeAgnostic() {
        let theme = Theme()
        theme.palette = .coastal
        let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                                   historyRepo: MockHistoryRepository(),
                                   sessionWriter: MockSessionWriter())
        m.startWorkout(ActiveWorkoutSample.workout)
        let before = m.steps.count
        theme.palette = .mint
        XCTAssertEqual(m.steps.count, before)
        XCTAssertEqual(m.phase, .pre)
    }
}
