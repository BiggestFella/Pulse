import SwiftUI

extension Theme {
    /// Fixed brand swatch for a folder. Intentionally palette-independent — the
    /// six folder colors are a brand set, not a re-skinnable token, so they stay
    /// constant across Coastal/Mint (views read this token instead of a raw hex).
    ///
    /// Lives in the Builders feature (not in `Theme.swift`) on purpose: the
    /// PulseWidgets extension compiles the shared `Theme.swift` but NOT
    /// `Features/Builders`, so keeping the `FolderColor` reference out of the
    /// shared file is what lets the widget target build.
    func folderColor(_ token: FolderColor) -> Color { Color(hex: token.hex) }
}
