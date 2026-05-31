import SwiftUI

/// Thin @Observable proxy over `Theme.palette` for the You → Palette control.
/// No repository, no async, no loading/empty/error states — pure local preference.
@Observable
final class PaletteModel {
    private let theme: Theme
    /// AC3: palette switching is never wrapped in withAnimation (avoids a
    /// stale-color background flash). Documented constant, asserted in tests.
    let animatesSelection = false

    init(theme: Theme) { self.theme = theme }

    var available: [Palette] { Palette.allCases }
    var selected: Palette {
        get { theme.palette }
        set { theme.palette = newValue }
    }
    func select(_ palette: Palette) { theme.palette = palette }
}
