# Design System (fonts, button styles, theme switching) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Pulse design system on top of the foundation layer — vendor and register the three font families, expose a concrete typography API, build the signature `PressableButtonStyle` (primary / secondary / ghost, sizes sm/md/lg), the `Lockup` hero-numeral composition, a reusable bottom-sheet container, the `fadein` / `sheetup` transition modifiers, a DEBUG gallery host for previews and UI tests, and the user-facing You → Palette swatch picker — so that no feature ever hardcodes a color, spacing value, or font. (Linear: BAK-7.)

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`, feature-folder layout. The design system is a library of reusable views, `ButtonStyle`s, `ViewModifier`s, and a `Font`/`Text` API in `Pulse/Core/DesignSystem`, all consuming the `Theme` tokens injected at the app root via `.environment(Theme.self)`. Project generated from a checked-in `project.yml` via XcodeGen. The only stateful piece is theme selection (`Theme.palette`, persisted to `@AppStorage("pulse-pal")`); the `PaletteModel` is a thin `@Observable` proxy. No domain data, no repositories, no Supabase.

**Tech Stack:** Swift 5.9+, SwiftUI, XcodeGen, XCTest + XCUITest. Test destination: `platform=iOS Simulator,name=iPhone 17`.

**Prerequisites:** The Foundation layer (BAK, commit #1 / PR #1) must already be merged — it ships `Pulse/Core/DesignSystem/Theme.swift`, `Palette.swift`, the buildable 4-tab skeleton, the test targets, and CI. This feature has **no dependency on the Data layer (BAK-6)**: the design-system primitives carry no domain data, so nothing here binds to a repository protocol. (Every *consuming* feature will depend on both BAK-7 and BAK-6, but this plan does not.)

Verify the foundation before starting:

- [ ] **Step 0a: Confirm the project generates and the baseline builds**

Run:
```bash
cd /Users/leoncreed-baker/Documents/Cavehole/Pulse && xcodegen generate && \
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 0b: Confirm the existing design-system files are present**

Run: `ls Pulse/Core/DesignSystem`
Expected: `Palette.swift` and `Theme.swift` exist (this plan extends them and adds new files alongside).

- [ ] **Step 0c: Create the feature branch**

```bash
git checkout -b feature/BAK-7-design-system
```

---

## Task 1: Reconcile palette tokens and `Color(hex:)` (TDD)

The spec (edge case + tests) requires resolving the `inkSoft`/`inkFaint` storage: `Palette.swift` currently puts the **full `ink` hex** in the `inkSoft`/`inkFaint` slots and `Theme` derives the soft/faint variants via `.opacity(0.62)` / `.opacity(0.16)`. We keep that derivation as the single source of truth, correct Mint's soft opacity to `.64` (per the handoff: Coastal soft `.62`, Mint soft `.64`), and lock both the hex values and the `Color(hex:)` parser behaviour with tests.

**Files:**
- Modify: `Pulse/Core/DesignSystem/Theme.swift`
- Modify: `Pulse/Core/DesignSystem/Palette.swift`
- Create: `PulseTests/DesignSystem/ColorHexTests.swift`
- Create: `PulseTests/DesignSystem/PaletteTests.swift` (replaces the foundation's root-level `PulseTests/PaletteTests.swift` if present — delete the old one)
- Create: `PulseTests/DesignSystem/ThemeTests.swift`

- [ ] **Step 1: Write the failing `ColorHexTests`**

Create `PulseTests/DesignSystem/ColorHexTests.swift`:
```swift
import XCTest
import SwiftUI
@testable import Pulse

final class ColorHexTests: XCTestCase {
    /// Resolve a SwiftUI Color to sRGB components for assertion.
    private func rgba(_ color: Color) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    func testParsesHashRRGGBB() {
        let c = rgba(Color(hex: "#26B6F6"))
        XCTAssertEqual(c.r, 0x26 / 255, accuracy: 0.01)
        XCTAssertEqual(c.g, 0xB6 / 255, accuracy: 0.01)
        XCTAssertEqual(c.b, 0xF6 / 255, accuracy: 0.01)
        XCTAssertEqual(c.a, 1, accuracy: 0.01)
    }

    func testToleratesMissingHash() {
        let withHash = rgba(Color(hex: "#FFF4D6"))
        let without = rgba(Color(hex: "FFF4D6"))
        XCTAssertEqual(withHash.r, without.r, accuracy: 0.001)
        XCTAssertEqual(withHash.g, without.g, accuracy: 0.001)
        XCTAssertEqual(withHash.b, without.b, accuracy: 0.001)
    }

    func testMalformedReturnsClear() {
        let c = rgba(Color(hex: "zzz"))
        XCTAssertEqual(c.a, 0, accuracy: 0.01) // .clear → alpha 0
    }
}
```

- [ ] **Step 2: Run it — expect FAIL**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/ColorHexTests
```
Expected: FAIL — the new file isn't compiled yet / the test target can't find `ColorHexTests` until regenerated; once compiled the tests must pass against the *existing* `Color(hex:)`. (This step verifies the harness wiring and that the existing parser already satisfies the contract.)

> The existing `Color(hex:)` in `Theme.swift` already implements this behaviour. If the run is GREEN here, that is the expected end state for this helper — proceed. We assert it so a future refactor can't silently break it.

- [ ] **Step 3: Write the failing `PaletteTests`**

Create `PulseTests/DesignSystem/PaletteTests.swift`:
```swift
import XCTest
@testable import Pulse

final class PaletteTests: XCTestCase {
    func testAllCasesIsCoastalThenMint() {
        XCTAssertEqual(Palette.allCases, [.coastal, .mint])
    }

    func testDefaultIsCoastal() {
        XCTAssertEqual(Palette.default, .coastal)
    }

    func testRawValueRoundTrips() {
        XCTAssertEqual(Palette(rawValue: "coastal"), .coastal)
        XCTAssertEqual(Palette(rawValue: "mint"), .mint)
        XCTAssertNil(Palette(rawValue: "teal"))
    }

    func testCoastalTokenHexMatchesHandoff() {
        let t = Palette.coastal.tokens
        XCTAssertEqual(t.bg, "#06121F")
        XCTAssertEqual(t.surface, "#0E1F33")
        XCTAssertEqual(t.surface2, "#16314D")
        XCTAssertEqual(t.ink, "#FFF4D6")
        XCTAssertEqual(t.accent, "#26B6F6")
        XCTAssertEqual(t.accentDeep, "#0E5BA8")
        XCTAssertEqual(t.accent2, "#FF6A1F")
        XCTAssertEqual(t.onAccent, "#06121F")
    }

    func testMintTokenHexMatchesHandoff() {
        let t = Palette.mint.tokens
        XCTAssertEqual(t.bg, "#0F1814")
        XCTAssertEqual(t.surface, "#1A2620")
        XCTAssertEqual(t.surface2, "#26332B")
        XCTAssertEqual(t.ink, "#E1F4E8")
        XCTAssertEqual(t.accent, "#00D9B8")
        XCTAssertEqual(t.accentDeep, "#007A6C")
        XCTAssertEqual(t.accent2, "#FFCC33")
        XCTAssertEqual(t.onAccent, "#0F1814")
    }

    /// Soft-opacity differs per palette: Coastal .62, Mint .64 (handoff).
    func testInkSoftOpacityPerPalette() {
        XCTAssertEqual(Palette.coastal.inkSoftOpacity, 0.62, accuracy: 0.001)
        XCTAssertEqual(Palette.mint.inkSoftOpacity, 0.64, accuracy: 0.001)
    }
}
```

- [ ] **Step 4: Run it — expect FAIL**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/PaletteTests
```
Expected: FAIL — `Palette.inkSoftOpacity` does not exist.

- [ ] **Step 5: Add `inkSoftOpacity` to `Palette.swift`**

In `Pulse/Core/DesignSystem/Palette.swift`, add inside `enum Palette` (after `static let default`):
```swift
    /// Soft-ink alpha per palette (handoff: Coastal .62, Mint .64).
    var inkSoftOpacity: Double {
        switch self {
        case .coastal: return 0.62
        case .mint:    return 0.64
        }
    }

    /// Faint-ink alpha (both palettes .16 in the handoff).
    var inkFaintOpacity: Double { 0.16 }
```

Also update the doc comment on `PaletteTokens` so the `inkSoft`/`inkFaint` slots are no longer misleading. Replace the struct's leading comment and keep storing the full ink hex (Theme derives the alpha):
```swift
/// Raw, theme-able token values from the design handoff. Hex strings so they
/// are testable without a rendering context; `Theme` converts them to `Color`.
/// NOTE: `inkSoft`/`inkFaint` hold the *same* full `ink` hex on purpose — the
/// soft/faint variants are alpha-derived by `Theme` using `Palette.inkSoftOpacity`
/// / `inkFaintOpacity`. Keep the three ink slots identical.
struct PaletteTokens {
```

- [ ] **Step 6: Write the failing `ThemeTests`**

Create `PulseTests/DesignSystem/ThemeTests.swift`:
```swift
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
```

- [ ] **Step 7: Run it — expect FAIL**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/ThemeTests
```
Expected: FAIL — `testInkSoftAndFaintUsePerPaletteOpacity` for Mint fails (current code hardcodes `.opacity(0.62)`).

- [ ] **Step 8: Make `Theme` derive soft/faint opacity from the palette**

In `Pulse/Core/DesignSystem/Theme.swift`, replace the two hardcoded lines:
```swift
    var inkSoft: Color { Color(hex: t.ink).opacity(0.62) }
    var inkFaint: Color { Color(hex: t.ink).opacity(0.16) }
```
with:
```swift
    var inkSoft: Color { Color(hex: t.ink).opacity(palette.inkSoftOpacity) }
    var inkFaint: Color { Color(hex: t.ink).opacity(palette.inkFaintOpacity) }
```

Also add the sheet radius and small-chip radius the later tasks need. Extend the radii block:
```swift
    let radiusCard: CGFloat = 16
    let radiusPill: CGFloat = 999
    let radiusSheet: CGFloat = 26
    let radiusChip: CGFloat = 10
```

- [ ] **Step 9: Delete the stale foundation test if it exists, then run all DesignSystem tests — expect PASS**

```bash
[ -f PulseTests/PaletteTests.swift ] && git rm PulseTests/PaletteTests.swift || true
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/ColorHexTests \
  -only-testing:PulseTests/PaletteTests \
  -only-testing:PulseTests/ThemeTests
```
Expected: PASS — all three suites green.

- [ ] **Step 10: Commit**

```bash
git add Pulse/Core/DesignSystem/Theme.swift Pulse/Core/DesignSystem/Palette.swift PulseTests/DesignSystem
git commit -m "feat: reconcile palette ink-opacity tokens and lock token/parser tests"
```

---

## Task 2: Vendor and register the three font families

Per the product decisions doc: vendor the OFL-licensed Google fonts into `Pulse/Resources/Fonts/` and declare `UIAppFonts` in `project.yml`. No system fallback for the hero look — but Task 3 still ships a defensive condensed-system fallback for `heroNumeral` per AC4.

**Files:**
- Create: `Pulse/Resources/Fonts/HankenGrotesk-Regular.ttf`, `…-Medium.ttf`, `…-SemiBold.ttf`, `…-Bold.ttf`, `…-ExtraBold.ttf`, `…-Black.ttf`
- Create: `Pulse/Resources/Fonts/Oswald-Medium.ttf`, `Oswald-SemiBold.ttf`, `Oswald-Bold.ttf`
- Create: `Pulse/Resources/Fonts/GeistMono-Regular.ttf`, `GeistMono-Medium.ttf`, `GeistMono-SemiBold.ttf`
- Modify: `project.yml`

- [ ] **Step 1: Download the OFL font files into `Pulse/Resources/Fonts/`**

```bash
mkdir -p Pulse/Resources/Fonts
# Hanken Grotesk (Google Fonts, OFL)
curl -sL "https://github.com/google/fonts/raw/main/ofl/hankengrotesk/HankenGrotesk%5Bwght%5D.ttf" -o /tmp/HankenGrotesk-var.ttf
# Oswald (Google Fonts, OFL)
curl -sL "https://github.com/google/fonts/raw/main/ofl/oswald/Oswald%5Bwght%5D.ttf" -o /tmp/Oswald-var.ttf
# Geist Mono (OFL)
curl -sL "https://github.com/vercel/geist-font/raw/main/packages/next/dist/fonts/geist-mono/GeistMono-Regular.ttf" -o Pulse/Resources/Fonts/GeistMono-Regular.ttf
curl -sL "https://github.com/vercel/geist-font/raw/main/packages/next/dist/fonts/geist-mono/GeistMono-Medium.ttf"  -o Pulse/Resources/Fonts/GeistMono-Medium.ttf
curl -sL "https://github.com/vercel/geist-font/raw/main/packages/next/dist/fonts/geist-mono/GeistMono-SemiBold.ttf" -o Pulse/Resources/Fonts/GeistMono-SemiBold.ttf
ls -la Pulse/Resources/Fonts
```
Expected: the three Geist Mono static files plus the two variable-font downloads in `/tmp`.

> The Hanken Grotesk and Oswald Google Fonts files are **variable** (`[wght]`). iOS registers a variable font under a single PostScript name; you cannot address per-weight static names. Instantiate the static weights you need from the variable files so each weight has its own file and PostScript name. If `fonttools` is available:
> ```bash
> pip install --quiet fonttools
> for w in 400:Regular 500:Medium 600:SemiBold 700:Bold 800:ExtraBold 900:Black; do
>   wgt=${w%%:*}; nm=${w##*:}
>   fonttools varLib.instancer /tmp/HankenGrotesk-var.ttf wght=$wgt -o "Pulse/Resources/Fonts/HankenGrotesk-$nm.ttf"
> done
> for w in 500:Medium 600:SemiBold 700:Bold; do
>   wgt=${w%%:*}; nm=${w##*:}
>   fonttools varLib.instancer /tmp/Oswald-var.ttf wght=$wgt -o "Pulse/Resources/Fonts/Oswald-$nm.ttf"
> done
> ```
> If `fonttools` is unavailable, download the static `.ttf` weights from a Google Fonts static mirror instead. The goal is one static `.ttf` per weight listed in Files above.

- [ ] **Step 2: Record the real PostScript names (needed by `project.yml` and Task 3)**

```bash
for f in Pulse/Resources/Fonts/*.ttf; do
  echo "$f -> $(/usr/bin/python3 -c "from fontTools.ttLib import TTFont,TTLibError;
import sys
try:
  ps=[r.toUnicode() for r in TTFont('$f')['name'].names if r.nameID==6][0]
  print(ps)
except Exception as e:
  print('UNKNOWN')" 2>/dev/null)"
done
```
Expected: each file maps to a PostScript name like `HankenGrotesk-Bold`, `Oswald-Bold`, `GeistMono-Medium`. **Use these exact names in Task 3's `Font.custom(...)` calls.** If a name differs from the convention (e.g. `Oswald-Regular_Bold`), record the actual value and adjust Task 3 accordingly.

- [ ] **Step 3: Declare the fonts in `project.yml`**

Under `targets: Pulse: settings: base:` add `INFOPLIST_KEY_UIAppFonts` listing every file name. Edit `project.yml` so the `Pulse` target reads:
```yaml
  Pulse:
    type: application
    platform: iOS
    sources: [Pulse]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: au.com.codeheroes.pulse
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_UIAppFonts: >-
          HankenGrotesk-Regular.ttf HankenGrotesk-Medium.ttf
          HankenGrotesk-SemiBold.ttf HankenGrotesk-Bold.ttf
          HankenGrotesk-ExtraBold.ttf HankenGrotesk-Black.ttf
          Oswald-Medium.ttf Oswald-SemiBold.ttf Oswald-Bold.ttf
          GeistMono-Regular.ttf GeistMono-Medium.ttf GeistMono-SemiBold.ttf
```
> `INFOPLIST_KEY_UIAppFonts` (space-separated) lets XcodeGen keep generating the Info.plist (`GENERATE_INFOPLIST_FILE: YES`) while injecting the `UIAppFonts` array. The font files are already inside `sources: [Pulse]` (they live under `Pulse/Resources/Fonts`), so they are copied into the bundle automatically.

- [ ] **Step 4: Regenerate and build**

```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Resources/Fonts project.yml
git commit -m "chore: vendor Hanken Grotesk, Oswald, Geist Mono and declare UIAppFonts"
```

---

## Task 3: Typography API with font-fallback logic (TDD for resolution, preview for rendering)

Exposes the concrete styles from the spec: H1, Eyebrow, Row name, Row sub/unit, Stat numeral, Hero numeral. The only *logic* is font resolution with a condensed-system fallback when Oswald is unavailable (AC4) — that gets TDD. The styles themselves are validated by a preview and the gallery UI test (Task 8).

**Files:**
- Create: `Pulse/Core/DesignSystem/Typography.swift`
- Create: `PulseTests/DesignSystem/TypographyTests.swift`

- [ ] **Step 1: Write the failing `TypographyTests`**

Create `PulseTests/DesignSystem/TypographyTests.swift`:
```swift
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
```

- [ ] **Step 2: Run it — expect FAIL**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/TypographyTests
```
Expected: FAIL — `PulseFont` undefined.

- [ ] **Step 3: Write `Pulse/Core/DesignSystem/Typography.swift`**

```swift
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
```

- [ ] **Step 4: Run it — expect PASS**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/TypographyTests
```
Expected: PASS.

- [ ] **Step 5: Add a preview so the styles render visually**

Append to `Typography.swift`:
```swift
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
```

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/DesignSystem/Typography.swift PulseTests/DesignSystem/TypographyTests.swift
git commit -m "feat: typography API with Oswald hero fallback to condensed system"
```

---

## Task 4: `PressableButtonStyle` — primary / secondary / ghost, sizes sm/md/lg (TDD for config, preview for render)

The press-collapse animation and shadow stack are pure SwiftUI view assembly, but the **size/variant configuration table** (heights, font sizes, whether press-translate applies) is logic worth a unit test (AC7/AC8). We TDD a small `PulseButtonConfig` value type, then assemble the `ButtonStyle` around it and validate the visuals via preview + the gallery UI test.

**Files:**
- Create: `Pulse/Core/DesignSystem/PressableButtonStyle.swift`
- Create: `PulseTests/DesignSystem/PressableButtonStyleTests.swift`

- [ ] **Step 1: Write the failing `PressableButtonStyleTests`**

Create `PulseTests/DesignSystem/PressableButtonStyleTests.swift`:
```swift
import XCTest
@testable import Pulse

final class PressableButtonStyleTests: XCTestCase {
    func testSizeHeightsMatchSpec() {
        XCTAssertEqual(PulseButtonConfig.height(for: .sm), 42)
        XCTAssertEqual(PulseButtonConfig.height(for: .md), 52)
        XCTAssertEqual(PulseButtonConfig.height(for: .lg), 60)
    }

    func testSizeFontSizesMatchSpec() {
        XCTAssertEqual(PulseButtonConfig.fontSize(for: .sm), 14)
        XCTAssertEqual(PulseButtonConfig.fontSize(for: .md), 16)
        XCTAssertEqual(PulseButtonConfig.fontSize(for: .lg), 18)
    }

    func testOnlyPrimaryHasShadowAndPressTranslate() {
        XCTAssertTrue(PulseButtonConfig.hasShadow(.primary))
        XCTAssertFalse(PulseButtonConfig.hasShadow(.secondary))
        XCTAssertFalse(PulseButtonConfig.hasShadow(.ghost))

        XCTAssertTrue(PulseButtonConfig.pressTranslates(.primary))
        XCTAssertFalse(PulseButtonConfig.pressTranslates(.secondary))
        XCTAssertFalse(PulseButtonConfig.pressTranslates(.ghost))
    }

    func testRestShadowOffsetIsFiveAndPressedIsOne() {
        XCTAssertEqual(PulseButtonConfig.shadowY(pressed: false), 5)
        XCTAssertEqual(PulseButtonConfig.shadowY(pressed: true), 1)
    }

    func testDisabledOpacityIsPoint45() {
        XCTAssertEqual(PulseButtonConfig.disabledOpacity, 0.45, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run it — expect FAIL**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/PressableButtonStyleTests
```
Expected: FAIL — `PulseButtonConfig` undefined.

- [ ] **Step 3: Write `Pulse/Core/DesignSystem/PressableButtonStyle.swift`**

```swift
import SwiftUI

enum PulseButtonSize { case sm, md, lg }
enum PulseButtonVariant { case primary, secondary, ghost }

/// Pure configuration table for the button styles. Unit-tested so the spec's
/// size/variant rules can't drift.
enum PulseButtonConfig {
    static let disabledOpacity: Double = 0.45

    static func height(for size: PulseButtonSize) -> CGFloat {
        switch size { case .sm: 42; case .md: 52; case .lg: 60 }
    }
    static func fontSize(for size: PulseButtonSize) -> CGFloat {
        switch size { case .sm: 14; case .md: 16; case .lg: 18 }
    }
    static func hPadding(for size: PulseButtonSize) -> CGFloat {
        switch size { case .sm: 18; case .md: 24; case .lg: 30 }
    }
    static func hasShadow(_ v: PulseButtonVariant) -> Bool { v == .primary }
    static func pressTranslates(_ v: PulseButtonVariant) -> Bool { v == .primary }
    /// Hard zero-blur drop-shadow Y offset: rest 5 → pressed 1.
    static func shadowY(pressed: Bool) -> CGFloat { pressed ? 1 : 5 }
    /// Content offset on press for primary (matches the shadow collapse).
    static let pressContentOffset: CGFloat = 4
}

/// The signature pressable button. Apply with `.buttonStyle(PressableButtonStyle(...))`.
struct PressableButtonStyle: ButtonStyle {
    var variant: PulseButtonVariant = .primary
    var size: PulseButtonSize = .md
    @Environment(Theme.self) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let translate = PulseButtonConfig.pressTranslates(variant) && pressed
        let contentOffset = translate ? PulseButtonConfig.pressContentOffset : 0

        return label(configuration)
            .frame(height: PulseButtonConfig.height(for: size))
            .padding(.horizontal, PulseButtonConfig.hPadding(for: size))
            .background(background(pressed: pressed))
            .offset(y: contentOffset)
            .opacity(isEnabled ? 1 : PulseButtonConfig.disabledOpacity)
            .animation(.timingCurve(0.2, 0.7, 0.3, 1.4, duration: 0.1), value: pressed)
    }

    @ViewBuilder
    private func label(_ configuration: Configuration) -> some View {
        configuration.label
            .font(PulseFont.hanken("HankenGrotesk-Bold", size: PulseButtonConfig.fontSize(for: size)))
            .tracking(-0.005 * PulseButtonConfig.fontSize(for: size))
            .foregroundStyle(variant == .primary ? theme.onAccent : theme.ink)
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch variant {
        case .primary:
            ZStack {
                // Hard, zero-blur drop shadow capsule behind the fill.
                Capsule().fill(theme.ink)
                    .offset(y: (isEnabled ? PulseButtonConfig.shadowY(pressed: pressed) : 2))
                Capsule()
                    .fill(theme.accent)
                    .overlay(Capsule().stroke(theme.ink, lineWidth: 2))
                    // inner top highlight + bottom shade
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.28), lineWidth: 2)
                            .blur(radius: 0).mask(Capsule().fill(
                                LinearGradient(colors: [.white, .clear],
                                               startPoint: .top, endPoint: .center)))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.22), lineWidth: 3)
                            .mask(Capsule().fill(
                                LinearGradient(colors: [.clear, .black],
                                               startPoint: .center, endPoint: .bottom)))
                    )
            }
        case .secondary:
            Capsule().fill(Color.clear)
                .overlay(Capsule().stroke(theme.ink, lineWidth: 1.5))
        case .ghost:
            Color.clear
        }
    }
}

extension PressableButtonStyle {
    static var primary: PressableButtonStyle { .init(variant: .primary, size: .md) }
    static var secondary: PressableButtonStyle { .init(variant: .secondary, size: .md) }
    static var ghost: PressableButtonStyle { .init(variant: .ghost, size: .md) }
}

/// Plain glyph icon button (⋯, back ←): translates +1pt on press only.
struct IconButtonStyle: ButtonStyle {
    @Environment(Theme.self) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PulseFont.hanken("HankenGrotesk-Bold", size: 18))
            .foregroundStyle(theme.ink)
            .frame(width: 36, height: 36)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
```

> Ghost has no border/shadow/padding per AC7; the `.padding(.horizontal,...)` above still applies. Override for ghost by special-casing `hPadding` to `0` for `.ghost`: change `hPadding(for:)` usage in `makeBody` to `variant == .ghost ? 0 : PulseButtonConfig.hPadding(for: size)`.

Apply that ghost-padding fix now: in `makeBody`, replace
```swift
            .padding(.horizontal, PulseButtonConfig.hPadding(for: size))
```
with
```swift
            .padding(.horizontal, variant == .ghost ? 0 : PulseButtonConfig.hPadding(for: size))
```

- [ ] **Step 4: Run it — expect PASS**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/PressableButtonStyleTests
```
Expected: PASS.

- [ ] **Step 5: Add a preview covering every variant/size + disabled**

Append to `PressableButtonStyle.swift`:
```swift
#Preview("Buttons") {
    let theme = Theme()
    return VStack(spacing: 18) {
        Button("Start →") {}.buttonStyle(PressableButtonStyle(variant: .primary, size: .lg))
        Button("Log set →") {}.buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
        Button("Skip") {}.buttonStyle(PressableButtonStyle(variant: .primary, size: .sm))
        Button("Cancel") {}.buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
        Button("Clear") {}.buttonStyle(PressableButtonStyle(variant: .ghost, size: .md))
        Button("Disabled") {}.buttonStyle(PressableButtonStyle(variant: .primary, size: .md)).disabled(true)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.bg)
    .environment(theme)
}
```

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/DesignSystem/PressableButtonStyle.swift PulseTests/DesignSystem/PressableButtonStyleTests.swift
git commit -m "feat: PressableButtonStyle (primary/secondary/ghost, sm/md/lg) + IconButtonStyle"
```

---

## Task 5: `Lockup` hero-numeral composition (TDD for sizing logic, preview for render)

The two-column grid is view assembly, but AC9's two rules are logic: the sub-label size is derived as ~0.2× the numeral size, and the `failure` flag swaps the numeral text to `∞`. TDD those, assemble the grid, validate via preview + gallery UI test.

**Files:**
- Create: `Pulse/Core/DesignSystem/Lockup.swift`
- Create: `PulseTests/DesignSystem/LockupTests.swift`

- [ ] **Step 1: Write the failing `LockupTests`**

Create `PulseTests/DesignSystem/LockupTests.swift`:
```swift
import XCTest
@testable import Pulse

final class LockupTests: XCTestCase {
    func testSubLabelSizeIsOneFifthOfNumeral() {
        XCTAssertEqual(Lockup.subLabelSize(numeralSize: 120), 24, accuracy: 0.001)
        XCTAssertEqual(Lockup.subLabelSize(numeralSize: 100), 20, accuracy: 0.001)
    }

    func testNumeralTextIsValueNormally() {
        XCTAssertEqual(Lockup.numeralText(value: "7", failure: false), "7")
    }

    func testNumeralTextIsInfinityOnFailure() {
        XCTAssertEqual(Lockup.numeralText(value: "7", failure: true), "∞")
    }
}
```

- [ ] **Step 2: Run it — expect FAIL**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/LockupTests
```
Expected: FAIL — `Lockup` undefined.

- [ ] **Step 3: Write `Pulse/Core/DesignSystem/Lockup.swift`**

```swift
import SwiftUI

/// Two-column hero composition: a giant Oswald numeral (col 1, spans both rows),
/// a Geist Mono eyebrow + a bold Hanken sub-label (col 2). Used on accent cards,
/// so the numeral defaults to `onAccent`. Pass `failure: true` to render `∞`.
struct Lockup: View {
    let value: String          // the numeral, e.g. "7"
    var top: String = ""       // eyebrow (Geist Mono), defaults to accent2
    var bottom: String = ""    // sub-label (Hanken bold)
    var size: CGFloat = 116    // numeral point size
    var failure: Bool = false
    var numeralColor: Color? = nil   // defaults to onAccent
    var topColor: Color? = nil       // defaults to accent2
    var bottomColor: Color? = nil    // defaults to numeralColor

    @Environment(Theme.self) private var theme

    /// AC9: sub-label is ~0.2× the numeral size.
    static func subLabelSize(numeralSize: CGFloat) -> CGFloat { numeralSize * 0.2 }
    /// AC9: failure renders the numeral as ∞.
    static func numeralText(value: String, failure: Bool) -> String { failure ? "∞" : value }

    var body: some View {
        let numColor = numeralColor ?? theme.onAccent
        let subColor = bottomColor ?? numColor
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 0) {
            GridRow {
                Text(Lockup.numeralText(value: value, failure: failure))
                    .font(PulseFont.hero(size: size))
                    .tracking(-0.02 * size)
                    .foregroundStyle(numColor)
                    .lineLimit(1)
                    .fixedSize()
                    .gridCellAnchor(.topLeading)
                    .gridCellColumns(1)
                    // span both rows: place the col-2 stack alongside via a VStack cell
                VStack(alignment: .leading, spacing: 0) {
                    Text(top)
                        .pulseStyle(.eyebrow)
                        .foregroundStyle(topColor ?? theme.accent2)
                        .padding(.top, size * 0.08)
                    Text(bottom)
                        .font(PulseFont.hanken("HankenGrotesk-ExtraBold",
                                               size: Lockup.subLabelSize(numeralSize: size)))
                        .tracking(-0.02 * Lockup.subLabelSize(numeralSize: size))
                        .lineSpacing(-0.05 * Lockup.subLabelSize(numeralSize: size))
                        .foregroundStyle(subColor)
                }
            }
        }
    }
}
```

> The numeral `lineHeight .82` from the prototype maps to `.fixedSize()` + tight tracking; SwiftUI does not expose sub-1.0 line height directly. The poster look is preserved by the fixed size and the condensed face. The sub-label's negative top margin in CSS maps to the zero `verticalSpacing` + `lineSpacing` nudge.

- [ ] **Step 4: Run it — expect PASS**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/LockupTests
```
Expected: PASS.

- [ ] **Step 5: Add a preview (normal + failure, on an accent card)**

Append to `Lockup.swift`:
```swift
#Preview("Lockup") {
    let theme = Theme()
    return VStack(spacing: 24) {
        Lockup(value: "7", top: "DAY 23", bottom: "Chest & Tris.", size: 116)
            .padding(20)
            .background(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.ink, lineWidth: 2))
        Lockup(value: "0", top: "TO FAILURE", bottom: "Reps logged", size: 116, failure: true)
            .padding(20)
            .background(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.ink, lineWidth: 2))
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.bg)
    .environment(theme)
}
```

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/DesignSystem/Lockup.swift PulseTests/DesignSystem/LockupTests.swift
git commit -m "feat: Lockup hero-numeral composition with failure (∞) case"
```

---

## Task 6: Transitions — `fadein` and `sheetup` modifiers (view assembly + preview)

Pure view modifiers; no business logic. Provide the timing curves and `.fadeInOnMount(id:)` so a screen replays the fade+rise when its `.id` changes (AC11), plus the shared sheet-up animation used by Task 7.

**Files:**
- Create: `Pulse/Core/DesignSystem/Transitions.swift`

- [ ] **Step 1: Write `Pulse/Core/DesignSystem/Transitions.swift`**

```swift
import SwiftUI

/// Shared design-system motion. Timing curves match the prototype.
enum PulseMotion {
    /// Screen mount fade+rise: cubic-bezier(.2,.7,.3,1), .28s.
    static let fadeIn = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.28)
    /// Sheet slide-up: same curve, .25s.
    static let sheetUp = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.25)
}

/// AC11: opacity 0→1 + 6pt rise on mount; re-fires when `id` changes.
private struct FadeInOnMount<ID: Hashable>: ViewModifier {
    let id: ID
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear { withAnimation(PulseMotion.fadeIn) { shown = true } }
            .onChange(of: id) { _, _ in
                shown = false
                withAnimation(PulseMotion.fadeIn) { shown = true }
            }
    }
}

extension View {
    /// Fade+rise on mount, replaying whenever `id` changes (tab/overlay/phase).
    func fadeInOnMount<ID: Hashable>(id: ID) -> some View {
        modifier(FadeInOnMount(id: id))
    }
}
```

- [ ] **Step 2: Add a preview that re-fires on id change**

Append to `Transitions.swift`:
```swift
#Preview("FadeIn") {
    struct Demo: View {
        @State private var screen = 0
        let theme = Theme()
        var body: some View {
            VStack(spacing: 24) {
                Text("Screen \(screen)")
                    .pulseStyle(.h1)
                    .foregroundStyle(theme.ink)
                    .fadeInOnMount(id: screen)
                Button("Next") { screen += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
            .environment(theme)
        }
    }
    return Demo()
}
```

- [ ] **Step 3: Build (no test target change) and commit**

```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
git add Pulse/Core/DesignSystem/Transitions.swift
git commit -m "feat: fadein/sheetup motion + fadeInOnMount(id:) modifier"
```

---

## Task 7: Bottom-sheet container (view assembly + preview)

A reusable presentation modifier. Per the product-decisions doc, use native `.sheet` + `.presentationDetents` with custom styled content (26pt top radius, scrim, drag handle, eyebrow+title+✕ header) rather than a fully custom overlay; accept minor native-chrome differences for v1. The slide-up animation is the system sheet present; the scrim/handle/header are our content chrome.

**Files:**
- Create: `Pulse/Core/DesignSystem/BottomSheet.swift`

- [ ] **Step 1: Write `Pulse/Core/DesignSystem/BottomSheet.swift`**

```swift
import SwiftUI

/// Styled chrome for a bottom sheet's content: drag handle, eyebrow+title+✕
/// header, and a scrollable body. Wrap your sheet content in this.
struct SheetChrome<Content: View>: View {
    let eyebrow: String
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(theme.inkFaint)
                .frame(width: 42, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 8)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(eyebrow).pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
                    Text(title).pulseStyle(.h1).foregroundStyle(theme.ink)
                }
                Spacer()
                Button(action: onClose) { Text("✕") }
                    .buttonStyle(IconButtonStyle())
                    .accessibilityIdentifier("sheet-close")
            }
            .padding(.horizontal, 18)
            ScrollView {
                content().padding(.horizontal, 18).padding(.top, 6)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .overlay(alignment: .top) {
            // 2px ink border, no bottom edge; 26pt top corners.
            UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet,
                                   topTrailingRadius: theme.radiusSheet)
                .stroke(theme.ink, lineWidth: 2)
                .ignoresSafeArea(edges: .bottom)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet,
                                          topTrailingRadius: theme.radiusSheet))
    }
}

private struct PulseSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let eyebrow: String
    let title: String
    @ViewBuilder var sheetContent: () -> SheetContent
    @Environment(Theme.self) private var theme

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            SheetChrome(eyebrow: eyebrow, title: title,
                        onClose: { isPresented = false }) {
                sheetContent()
            }
            .environment(theme)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden) // we draw our own handle
            .presentationBackground(.clear)     // scrim/background is ours
            .accessibilityIdentifier("pulse-sheet")
        }
    }
}

extension View {
    /// Present a styled Pulse bottom sheet. Tapping outside (system scrim) or the
    /// ✕ dismisses it.
    func pulseSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        eyebrow: String,
        title: String,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(PulseSheetModifier(isPresented: isPresented,
                                    eyebrow: eyebrow, title: title,
                                    sheetContent: content))
    }
}
```

> AC10 asks for a `rgba(0,0,0,.55)` scrim and tap-to-dismiss. The native sheet supplies a system dimming scrim and tap-outside-to-dismiss; per the product decision we accept the native scrim rather than hand-rolling an overlay. The handle, header, ✕, border, and 26pt corners are our content chrome, which is what the acceptance UI test asserts.

- [ ] **Step 2: Add a preview host**

Append to `BottomSheet.swift`:
```swift
#Preview("BottomSheet") {
    struct Demo: View {
        @State private var open = false
        let theme = Theme()
        var body: some View {
            VStack {
                Button("Open sheet") { open = true }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
            .environment(theme)
            .pulseSheet(isPresented: $open, eyebrow: "EDIT", title: "Set editor.") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<6) { i in
                        Text("Set \(i + 1)").pulseStyle(.rowName).foregroundStyle(theme.ink)
                    }
                }
            }
        }
    }
    return Demo()
}
```

- [ ] **Step 3: Build and commit**

```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
git add Pulse/Core/DesignSystem/BottomSheet.swift
git commit -m "feat: reusable bottom-sheet chrome + pulseSheet presentation modifier"
```

---

## Task 8: DEBUG DesignSystem gallery host (view assembly, UI-test anchor)

A DEBUG-only screen that renders every primitive with stable accessibility identifiers so the XCUITests in Task 11 have something to drive. Reached via a launch argument so it never ships in a release flow.

**Files:**
- Create: `Pulse/Core/DesignSystem/DesignSystemGallery.swift`
- Modify: `Pulse/App/AppShell.swift`

- [ ] **Step 1: Write `Pulse/Core/DesignSystem/DesignSystemGallery.swift`**

```swift
import SwiftUI

#if DEBUG
/// DEBUG-only gallery used as the UI-test host for the design-system primitives.
/// Presented when the app launches with `-uiTestGallery` (see AppShell).
struct DesignSystemGallery: View {
    @Environment(Theme.self) private var theme
    @State private var sheetOpen = false
    @State private var fired = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("DESIGN SYSTEM").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)

                Lockup(value: "7", top: "DAY 23", bottom: "Chest & Tris.", size: 96)
                    .padding(18)
                    .background(theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.ink, lineWidth: 2))
                    .accessibilityIdentifier("gallery-lockup")

                Lockup(value: "0", top: "TO FAILURE", bottom: "Reps", size: 96, failure: true)
                    .accessibilityIdentifier("gallery-lockup-failure")

                Button("Start →") { fired += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .lg))
                    .accessibilityIdentifier("gallery-primary-lg")
                Button("Log set →") { fired += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
                    .accessibilityIdentifier("gallery-primary-md")
                Button("Skip") { fired += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .sm))
                    .accessibilityIdentifier("gallery-primary-sm")
                Button("Cancel") { fired += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
                    .accessibilityIdentifier("gallery-secondary")
                Button("Disabled") { fired += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
                    .disabled(true)
                    .accessibilityIdentifier("gallery-disabled")

                Text("Fired: \(fired)")
                    .pulseStyle(.rowSub).foregroundStyle(theme.inkSoft)
                    .accessibilityIdentifier("gallery-fired-count")

                Button("Open sheet") { sheetOpen = true }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
                    .accessibilityIdentifier("gallery-open-sheet")

                // Palette picker lives here too, so AC3/AC12 can be driven.
                PaletteView()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .fadeInOnMount(id: theme.palette)
        .pulseSheet(isPresented: $sheetOpen, eyebrow: "EDIT", title: "Set editor.") {
            Text("Sheet body").pulseStyle(.rowName).foregroundStyle(theme.ink)
                .accessibilityIdentifier("sheet-body")
        }
        .accessibilityIdentifier("design-system-gallery")
    }
}
#endif
```

> `PaletteView` is built in Task 9; this file references it, so commit Task 8 and Task 9 together (or build the gallery body without `PaletteView()` first and add it after Task 9). Simplest: do Task 9 first if the agent prefers strict compile-at-each-commit. The plan orders gallery before the picker for narrative flow; the build step below assumes Task 9 is in place — if not, temporarily comment out the `PaletteView()` line and the build will pass.

- [ ] **Step 2: Route to the gallery via a launch argument in `AppShell.swift`**

Replace the body of `Pulse/App/AppShell.swift`:
```swift
import SwiftUI

struct AppShell: View {
    @Environment(Theme.self) private var theme

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTestGallery") {
                DesignSystemGallery()
            } else {
                tabs
            }
            #else
            tabs
            #endif
        }
    }

    private var tabs: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "bolt.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            YouView()
                .tabItem { Label("You", systemImage: "person.fill") }
        }
    }
}

#Preview { AppShell().environment(Theme()) }
```

- [ ] **Step 3: Build (after Task 9) and commit**

```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
git add Pulse/Core/DesignSystem/DesignSystemGallery.swift Pulse/App/AppShell.swift
git commit -m "feat: DEBUG design-system gallery host gated by -uiTestGallery"
```

---

## Task 9: Palette picker — `PaletteModel` (TDD) + `PaletteView`

The model is logic (proxies `Theme.palette`, persists, no animation flag) → strict TDD. The swatch row is view assembly → preview + UI test. Per AC12 this ships only the Palette control, not the full You screen.

**Files:**
- Create: `Pulse/Features/You/PaletteModel.swift`
- Create: `Pulse/Features/You/PaletteView.swift`
- Create: `PulseTests/DesignSystem/PaletteModelTests.swift`

- [ ] **Step 1: Write the failing `PaletteModelTests`**

Create `PulseTests/DesignSystem/PaletteModelTests.swift`:
```swift
import XCTest
@testable import Pulse

final class PaletteModelTests: XCTestCase {
    private let key = "pulse-pal"
    override func setUp() { super.setUp(); UserDefaults.standard.removeObject(forKey: key) }
    override func tearDown() { UserDefaults.standard.removeObject(forKey: key); super.tearDown() }

    func testAvailableIsAllPalettes() {
        let model = PaletteModel(theme: Theme())
        XCTAssertEqual(model.available, [.coastal, .mint])
    }

    func testSelectedReflectsTheme() {
        let theme = Theme(); theme.palette = .mint
        let model = PaletteModel(theme: theme)
        XCTAssertEqual(model.selected, .mint)
    }

    func testSelectUpdatesThemeAndPersists() {
        let theme = Theme()
        let model = PaletteModel(theme: theme)
        model.select(.mint)
        XCTAssertEqual(theme.palette, .mint)
        XCTAssertEqual(model.selected, .mint)
        XCTAssertEqual(UserDefaults.standard.string(forKey: key), "mint")
    }

    func testSelectIsNotAnimated() {
        // AC3: palette change must NOT be wrapped in withAnimation.
        let model = PaletteModel(theme: Theme())
        XCTAssertFalse(model.animatesSelection)
    }
}
```

- [ ] **Step 2: Run it — expect FAIL**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/PaletteModelTests
```
Expected: FAIL — `PaletteModel` undefined.

- [ ] **Step 3: Write `Pulse/Features/You/PaletteModel.swift`**

```swift
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
```

- [ ] **Step 4: Run it — expect PASS**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/PaletteModelTests
```
Expected: PASS.

- [ ] **Step 5: Write `Pulse/Features/You/PaletteView.swift`**

```swift
import SwiftUI

/// You → Palette: a horizontal swatch row. Each swatch previews a palette's
/// accent / accent2 / surface; the active one wears a 2px accent2 ring. Tapping
/// re-skins the whole app instantly with NO background animation (AC3/AC12).
struct PaletteView: View {
    @Environment(Theme.self) private var theme
    private var model: PaletteModel { PaletteModel(theme: theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PALETTE").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
            HStack(spacing: 12) {
                ForEach(model.available, id: \.self) { palette in
                    swatch(palette)
                }
            }
        }
        .accessibilityIdentifier("palette-picker")
    }

    private func swatch(_ palette: Palette) -> some View {
        let isSelected = model.selected == palette
        let tokens = palette.tokens
        return Button {
            // No withAnimation — instant re-skin (AC3).
            model.select(palette)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: theme.radiusChip)
                    .fill(Color(hex: tokens.surface))
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: tokens.accent)).frame(width: 16, height: 16)
                    Circle().fill(Color(hex: tokens.accent2)).frame(width: 16, height: 16)
                }
            }
            .frame(width: 72, height: 48)
            .overlay(
                RoundedRectangle(cornerRadius: theme.radiusChip)
                    .stroke(isSelected ? theme.accent2 : theme.inkFaint,
                            lineWidth: isSelected ? 2 : 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("palette-swatch-\(palette.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview("Palette") {
    let theme = Theme()
    return PaletteView()
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
        .environment(theme)
}
```

- [ ] **Step 6: Surface the picker in `YouView` so it lives on its real tab**

Replace `Pulse/Features/You/YouView.swift`:
```swift
import SwiftUI

struct YouView: View {
    @Environment(Theme.self) private var theme
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PaletteView()
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.bg)
            .navigationTitle("You")
        }
    }
}

#Preview { YouView().environment(Theme()) }
```

- [ ] **Step 7: Build and run all unit tests — expect PASS**

```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests
```
Expected: PASS — every `PulseTests` suite green.

- [ ] **Step 8: Commit**

```bash
git add Pulse/Features/You PulseTests/DesignSystem/PaletteModelTests.swift
git commit -m "feat: PaletteModel + You → Palette swatch picker (instant re-skin)"
```

---

## Task 10: Inject `Theme` at the app root

`Theme` must be in the environment for every primitive that reads `@Environment(Theme.self)`. The foundation app root does not yet inject it.

**Files:**
- Modify: `Pulse/App/PulseApp.swift`

- [ ] **Step 1: Inject `Theme` and keep it alive at the root**

Replace `Pulse/App/PulseApp.swift`:
```swift
import SwiftUI

@main
struct PulseApp: App {
    @State private var theme = Theme()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(theme)
        }
    }
}
```

- [ ] **Step 2: Build and commit**

```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
git add Pulse/App/PulseApp.swift
git commit -m "feat: inject Theme into the SwiftUI environment at the app root"
```

---

## Task 11: Acceptance UI tests (XCUITest, mapped to acceptance criteria)

Drives the DEBUG gallery (launched with `-uiTestGallery`) and the You tab. Maps to AC1–3, AC5–12.

**Files:**
- Create: `PulseUITests/DesignSystemUITests.swift`

- [ ] **Step 1: Write `PulseUITests/DesignSystemUITests.swift`**

```swift
import XCTest

final class DesignSystemUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launchGallery() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestGallery"]
        app.launch()
        XCTAssertTrue(app.otherElements["design-system-gallery"].waitForExistence(timeout: 5))
        return app
    }

    // AC9: Lockup renders; failure variant exists.
    func testLockupAndFailureRender() {
        let app = launchGallery()
        XCTAssertTrue(app.otherElements["gallery-lockup"].exists)
        XCTAssertTrue(app.staticTexts["∞"].exists)
    }

    // AC5–7: primary buttons of each size exist and fire once.
    func testPrimaryButtonFiresOnce() {
        let app = launchGallery()
        XCTAssertTrue(app.buttons["gallery-primary-lg"].exists)
        XCTAssertTrue(app.buttons["gallery-primary-md"].exists)
        XCTAssertTrue(app.buttons["gallery-primary-sm"].exists)
        app.buttons["gallery-primary-md"].tap()
        XCTAssertTrue(app.staticTexts["Fired: 1"].waitForExistence(timeout: 2))
    }

    // AC8: disabled button does not fire.
    func testDisabledButtonDoesNotFire() {
        let app = launchGallery()
        let disabled = app.buttons["gallery-disabled"]
        XCTAssertTrue(disabled.exists)
        XCTAssertFalse(disabled.isEnabled)
    }

    // AC10: sheet presents, ✕ dismisses it.
    func testSheetPresentsAndCloseButtonDismisses() {
        let app = launchGallery()
        app.buttons["gallery-open-sheet"].tap()
        XCTAssertTrue(app.otherElements["pulse-sheet"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["sheet-body"].exists)
        app.buttons["sheet-close"].tap()
        XCTAssertFalse(app.staticTexts["sheet-body"].waitForExistence(timeout: 2))
    }

    // AC3/AC12: selecting Mint marks it selected; selecting Coastal reverts.
    func testPalettePickerSelectsAndReverts() {
        let app = launchGallery()
        let mint = app.buttons["palette-swatch-mint"]
        let coastal = app.buttons["palette-swatch-coastal"]
        XCTAssertTrue(mint.waitForExistence(timeout: 3))
        mint.tap()
        XCTAssertTrue(mint.isSelected)
        coastal.tap()
        XCTAssertTrue(coastal.isSelected)
    }

    // AC1–2: first launch defaults to Coastal; selection persists across relaunch.
    func testPalettePersistsAcrossRelaunch() {
        let app = launchGallery()
        XCTAssertTrue(app.buttons["palette-swatch-coastal"].isSelected) // AC1/AC2 default
        app.buttons["palette-swatch-mint"].tap()
        XCTAssertTrue(app.buttons["palette-swatch-mint"].isSelected)

        app.terminate()
        let relaunch = XCUIApplication()
        relaunch.launchArguments += ["-uiTestGallery"]
        relaunch.launch()
        XCTAssertTrue(relaunch.buttons["palette-swatch-mint"].waitForExistence(timeout: 5))
        XCTAssertTrue(relaunch.buttons["palette-swatch-mint"].isSelected)

        // Reset preference so other tests start from Coastal.
        relaunch.buttons["palette-swatch-coastal"].tap()
    }
}
```

> The relaunch test relies on `@AppStorage`/`UserDefaults` persisting between `launch()` calls in the same simulator, which it does. It resets to Coastal at the end so suite order doesn't leak Mint into the default-state assertion.

- [ ] **Step 2: Run the UI tests — expect PASS**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseUITests/DesignSystemUITests
```
Expected: PASS — all six UI tests green.

- [ ] **Step 3: Commit**

```bash
git add PulseUITests/DesignSystemUITests.swift
git commit -m "test: acceptance UI tests for design-system primitives and palette picker"
```

---

## Task 12: Full suite, push, and open the PR (⏸ outward action — confirm first)

- [ ] **Step 1: Run the complete build + test suite — expect PASS**

Run:
```bash
xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test
```
Expected: `** TEST SUCCEEDED **` — `ColorHexTests`, `PaletteTests`, `ThemeTests`, `TypographyTests`, `PressableButtonStyleTests`, `LockupTests`, `PaletteModelTests`, and `DesignSystemUITests` all green.

- [ ] **Step 2: Confirm with the user before pushing / opening the PR.**

- [ ] **Step 3: Push the branch and open the PR**

Run:
```bash
git push -u origin feature/BAK-7-design-system
gh pr create --fill --base main \
  --title "feat: design system (fonts, button styles, theme switching) [BAK-7]"
```
Use the PR template; link BAK-7 and the spec/plan docs. CI must be green before review.

- [ ] **Step 4: Request review**

Hand off to the `code-reviewer` agent and run `/security-review`, then the human PR gate per CLAUDE.md.

---

## Self-Review notes

- **Acceptance-criteria coverage:** AC1–2 (Task 10 root injection + Task 1 default/persistence tests + Task 11 relaunch test), AC3 (Task 9 `animatesSelection=false` + Task 11 picker test), AC4 (Task 3 hero fallback TDD), AC5–8 (Task 4 config TDD + Task 11 button/disabled tests), AC9 (Task 5 lockup TDD + Task 11), AC10 (Task 7 sheet + Task 11), AC11 (Task 6 `fadeInOnMount` + gallery uses it), AC12 (Task 9 + Task 11), AC13 (documented in token roles/comments; review-verified per spec).
- **Product decisions honored:** fonts vendored + `UIAppFonts` (Task 2), native `.sheet` + detents with custom chrome (Task 7), fixed poster hero sizes / no Dynamic Type on Oswald (`fixedSize:` in Task 3), grain deferred, kg-only / PR / streak rules not applicable to this view-layer feature.
- **TDD vs view-assembly split:** logic (palette opacity, font resolution, button config, lockup sizing, `PaletteModel`) is strict failing-test-first; pure SwiftUI assembly (`Lockup` grid, button chrome, sheet, transitions, gallery, picker view) is validated by `#Preview` + XCUITest. No placeholders; every step shows real code and exact commands.
- **No BAK-6 dependency:** confirmed — no repository protocols or mocks referenced; the only state is `Theme.palette`.
- **Mock-data/UI-first:** the feature carries no domain data; the gallery and picker render against static `Palette.allCases`.
