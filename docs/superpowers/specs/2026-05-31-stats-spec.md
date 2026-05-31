# Stats — Spec

**Linear:** BAK-15  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview

Stats is a read-only analytics screen pushed onto the navigation stack from the **You** tab ("YOUR DATA → Stats"). It summarizes training output over a selectable time range: a hero volume card with a 12-bar trend chart, a 2×2 grid of headline sub-stats (Sessions / New PRs / Avg Time / Streak), and a horizontal "Volume by muscle" bar list. It is purely a display surface — no editing, no logging — built UI-first against a mock repository so it renders before the real Supabase data layer (BAK-6) lands.

## User story

As a lifter, I want to see my training volume, session count, PRs, average session time, streak, and how my volume splits across muscle groups over a chosen time window, so that I can understand my recent progress and where I'm putting in work at a glance.

## Acceptance criteria

1. Navigating from You → "Stats" pushes the Stats screen onto the stack with a back affordance; tapping back returns to You.
2. The screen shows a TopBar with `STATS` eyebrow and a `⋯` glyph, and an H1 reading `Your numbers.`
3. A horizontally scrollable range-chip row offers `7D / 30D / 3M / YR / ALL`; `30D` is selected on first appearance.
4. Tapping a different range chip selects it (single-select, visibly active) and re-loads the displayed aggregate for that range (hero card, chart, 2×2 grid, and muscle list all update).
5. The hero accent card shows an eyebrow `<RANGE> VOLUME · <UNITS>` (e.g. `30D VOLUME · LBS`), a lockup with the volume numeral (e.g. `184K`) and a top-label trend string (e.g. `+12% vs prev`), and a 12-bar volume chart rendered in `onAccent`.
6. The 2×2 grid renders four sub-stat cards in order: **Sessions** (`21/22`, sub `OF PLAN`), **New PRs** (accent, sub `THIS MONTH`), **Avg Time** (`62m`, sub `PER SESSION`), **Streak** (accent-2, `27d`, sub `PERSONAL BEST`).
7. A `VOLUME BY MUSCLE` eyebrow precedes a horizontal bar list; each row shows muscle label, a proportional bar, and the muscle's volume value. The single highest-volume muscle's bar uses `accent2`; all others use `accent`.
8. While the initial load (or a range change) is in flight, a loading state is shown; on completion the populated content replaces it; the screen never renders zero-height bars or partial garbage as if it were data.
9. If the repository call fails, an error state is shown with a retry affordance rather than a crash or blank screen.
10. If a range returns no training data (e.g. a brand-new account on `7D`), an empty state is shown (zeroed/`—` stats, no misleading bars) rather than a populated-looking screen.
11. All colors, spacing, radii, and typography come from `Theme` tokens; switching Coastal ↔ Mint under You → Palette restyles the screen with no layout shift.

## Screen / UX behavior

Layout follows design README §6 and `StatsScreen` in `docs/design/pulse-app.jsx` (lines ~1200–1242).

- **Container:** standard stack screen (`body`), screen-mount fade+rise transition.
- **TopBar:** back chevron (pops the stack), eyebrow `STATS` (Geist Mono, uppercase, tracked), `⋯` glyph on the right (non-functional placeholder).
- **H1:** `Your numbers.` (Hanken Grotesk).
- **Range chips:** horizontal scrolling row of pill `FilterChip`s `7D / 30D / 3M / YR / ALL`; the active chip uses the design system's selected/filled chip style. Default active = `30D`. Single-select.
- **Hero accent card (`card accent`):**
  - Eyebrow in `onAccent` (slightly reduced opacity per prototype): `30D VOLUME · LBS` — range token + units token.
  - Lockup: big Oswald numeral for the volume (the trailing magnitude letter, e.g. `K`, is rendered in Hanken Grotesk at reduced weight/size per prototype), a top-label trend string (`+12% vs prev`), and a bottom caption (`Trending up.`).
  - 12-bar chart beneath the lockup, bars filled in `onAccent` (highlight text/graphics on an accent card use `onAccent`, never `accent2`, per design rules).
- **2×2 sub-stat grid:** two-column grid of `SmallStat` cards. Each card: small eyebrow label, big Oswald value with optional unit suffix, and a small sub eyebrow. Color emphasis: New PRs value in `accent`; Streak value + label in `accent2`; Sessions and Avg Time use default `ink`/`inkSoft`.
- **Volume by muscle:** `VOLUME BY MUSCLE` eyebrow, then one row per muscle: fixed-width label (Hanken Grotesk), a track (`inkFaint` background) with a proportional fill bar, and a right-aligned Oswald value. Fill color = `accent` for all rows except the max-volume muscle, which uses `accent2`.
- **Navigation:** entered only from You. No outbound navigation from this screen in scope (sub-stat cards are not tappable in the prototype — see Open questions).

## Data & state

Each screen = a `View` + an `@Observable` model in `Pulse/Features/Stats/`.

`@Observable final class StatsModel`:

- `phase: LoadPhase` — `.loading / .loaded / .empty / .error` (matching the convention used by sibling specs).
- `selectedRange: StatsRange` — enum `{ d7, d30, m3, yr, all }`; defaults to `.d30`.
- `summary: StatsSummary?` — the aggregate for the selected range, nil until loaded.
- Derived/computed: `volumeChartMax` (for bar scaling, with a minimum floor so non-zero bars never render invisible), `maxVolumeMuscleID` (which `VolumeByMuscle` row gets `accent2`), `unitsLabel` (from settings, e.g. `LBS`).
- Methods: `load()` (async) — calls the repository for `selectedRange`, populates `summary`, sets `phase`; `select(_ range:)` — sets `selectedRange` then re-runs `load()`; `retry()` — re-runs `load()` after `.error`.

Domain shape rendered (per research digest):

```
struct StatsSummary {
  let volume: Int                 // total volume for range
  let volumeDisplay: String       // e.g. "184K"
  let volumeTrendPct: Int         // +12 → "+12% vs prev"
  let volumeSeries: [Int]         // 12 bars
  let sessions: Int               // 21
  let sessionsPlanned: Int        // 22
  let newPRs: Int                 // 4
  let avgTimeMinutes: Int         // 62
  let streakDays: Int             // 27
  let volumeByMuscle: [VolumeByMuscle] // {id, muscle, value, valueDisplay, pct}
}
```

Repository protocol it calls (defined in BAK-6, mock-backed here):

- `StatsRepository.summary(range:) async throws -> StatsSummary` — returns the aggregate for a given range. (Exact protocol name/placement is a dependency on BAK-6 — see Open questions.)

Mock data: the in-memory `StatsRepository` mock seeds the design's sample values for `30D` (volume `184K`, trend `+12%`, 12-bar series `[40,55,52,68,72,80,60,75,72,85,90,82]`, sessions `21/22`, new PRs `4`, avg time `62m`, streak `27d`, muscle list Chest 42k / Back 38k / Legs 56k / Shoulders 22k / Arms 18k with Legs as the accent-2 max). Other ranges return plausible scaled sample summaries so every chip renders content. The screen renders entirely against these mocks; real Supabase wiring is deferred to BAK-6.

Dependencies: Design System tokens/components (BAK-7); repository protocols + mocks (BAK-6).

## Out of scope

- Real Supabase persistence/aggregation queries (BAK-6).
- The `⋯` overflow menu actions (glyph only, non-functional).
- Tappable sub-stat cards / drill-down navigation (e.g. tapping "New PRs" → Personal Records). Personal Records and Workout History are their own screens (BAK siblings) reached from You, not from Stats.
- Editing, exporting, or sharing stats.
- Custom/arbitrary date-range pickers beyond the five fixed chips.
- Per-exercise or per-variation breakdowns (that lives in Exercise Detail / History).
- Units conversion logic (LBS↔KG) — the screen reads the units label from settings; conversion math belongs to the data layer.
- Live Activity / widget surfaces (BAK-14).

## Edge cases

- **Empty range (new account / no sessions in window):** `.empty` phase — show zeroed or `—` stats and suppress the volume chart and muscle bars rather than rendering zero-height bars as data.
- **Single muscle with all volume, or all-equal volumes:** `maxVolumeMuscleID` resolves deterministically (first max wins); bars use a minimum floor height so a near-zero bar is still visible.
- **All-zero volume series:** chart hidden or shown flat at floor height, not collapsed to invisible.
- **Negative trend:** trend string renders the sign correctly (e.g. `-8% vs prev`); spec does not assume only positive trends.
- **`sessions > sessionsPlanned`** (over-delivered against plan): display the raw `21/22`-style fraction without clamping; do not show >100%.
- **Range with no "previous" period to compare** (e.g. `ALL`): trend label may be absent/`—` — see Open questions.
- **Large volume values:** `volumeDisplay` abbreviates (e.g. `184K`, `1.2M`); numeral + magnitude suffix styling is preserved.
- **Theme switch mid-screen:** Coastal ↔ Mint restyles tokens only — accent hero card, onAccent bars, accent/accent-2 stat emphasis, and the accent-2 max-volume muscle bar all re-derive from tokens with no layout shift.
- **Repository failure:** `.error` phase with retry; no crash, no stale partial content.

## Open questions

1. **Repository name & placement:** Is Stats served by a dedicated `StatsRepository`, or computed by a broader analytics/session repository (and where do the aggregates live relative to `SessionRepository`)? Defined by BAK-6.
2. **Trend semantics for boundary ranges:** What is the comparison baseline for the `+12% vs prev` trend (immediately preceding equal-length window?), and what does the trend show for `ALL` where no prior period exists?
3. **Are sub-stat cards interactive?** The prototype renders them as static cards. Should any (e.g. New PRs, Sessions) deep-link to Personal Records / Workout History? Design does not specify.
4. **Units source & conversion:** Is the units label (`LBS`/`KG`) read from the You → Preferences settings model, and does Stats display pre-converted values from the data layer, or convert on-screen? Not specified by design.
5. **Volume `K`/`M` abbreviation rules:** exact thresholds and decimal precision for `volumeDisplay` and per-muscle values (`42k` vs `42.3k`) are not defined.
6. **Per-range plan target:** `sessionsPlanned` ("OF PLAN") for ranges other than the active program's current cycle (e.g. `YR`, `ALL`) is undefined — what does "plan" mean over a year?
7. **Streak "PERSONAL BEST" semantics:** is the Streak stat the *current* streak or the *all-time best*? The label says PERSONAL BEST but the value matches the current streak shown elsewhere (You tab `27D`).

## Tests required

Unit tests (`PulseTests/Features/Stats/StatsModelTests.swift`) for the `@Observable` model:

- Initial state: `selectedRange == .d30`, `phase == .loading` before load resolves.
- `load()` happy path populates `summary` and sets `phase == .loaded` (asserts mapped values: volume display, sessions fraction, streak, 12-bar series count == 12, muscle list count).
- `select(_:)` changes `selectedRange` and triggers a reload that swaps in the new range's summary.
- `maxVolumeMuscleID` correctly identifies the highest-volume muscle (and is deterministic on ties).
- `volumeChartMax` floor logic: an all-zero or single-nonzero series still yields a usable, non-collapsing scale.
- Empty result → `phase == .empty`; failing repository → `phase == .error`; `retry()` recovers to `.loaded` when the repository succeeds.

Acceptance / UI tests (`PulseUITests/StatsTests.swift`) mapping to acceptance criteria:

- Navigate You → Stats; assert TopBar `STATS`, H1 `Your numbers.` (AC 1–2).
- Range chips present, `30D` active by default; tapping `7D` updates active chip and content (AC 3–4).
- Hero card eyebrow, volume numeral, trend, and 12 bars present (AC 5).
- 2×2 grid shows the four stats in order with correct labels/subs (AC 6).
- Volume-by-muscle list renders rows; max-volume muscle bar uses the accent-2 styling (AC 7).
- Loading → loaded transition; empty state for a no-data range; error state shows retry (AC 8–10).
- Theme switch (Coastal ↔ Mint) does not change layout (AC 11).

## Files that will change

- `Pulse/Features/Stats/StatsView.swift` — new screen view.
- `Pulse/Features/Stats/StatsModel.swift` — new `@Observable` model.
- `Pulse/Features/Stats/StatsRange.swift` — range enum (or co-located in the model file).
- `Pulse/Core/Models/StatsModels.swift` — `StatsSummary`, `VolumeByMuscle` domain structs (placement may move under BAK-6).
- `Pulse/Core/Data/StatsRepository.swift` — repository protocol + in-memory mock with sample data (depends on / coordinated with BAK-6).
- `Pulse/Features/You/` — wire the existing "Stats" `NavRow` to push `StatsView` (navigation hook only).
- `PulseTests/Features/Stats/StatsModelTests.swift` — model unit tests.
- `PulseUITests/StatsTests.swift` — acceptance/UI tests.
- `project.yml` — only if new source files require target/membership updates; regenerate via `xcodegen generate` (never hand-edit `.xcodeproj`).
