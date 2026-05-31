# You / Settings — Spec
**Linear:** BAK-13  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview
The **You** tab is the fourth root tab and the profile/settings home. It shows the
lifter's identity (avatar, name, membership), a 3-up summary of headline stats, a
"Your data" hub that pushes to Stats / Personal Records / Workout History, a live
**Palette** swatch picker (Coastal/Mint), and a **Preferences** group (units, default
rest timer, auto-progress, rest sound). This feature delivers the You landing screen
itself plus the palette and preference controls; the three destination screens it links
to (Stats, PRs, History) are separate backlog items and are out of scope here beyond
wiring the navigation rows.

## User story
As a lifter, I want a profile screen that surfaces my key numbers, lets me jump to my
detailed stats/PRs/history, switch the app's color theme, and adjust my training
preferences, so that I can personalize the app and reach my data quickly.

## Acceptance criteria
1. The You tab renders a top bar with a `YOU` eyebrow (Geist Mono, `inkSoft`) and a
   trailing `⋯` overflow glyph.
2. A profile header shows a circular avatar (single initial in Oswald on an `accent`
   fill, `2px solid ink` border, `onAccent` text), the user's display name as an H1
   (with trailing period, e.g. `Alex Mason.`), and a sub line `Member since <month year> · <programLabel>`.
3. A 3-up MiniStat strip renders **STREAK** (value + `d` unit, eyebrow + numeral in
   `accent2`), **SESSIONS** (value only, `ink`), and **VOLUME** (value + unit, eyebrow
   in `accent`, numeral in `ink`). Numerals use Oswald; units use small Hanken at reduced opacity.
4. A `YOUR DATA` section renders three NavRows — **Stats** (`Volume, PRs, charts`,
   `accent` icon tile), **Personal records** (`N lifts tracked`, `accent2` "PR" tile),
   **Workout history** (`N sessions logged`, `inkFaint` "H" tile) — each with a name,
   sub-count, and trailing chevron.
5. Tapping a NavRow pushes the corresponding stack screen (Stats / Personal Records /
   Workout History) onto the You tab's `NavigationStack`. (Destinations are stubbed/owned
   by other backlog items; the row navigation intent must be testable here.)
6. A `PALETTE` section shows a `Theme` row with the current palette label
   (`Coastal`/`Mint`) and a swatch picker — one circular swatch per palette filled with
   that palette's `accent`. The selected swatch is ringed (`2px solid ink` + `accent2`
   halo); unselected swatches use a faint `inkFaint` border.
7. Tapping a swatch switches the active theme instantly and re-skins the entire app
   (all ten tokens swap). The choice persists across launches via `@AppStorage("pulse-pal")`
   with values `"coastal"`/`"mint"`. The background must not animate/flash on switch.
8. A `PREFERENCES` group (single rounded card, `inkFaint` border) renders four rows:
   **Units** (value `LBS · IMPERIAL`, trailing chevron), **Default rest timer** (value
   `90s`, trailing chevron), **Auto-progress weight** (toggle), **Sound on rest end** (toggle).
9. Toggling a preference toggle flips its bound boolean in the model and persists it; the
   switch reflects the new state immediately.
10. On first appearance the model loads settings + profile + aggregate stats from the
    repositories; while loading, the screen shows a non-blocking placeholder/skeleton and
    does not crash on absent data.
11. If a repository call fails, the model surfaces a non-fatal error state and the screen
    still renders with last-known/default settings (the screen never blocks the user from
    changing palette, which is local).
12. All colors and spacing come from `Theme` tokens — no hardcoded hex or magic spacing.

## Screen / UX behavior
Layout top-to-bottom (grounded in README §5 and the `YouScreen` prototype):

- **Top bar:** `TopBar` with eyebrow `YOU` and a right `⋯` icon button (overflow; no menu
  defined yet — see Open questions).
- **Profile header:** horizontal row, 56pt avatar circle + name/sub block. Avatar = Oswald
  initial, `accent` fill, `onAccent` text, `2px solid ink`. H1 Hanken 800 ~26pt. Sub =
  row-sub style (Geist Mono / `inkSoft`).
- **MiniStat strip:** 3-column equal grid (gap 6). Each MiniStat = flat `surface` card,
  Geist Mono eyebrow + Oswald numeral (`lineHeight ~.85`), optional small Hanken unit. Color
  treatment per AC 3 (STREAK→`accent2`, VOLUME eyebrow→`accent`).
- **Scroll body** (gap ~6):
  - `YOUR DATA` eyebrow, then three NavRows. NavRow = `surface` row, 32pt rounded icon
    tile + name (Hanken 700) + sub (Geist Mono) + trailing chevron; whole row pressable.
  - `PALETTE` eyebrow, then a `Theme` row (label + sub = current palette label) with the
    swatch picker on the trailing side. One swatch per `Palette` case; selection ring as AC 6.
  - `PREFERENCES` eyebrow, then one rounded container holding four `SetRow`s. Value rows show
    value text + chevron (tapping opens a picker — see Open questions / Out of scope); toggle
    rows show the chunky pill switch (`on` = `accent`).
- **Navigation:** NavRows push onto the You `NavigationStack`; switching tabs resets the path
  (per the app shell navigation model). Active workout is unrelated here.
- **Motion:** screen mount uses the standard fade+rise (`.28s`, timing curve `0.2,0.7,0.3,1`).
  Palette change is the explicit exception — no implicit animation on the background.
- **Buttons/press:** NavRows and swatches use the standard press feedback; no primary pill
  buttons appear on this screen.

## Data & state
`@Observable` model `YouModel` in `Pulse/Features/You/`:

```swift
@Observable final class YouModel {
    // loaded snapshots
    private(set) var profile: UserProfile?        // name, avatarInitial, memberSince, programLabel
    private(set) var stats: ProfileStats?         // streak, sessions, totalVolume(+unit)
    var settings: UserSettings                     // units, defaultRest, autoProgress, soundOnRest
    private(set) var phase: LoadPhase = .loading   // .loading | .loaded | .failed(String)

    // palette is app-global, not owned here:
    // bound to @AppStorage("pulse-pal") at the shell; the swatch picker reads/writes it.

    func load() async { /* calls repos, sets phase */ }
    func setAutoProgress(_ on: Bool) async { /* mutate + persist */ }
    func setSoundOnRest(_ on: Bool) async { /* mutate + persist */ }
}
```

Repository protocols consumed (defined/owned by BAK-6; **mock implementations + sample
data assumed to exist**):
- `UserRepository.currentProfile() async throws -> UserProfile` — name, avatar initial,
  member-since date, current program label.
- `StatsRepository.profileSummary() async throws -> ProfileStats` — streak, total sessions,
  total volume (value + unit). (NavRow sub-counts `N lifts tracked` / `N sessions logged`
  also come from here or from PR/History repos — see Open questions.)
- `SettingsRepository.load() async throws -> UserSettings` and
  `SettingsRepository.save(_ settings: UserSettings) async throws` — units, default rest,
  autoProgress, soundOnRest. (Palette is persisted separately via `@AppStorage`, not this repo.)

Mock data the screen renders against (mirrors prototype): profile `Alex Mason · Member since
Feb 2024 · PPL`; stats `streak 27d · 183 sessions · 2.1M volume`; NavRow subs `8 lifts tracked`,
`183 sessions logged`; settings `LBS · IMPERIAL`, `90s`, autoProgress on, soundOnRest on.

Palette: the active `Palette` and its `Theme` are resolved at the app root from
`@AppStorage("pulse-pal")` and injected via environment. The You screen's swatch picker is a
thin control that writes that storage; the model itself does not own theme state.

## Out of scope
- The destination screens **Stats** (BAK-?), **Personal Records**, **Workout History** — this
  feature only wires the NavRows that push to them.
- The `⋯` overflow menu contents/actions (no menu is defined in the design).
- Editing the **Units** and **Default rest timer** values (the picker sheets/flows those
  chevron rows imply) — this feature renders the rows and their current values; the editing
  UI is unspecified (see Open questions).
- Account/auth, sign-out, profile editing, avatar upload.
- Notifications settings (mentioned once in README §5 but with no design; not in the prototype).
- Real Supabase wiring (BAK-6) and any Live Activity/Widget concerns (BAK-14).

## Edge cases
- **Loading:** repos in-flight → skeleton/placeholder values; no crash on `nil` snapshots.
- **Empty/new user:** zeroed stats (`0d`, `0`, `0`) and empty NavRow subs (`0 lifts tracked`,
  `0 sessions logged`) must render cleanly; avatar falls back to a default initial if name is empty.
- **Repository error:** non-fatal; screen renders with defaults/last-known settings and the
  palette picker remains fully functional (local-only).
- **Theme switching:** instant re-skin of all ten tokens; background must not animate or flash
  (do not wrap palette mutation in `withAnimation`); selected-swatch ring updates immediately;
  persisted across relaunch.
- **Toggle persistence:** flipping a toggle then backgrounding the app must retain the value;
  if `save` fails the toggle should not silently lie about persisted state (surface error or revert — see Open questions).
- **Long name / long program label:** H1 and sub truncate gracefully without breaking layout.

## Open questions
1. Do the **Units** and **Default rest timer** rows open editing UI in this feature, or are
   they display-only stubs for now? The prototype shows a chevron but no editor; README lists
   empty/loading states and notifications as "not yet built."
2. What are the allowed values for **Units** (just `LBS · IMPERIAL` vs a `KG · METRIC`
   alternative?) and **Default rest timer** (discrete steps? range?)? Not specified.
3. Where do the NavRow sub-counts come from — `8 lifts tracked` (PR repo?) and
   `183 sessions logged` (History/Stats repo?) — and should they update live or are they static
   in v1?
4. Should the **VOLUME** MiniStat unit (`M`) and value formatting be locale/units-aware, and
   does it follow the Units preference?
5. On a failed `SettingsRepository.save`, should the toggle revert with an error, or keep the
   optimistic value and retry? No design guidance.
6. The `⋯` overflow button — does it have any action in v1, or is it a decorative stub like the
   library search field?
7. Is **Notifications** (named in README §5 prose but absent from the prototype and digest) in
   scope for this screen at all? Assumed out of scope here pending confirmation.

## Tests required
**Unit (`YouModel`):**
- `load()` populates `profile`, `stats`, `settings` and transitions `phase` to `.loaded` on
  success (against mock repos).
- `load()` transitions `phase` to `.failed` (or equivalent non-fatal state) when a repo throws,
  while leaving `settings` at defaults/last-known.
- `setAutoProgress(_:)` / `setSoundOnRest(_:)` mutate `settings` and call `SettingsRepository.save`
  with the updated value.
- Empty/new-user mock yields zeroed stats and empty sub-counts without crashing.

**Acceptance / UI (map to ACs):**
- AC1–AC4: You screen renders top bar, profile header, three MiniStats with correct
  values/colors, and three NavRows with correct names/subs.
- AC5: tapping each NavRow triggers navigation to the matching destination (assert pushed route
  / destination identity).
- AC6–AC7: swatch picker shows both palettes, selection ring on the active one; tapping the other
  swatch updates the active `Theme` and persists `pulse-pal`; relaunch restores the choice; no
  background animation on switch.
- AC8–AC9: Preferences group shows four rows with correct values; toggling a switch flips state
  and persists.
- AC10–AC11: loading shows placeholder; injected failing repo still renders the screen and keeps
  the palette picker usable.
- AC12: snapshot/lint check that no hardcoded colors or spacing are used (tokens only).

## Files that will change
- `Pulse/Features/You/YouView.swift` — the You screen.
- `Pulse/Features/You/YouModel.swift` — `@Observable` model.
- `Pulse/Features/You/Components/MiniStat.swift` — 3-up stat card (if not already shared).
- `Pulse/Features/You/Components/NavRow.swift` — icon-tile nav row (if not already shared).
- `Pulse/Features/You/Components/PaletteSwatchPicker.swift` — palette swatch control.
- `Pulse/Features/You/Components/PreferenceRow.swift` — value/toggle settings row.
- `Pulse/Core/Models/UserProfile.swift`, `Pulse/Core/Models/UserSettings.swift`,
  `Pulse/Core/Models/ProfileStats.swift` — domain structs (if not already present from BAK-6).
- `Pulse/Core/Data/UserRepository.swift`, `Pulse/Core/Data/StatsRepository.swift`,
  `Pulse/Core/Data/SettingsRepository.swift` — repository protocols + mock conformances + sample
  data (owned by BAK-6; this feature consumes/extends them as needed).
- `Pulse/App/` — register the You tab destination + NavigationStack routes for Stats / PRs / History
  (route enum entries; destination screens themselves owned by their own backlog items).
- `PulseTests/YouModelTests.swift` — unit tests for the model.
- `PulseUITests/YouScreenTests.swift` — acceptance/UI tests mapping to the ACs.
- `project.yml` — only if new files require target/group updates (regenerate via `xcodegen generate`; never hand-edit `.xcodeproj`).

## Dependencies
- **BAK-7 (Design System):** `Theme` tokens, typography (Hanken/Oswald/Geist Mono), pressable
  styles, `Eyebrow`/row primitives, the palette/`@AppStorage("pulse-pal")` plumbing.
- **BAK-6 (Data layer):** `UserRepository`, `StatsRepository`, `SettingsRepository` protocols +
  in-memory mocks + sample data. This UI-first feature binds to those protocols backed by mocks.
- **BAK-14 (active flow / session engine):** not required for this screen, but the `Default rest
  timer` and `Sound on rest end` preferences are *consumed* by the active workout/rest flow; the
  source of truth for those values lives here.
