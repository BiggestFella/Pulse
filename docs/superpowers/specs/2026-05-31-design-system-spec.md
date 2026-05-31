# Design System (fonts, button styles, theme switching) — Spec

**Linear:** BAK-7  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview
The Design System is the shared visual foundation every Pulse screen builds on: the two color themes (Coastal / Mint), the three font families with their concrete text styles, the signature chunky hard-shadow pressable button, the hero "lockup" numeral composition, the bottom-sheet container, and the standard screen / sheet transitions. It exists so that no feature ever hardcodes a color, spacing value, or font — they consume `Theme` tokens and a small set of reusable views, styles, and modifiers. The foundation layer (commit #1) already ships `Theme.swift` and `Palette.swift` with the ten tokens and an `@AppStorage`-backed palette; this feature completes the system (typography, button styles, lockup, sheet/transition primitives) and adds the user-facing Palette picker placeholder so themes can actually be switched in-app.

## User story
As a lifter, I want the app to look and feel like one cohesive, tactile product — bold condensed numerals, satisfying buttons that physically depress, and a theme I can switch between — so that the experience feels premium and consistent on every screen.

## Acceptance criteria
1. A `Theme` resolving all ten semantic tokens (`bg`, `surface`, `surface2`, `ink`, `inkSoft`, `inkFaint`, `accent`, `accentDeep`, `accent2`, `onAccent`) for both Coastal and Mint is injected into the SwiftUI environment at the app root, and reading a token in a view returns the value for the active palette.
2. Coastal is the default palette on first launch (no stored preference). The chosen palette persists across launches via `@AppStorage("pulse-pal")` with raw values `"coastal"` / `"mint"`.
3. Switching the palette re-skins the entire UI to the other theme's ten tokens simultaneously, with **no implicit animation on the screen background** (the palette change is not wrapped in `withAnimation`), avoiding a stale-color flash.
4. The three font families (Hanken Grotesk, Oswald, Geist Mono) are registered and available; a typography API exposes the concrete styles — H1, Eyebrow, Row name, Row sub / unit, Stat numeral, Hero numeral — at the specified sizes, weights, and tracking. If Oswald fails to load, hero numerals fall back to a condensed system equivalent (the condensed look is preserved).
5. The primary `PressableButtonStyle` renders a Capsule with a `2px solid ink` stroke, `accent` fill, `onAccent` text, a top inner highlight + bottom inner shade, and a hard (zero-blur) `0 5px 0 ink` drop shadow at rest.
6. On press, the primary button's content offsets down ~4pt and the hard shadow collapses from y:5 → y:1, animated over ~0.1s with a slight overshoot (timing curve ≈ cubic-bezier(.2,.7,.3,1.4)); on release it returns to rest.
7. The button style supports three sizes — `sm` (42pt tall, 14pt), `md` (52pt, 16pt), `lg` (60pt, 18pt) — and three variants — `primary` (filled, shadow), `secondary` (transparent, `ink` text, `1.5px ink` stroke, no shadow, no press translate), `ghost` (transparent, `ink` text, no border / shadow / padding).
8. A disabled primary button renders at ~0.45 opacity with no press translate and a faint shadow, and does not invoke its action.
9. A `Lockup` view renders a two-column composition: a giant Oswald numeral in column one spanning both rows; a Geist Mono eyebrow (`accent2`) and a bold Hanken sub-label (sized relative to the numeral, ~0.2×) in column two. Default numeral color is `onAccent` on accent cards. Passing a "failure" flag renders the numeral as `∞`.
10. A reusable bottom-sheet container renders: a `rgba(0,0,0,.55)` scrim that dismisses on tap, a panel with `bg` background, `2px solid ink` border (no bottom border), 26pt top-only corner radius, a centered 42×4 `inkFaint` drag handle, and an eyebrow + title + `✕` header. It slides up from +24pt with opacity .5→1 over ~0.25s.
11. A screen-mount transition (`fadein`) applies opacity 0→1 + 6pt rise over ~0.28s (timing curve ≈ cubic-bezier(.2,.7,.3,1)) and re-fires when the screen identity (`.id`) changes.
12. The You → Palette control lists Coastal and Mint as selectable swatches, marks the active one, and changing the selection satisfies criteria 2 and 3. (This feature ships only the Palette control; the rest of the You screen is BAK-out-of-scope.)
13. The color-usage rule is enforceable: highlight text on an `accent`-filled surface uses `onAccent`, never `accent2`. (Documented in code comments / token roles; verified by review, not a runtime test.)

## Screen / UX behavior
This feature is primarily a library of reusable primitives plus one small user-facing control. Grounded in `docs/design/README.md` (Design Tokens, Interactions & Behavior, Global Structure) and `pulse-app.jsx`.

- **Theme tokens.** Ten semantic colors per palette. Roles: `bg` = screen background; `surface` / `surface2` = cards, sheets, rows, raised fills; `ink` = primary text, structural borders, button stroke, hard shadow; `inkSoft` = secondary text / eyebrows; `inkFaint` = faint borders / dividers / track fills; `accent` = primary actions / fills; `accentDeep` = deep accent variant; `accent2` = secondary highlight only (current-set marker, streak, NEW / PR flags, rest-ring progress); `onAccent` = text / icons on an accent fill. Radii: cards 14–20 (rows 14, hero / lockup cards 20), pills / buttons 999 (Capsule), sheets 26 (top only), small chips 8–10. Spacing rhythm: 4 / 8 / 10 / 12 / 14 / 18 / 24. Borders: structural `1.5–2px inkFaint`; emphasis `2px accent` or `accent2`; accent cards & buttons `2px ink`.

- **Typography.** Hanken Grotesk (display / body, 400–900), Oswald (condensed, all hero numerals, 500/600/700, tracking ≈ -.02em, optional `scaleEffect(y:)` 1.1–1.35 for poster effect), Geist Mono (uppercase labels / eyebrows / units, 400/500/600, tracking .1–.16em). Concrete styles: H1 (Hanken 800, 28–32pt, tracking -.025em); Eyebrow (Geist Mono 500, 9–11pt, uppercase, tracking .16em, `inkSoft`); Row name (Hanken 700, 14pt, tracking -.005em); Row sub / unit (Geist Mono 500, 10pt, uppercase, .1em); Stat numeral (Oswald 700, ~26pt, tracking -.01em, lineHeight .85–.9, trailing unit small Hanken 10pt @ .6 opacity); Hero numeral (Oswald 700, 112–124pt+, lineHeight .82).

- **Lockup.** Two-column grid (column-gap 12, align-items start). Column 1: giant Oswald numeral spanning both rows. Column 2 row 1: Geist Mono eyebrow (`accent2` by default, padding-top ~8%). Column 2 row 2: bold Hanken sub-label, size ≈ 0.2× the numeral size (derive from the hero size so it scales), lineHeight .95, tracking -.02em, top-aligned with a slight negative top margin. Default numeral color `onAccent`; bottom label defaults to numeral color. Failure renders the numeral as `∞`.

- **Pressable button.** Capsule, `2px solid ink`, fill `accent`, text `onAccent`, Hanken 700, tracking -.005em. Resting shadow stack: inner top highlight (white .28), inner bottom shade (black .22), and a hard zero-blur `0 5px 0 ink` drop shadow. On press: content offsets +4pt, hard-shadow Capsule's y offset shrinks 5 → 1, animated ~0.1s with overshoot. Sizes sm/md/lg per criteria 7. Secondary: transparent, `ink` text, `1.5px solid ink`, no shadow / no press translate. Ghost: text-only, no border / shadow / padding. Icon buttons (`⋯`, back `←`): plain glyph, translate +1pt on press only. (Desktop `:hover` is ignored on iOS.)

- **Bottom sheet.** Bottom-anchored. Scrim `rgba(0,0,0,.55)`, tap-to-dismiss. Panel: `bg` background, `2px solid ink` border with no bottom border, 26pt top corners, padding 12 / 18 / 30, max height 84%, flex column. Centered 42×4 `inkFaint` handle. Header: Geist Mono eyebrow + Hanken bold title (often trailing `.`) + `✕` close at right. Scroll body with hidden scrollbar, side padding 18, content gap ~6–8. Dismissal: tap scrim, tap `✕`, or footer action. Implemented as a reusable container; specific sheets (Set Editor, Swap, etc.) are built by their owning features.

- **Transitions.** Screen mount `fadein`: opacity 0→1 + 6pt rise, ~0.28s timingCurve(.2,.7,.3,1), driven by an `.id()` on tab / overlay / phase. Sheet slide `sheetup`: +24pt → 0 + opacity .5→1, ~0.25s same curve.

- **Palette picker (You → Palette).** A horizontal swatch row (one swatch per palette showing its `accent` / `accent2` / `surface`), the active palette marked (e.g. `2px accent2` ring). Tapping a swatch sets the palette; the whole app re-skins instantly with no background animation. The prototype's floating top-right toggle is scaffolding and is **not** reproduced.

- **Grain (optional).** A low-opacity SVG fractal-noise overlay over `bg` is a nice-to-have; skip on iOS if it complicates. Not required for any acceptance criterion.

## Data & state
This feature is largely view-layer infrastructure and does **not** depend on the data-layer repositories (BAK-6); it has no domain data. The only stateful piece is theme selection.

- **`Theme` (`@Observable`, already present, extended here):** holds `var palette: Palette` persisted to `UserDefaults`/`@AppStorage("pulse-pal")`; exposes the ten resolved `Color` tokens plus `spacing`, `radiusCard`, `radiusPill` (and any added radii). Injected at the app root via `.environment(Theme.self)`. No repository calls.
- **`PaletteModel` (`@Observable`, the picker's model):** thin wrapper exposing `available: [Palette]`, `selected: Palette` (get/set proxying `Theme.palette`), and a `select(_:)` method. No repository, no async, no loading / empty / error states (purely local user preference).
- **Mock data:** none required. The Palette picker renders against the static `Palette.allCases`. Because the design-system primitives carry no domain data, there is no dependency on BAK-6 mock repositories for this feature — though every *consuming* feature will depend on both BAK-7 (this) and BAK-6.

## Out of scope
- The full **You** screen (avatar, mini-stats, YOUR DATA nav rows, Preferences, Notifications) — only the Palette swatch control ships here; the rest is the You / Settings feature.
- All concrete sheets (Set Editor, Swap, History, Jump, Exercise Picker, Create chooser, Workout Picker, Schedule) — those are built by their owning features using this feature's sheet container.
- The 4-tab bar / `NavigationStack` shell and active-workout full-takeover wiring — navigation is the app-shell feature; the active flow / session engine is **BAK-14** (and the Live Activity / Widgets depend on it).
- Real exercise media, icons beyond glyph / SF Symbol placeholders, and raster assets.
- Supabase wiring and any repository protocols (**BAK-6**).
- Optional grain overlay is non-blocking; may be deferred.

## Edge cases
- **First launch / no stored preference:** defaults to Coastal.
- **Corrupt / unknown `pulse-pal` value:** falls back to Coastal (`Palette(rawValue:)` returns nil → `.default`).
- **Theme switch flash:** the background must not animate on palette change; verify no `withAnimation` wraps the palette mutation.
- **Oswald (or any custom font) missing at runtime:** hero numerals fall back to a condensed system font; layout must not break (test both with-font and fallback paths if feasible).
- **Very large hero numerals (124pt+):** lockup sub-label is derived as a fraction of the numeral size and must remain top-aligned and not clip; numeral lineHeight .82 must not overlap the sub-label.
- **Failure set:** lockup numeral renders `∞` rather than a number.
- **Disabled button:** action never fires; opacity ~0.45; no translate.
- **Dynamic Type / accessibility sizing:** condensed hero numerals are explicitly sized (poster effect) — confirm behavior under larger accessibility text sizes (see open question).
- **Existing token implementation:** `Palette.swift` currently stores the full `ink` hex in the `inkSoft` / `inkFaint` slots and `Theme` applies `.opacity(0.62)` / `.opacity(0.16)` to `ink` directly — confirm this stays the source of truth and the unused `PaletteTokens.inkSoft/inkFaint` fields are either removed or honored consistently.

## Open questions
1. **Custom font packaging:** are the Hanken Grotesk / Oswald / Geist Mono font files vendored into `Pulse/Resources` and declared in `project.yml` (`UIAppFonts`), or do we ship only system-font fallbacks for v1? The design says the condensed look is essential but the repo does not yet contain the font files.
2. **Dynamic Type / accessibility:** should hero numerals and condensed labels scale with Dynamic Type, or are they fixed poster sizes? The design specifies absolute pt values; accessibility scaling behavior is unspecified.
3. **Palette swatch visual:** the design doc does not define the exact look of the You → Palette swatch (size, which tokens each swatch shows, selected-state treatment). Confirm before building.
4. **Sheet implementation choice:** native `.sheet` + `.presentationDetents` vs. a fully custom overlay. The design's 26pt top-only radius, exact scrim opacity, and tap-to-dismiss-on-backdrop are hard to match precisely with the native sheet chrome — which path do we take?
5. **`scaleEffect(y:)` poster stretch (1.1–1.35):** is this applied globally to all hero numerals, only on specific screens, or left as a per-call option? The prototype uses it "occasionally."
6. **Grain overlay:** ship it or defer? Marked optional in the design.
7. **Animation fidelity:** is a SwiftUI spring approximation of cubic-bezier(.2,.7,.3,1.4) (overshoot on button press) acceptable, or must we match the curve exactly via `.timingCurve`?

## Tests required
**Unit tests (`PulseTests/`):**
- `ThemeTests`: each token returns the correct value per palette (Coastal vs Mint); `inkSoft` / `inkFaint` opacity derivation is correct; default palette is Coastal when no stored value; unknown stored value falls back to Coastal; setting `palette` persists to `UserDefaults` under `"pulse-pal"`.
- `PaletteTests`: `Palette.allCases` is `[coastal, mint]`; `rawValue` round-trips; `tokens` hex strings match the handoff for both palettes.
- `PaletteModelTests`: `selected` reflects `Theme.palette`; `select(_:)` updates the theme and persistence; no background animation flag is set on switch.
- `ColorHexTests`: `Color(hex:)` parses valid `#RRGGBB`, tolerates missing `#`, and returns `.clear` on malformed input (covers existing helper).

**Acceptance / UI tests (`PulseUITests/`):** mapped to acceptance criteria.
- AC1–2: launch with no preference → Coastal applied; relaunch after switching → preference persists.
- AC3 / AC12: in the Palette picker, select Mint → representative surfaces re-skin to Mint tokens; select Coastal → revert; assert no animated background transition.
- AC5–8: a primary button shows resting hard shadow; pressing it triggers the depress state and fires the action once; disabled button does not fire; sm / md / lg render at expected heights; secondary / ghost render without shadow.
- AC9: a Lockup renders its numeral and labels; failure flag renders `∞`.
- AC10–11: presenting the sheet container slides it up; tapping the scrim dismisses it; tapping `✕` dismisses it; a pushed screen plays the fade+rise on mount.

(A small DesignSystem gallery / preview screen, gated to DEBUG, is recommended as the UI-test host since no production screen renders these in isolation yet — confirm whether to add one.)

## Files that will change
- `Pulse/Core/DesignSystem/Theme.swift` — extend with any added radii / spacing helpers; confirm token derivation. *(exists)*
- `Pulse/Core/DesignSystem/Palette.swift` — reconcile `inkSoft` / `inkFaint` token storage. *(exists)*
- `Pulse/Core/DesignSystem/Typography.swift` — **new**: font registration + `Font`/`Text` style API (H1, eyebrow, row name, row sub, stat numeral, hero numeral) with fallbacks.
- `Pulse/Core/DesignSystem/PressableButtonStyle.swift` — **new**: primary / secondary / ghost `ButtonStyle`s, sizes sm/md/lg, hard-shadow + depress animation; icon-button style.
- `Pulse/Core/DesignSystem/Lockup.swift` — **new**: the two-column hero numeral composition (with `∞` failure case).
- `Pulse/Core/DesignSystem/BottomSheet.swift` — **new**: reusable sheet container (scrim, panel, handle, eyebrow+title+✕ header) + presentation modifier.
- `Pulse/Core/DesignSystem/Transitions.swift` — **new**: `fadein` and `sheetup` transition / animation modifiers and timing curves.
- `Pulse/Core/DesignSystem/DesignSystemPreview.swift` — **new (DEBUG)**: gallery host for previews and UI-test anchoring.
- `Pulse/Features/You/PaletteView.swift` — **new**: the You → Palette swatch picker.
- `Pulse/Features/You/PaletteModel.swift` — **new**: `@Observable` model proxying `Theme.palette`.
- `Pulse/App/` — inject `.environment(Theme.self)` at the root (if not already) and register fonts at launch.
- `Pulse/Resources/` — add Hanken Grotesk / Oswald / Geist Mono font files (pending open question 1).
- `project.yml` — declare bundled fonts (`UIAppFonts`); regenerate via `xcodegen generate` (never hand-edit `.xcodeproj`).
- `PulseTests/DesignSystem/ThemeTests.swift`, `PaletteTests.swift`, `PaletteModelTests.swift`, `ColorHexTests.swift` — **new**.
- `PulseUITests/DesignSystemUITests.swift` — **new**.
