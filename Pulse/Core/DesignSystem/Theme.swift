import SwiftUI

/// Resolves the active palette into SwiftUI `Color`s and exposes spacing/radii.
/// Inject via `.environment(Theme.self)`; never hardcode colors in views.
@Observable
final class Theme {
    var palette: Palette {
        didSet { UserDefaults.standard.set(palette.rawValue, forKey: Self.paletteDefaultsKey) }
    }
    /// UserDefaults key the active palette persists under. Internal so the Live
    /// Activity controller can snapshot the same value for the widget process.
    static let paletteDefaultsKey = "pulse-pal"

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.paletteDefaultsKey)
        self.palette = raw.flatMap(Palette.init(rawValue:)) ?? .default
    }

    private var t: PaletteTokens { palette.tokens }

    var bg: Color { Color(hex: t.bg) }
    var surface: Color { Color(hex: t.surface) }
    var surface2: Color { Color(hex: t.surface2) }
    var ink: Color { Color(hex: t.ink) }
    var inkSoft: Color { Color(hex: t.ink).opacity(palette.inkSoftOpacity) }
    var inkFaint: Color { Color(hex: t.ink).opacity(palette.inkFaintOpacity) }
    var accent: Color { Color(hex: t.accent) }
    var accentDeep: Color { Color(hex: t.accentDeep) }
    var accent2: Color { Color(hex: t.accent2) }
    var onAccent: Color { Color(hex: t.onAccent) }

    // Spacing rhythm and radii from the handoff.
    let spacing: [CGFloat] = [4, 8, 10, 12, 14, 18, 24]
    let radiusCard: CGFloat = 16
    let radiusPill: CGFloat = 999
    let radiusSheet: CGFloat = 26
    let radiusChip: CGFloat = 10
}

extension Color {
    /// "#RRGGBB" → Color. Falls back to clear on malformed input.
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        guard s.count == 6, Scanner(string: s).scanHexInt64(&v) else {
            self = .clear; return
        }
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
