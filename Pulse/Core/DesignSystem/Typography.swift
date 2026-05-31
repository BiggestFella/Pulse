import SwiftUI
import UIKit

/// Font resolution + concrete text styles for the Pulse design system.
/// Use `Text(...).pulseStyle(.heroNumeral)` etc.; never call `.font(.system(...))`
/// directly in feature code.
enum PulseFont {
    /// Where the hero numeral font resolves to.
    enum HeroFace: Equatable {
        case custom(String)     // a registered PostScript name (Oswald)
        case systemCondensed    // condensed system fallback (AC4)
    }

    static let bodyFontName = "HankenGrotesk-Bold"
    private static let oswaldBold = "Oswald-Bold"

    /// Pure resolver, injectable for tests. AC4: if Oswald is missing, fall back
    /// to a condensed system face so the condensed look is preserved.
    static func resolvedHeroFontName(
        isRegistered: (String) -> Bool = PulseFont.isFontRegistered
    ) -> HeroFace {
        isRegistered(oswaldBold) ? .custom(oswaldBold) : .systemCondensed
    }

    static func isFontRegistered(_ postScriptName: String) -> Bool {
        UIFont(name: postScriptName, size: 12) != nil
    }

    /// Build the hero numeral SwiftUI Font at a fixed poster size (no Dynamic
    /// Type scaling per product decision — `fixedSize: true`).
    static func hero(size: CGFloat) -> Font {
        switch resolvedHeroFontName() {
        case .custom(let name):
            return .custom(name, fixedSize: size)
        case .systemCondensed:
            return .system(size: size, weight: .bold).width(.condensed)
        }
    }

    static func oswald(_ name: String, size: CGFloat) -> Font {
        isFontRegistered(name)
            ? .custom(name, fixedSize: size)
            : .system(size: size, weight: .bold).width(.condensed)
    }

    static func hanken(_ name: String, size: CGFloat) -> Font {
        isFontRegistered(name) ? .custom(name, size: size) : .system(size: size, weight: .bold)
    }

    static func mono(_ name: String, size: CGFloat) -> Font {
        isFontRegistered(name) ? .custom(name, size: size) : .system(size: size, design: .monospaced)
    }
}

/// The concrete named styles from the spec.
enum PulseTextStyle {
    case h1            // Hanken 800, 30pt, tracking -.025em
    case eyebrow       // Geist Mono 500, 10pt, uppercase, tracking .16em
    case rowName       // Hanken 700, 14pt, tracking -.005em
    case rowSub        // Geist Mono 500, 10pt, uppercase, tracking .1em
    case statNumeral   // Oswald 700, 26pt, tracking -.01em
    case heroNumeral   // Oswald 700, 116pt, lineHeight .82
}

private struct PulseTextModifier: ViewModifier {
    let style: PulseTextStyle

    func body(content: Content) -> some View {
        switch style {
        case .h1:
            content.font(PulseFont.hanken("HankenGrotesk-ExtraBold", size: 30))
                .tracking(-0.025 * 30)
        case .eyebrow:
            content.font(PulseFont.mono("GeistMono-Medium", size: 10))
                .tracking(0.16 * 10).textCase(.uppercase)
        case .rowName:
            content.font(PulseFont.hanken("HankenGrotesk-Bold", size: 14))
                .tracking(-0.005 * 14)
        case .rowSub:
            content.font(PulseFont.mono("GeistMono-Medium", size: 10))
                .tracking(0.10 * 10).textCase(.uppercase)
        case .statNumeral:
            content.font(PulseFont.oswald("Oswald-Bold", size: 26))
                .tracking(-0.01 * 26)
        case .heroNumeral:
            content.font(PulseFont.hero(size: 116))
        }
    }
}

extension View {
    /// Apply a named Pulse text style. Color is the caller's responsibility
    /// (use Theme tokens — e.g. `.foregroundStyle(theme.inkSoft)` for eyebrows).
    func pulseStyle(_ style: PulseTextStyle) -> some View {
        modifier(PulseTextModifier(style: style))
    }
}

#Preview("Typography") {
    let theme = Theme()
    return VStack(alignment: .leading, spacing: 16) {
        Text("Hey, Alex.").pulseStyle(.h1).foregroundStyle(theme.ink)
        Text("WED · MAY 28").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
        Text("Incline DB Press").pulseStyle(.rowName).foregroundStyle(theme.ink)
        Text("3 SETS · 12 REPS").pulseStyle(.rowSub).foregroundStyle(theme.inkSoft)
        Text("1240").pulseStyle(.statNumeral).foregroundStyle(theme.accent)
        Text("7").pulseStyle(.heroNumeral).foregroundStyle(theme.accent)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.bg)
    .environment(theme)
}
