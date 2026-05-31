import Foundation

/// Raw, theme-able token values from the design handoff. Hex strings so they
/// are testable without a rendering context; `Theme` converts them to `Color`.
/// NOTE: `inkSoft`/`inkFaint` hold the *same* full `ink` hex on purpose — the
/// soft/faint variants are alpha-derived by `Theme` using `Palette.inkSoftOpacity`
/// / `inkFaintOpacity`. Keep the three ink slots identical.
struct PaletteTokens {
    let bg, surface, surface2: String
    let ink, inkSoft, inkFaint: String
    let accent, accentDeep, accent2, onAccent: String
}

enum Palette: String, CaseIterable {
    case coastal, mint

    static let `default`: Palette = .coastal

    /// Soft-ink alpha per palette (handoff: Coastal .62, Mint .64).
    var inkSoftOpacity: Double {
        switch self {
        case .coastal: return 0.62
        case .mint:    return 0.64
        }
    }

    /// Faint-ink alpha (both palettes .16 in the handoff).
    var inkFaintOpacity: Double { 0.16 }

    var tokens: PaletteTokens {
        switch self {
        case .coastal:
            return PaletteTokens(
                bg: "#06121F", surface: "#0E1F33", surface2: "#16314D",
                ink: "#FFF4D6", inkSoft: "#FFF4D6", inkFaint: "#FFF4D6",
                accent: "#26B6F6", accentDeep: "#0E5BA8",
                accent2: "#FF6A1F", onAccent: "#06121F")
        case .mint:
            return PaletteTokens(
                bg: "#0F1814", surface: "#1A2620", surface2: "#26332B",
                ink: "#E1F4E8", inkSoft: "#E1F4E8", inkFaint: "#E1F4E8",
                accent: "#00D9B8", accentDeep: "#007A6C",
                accent2: "#FFCC33", onAccent: "#0F1814")
        }
    }
}
