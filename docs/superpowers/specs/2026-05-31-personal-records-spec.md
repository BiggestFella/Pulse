# Personal Records — Spec

**Linear:** BAK-16  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview
Personal Records ("PRs.") is a read-only stack screen pushed from **You → Personal records** that surfaces the lifter's best lifts. It shows a count summary, muscle-group filter chips, a single accent **hero PR card** for the standout record, and a 2-column grid of PR cards (recently-set records get a `NEW` flag and accent-2 border). This is a **UI-first** build: the screen binds to a repository protocol backed by an in-memory mock with sample data (per BAK-6); no real Supabase wiring is included here. It depends on the Design System tokens/components (BAK-7).

## User story
As a lifter, I want to see all my personal records grouped and filterable by muscle, with my newest PRs highlighted, so that I can track progress and feel rewarded when I hit a new best.

## Acceptance criteria
1. Pushing the screen shows TopBar eyebrow `PERSONAL RECORDS` (with a trailing ⋯ overflow control), H1 `PRs.`, and a sub-line of the form `{N} lifts tracked · {M} new this month`, where `N` is the total PR count and `M` is the count of PRs marked fresh-this-month.
2. A horizontally scrollable row of muscle filter chips renders with a leading `All` chip plus one chip per distinct muscle group present in the PR data; `All` is selected by default (accent chip style).
3. Selecting a muscle chip filters both the hero card and the grid to PRs in that muscle group; selecting `All` clears the filter. The selected chip is visually active; exactly one chip is selected at a time.
4. The hero PR card (accent fill) renders for the designated hero PR within the current filter: a `NEW · {date}` pill (only when the PR is fresh), a muscle eyebrow, the lift name, the big weight numeral (Oswald) with a `lb`/unit suffix, and the rep count (e.g. `×1`) in accent-2.
5. Below the hero, a 2-column grid renders one card per remaining (non-hero) PR in the current filter, each showing: muscle eyebrow, an optional `NEW` eyebrow flag (accent-2) when fresh, lift name, weight numeral + unit suffix, rep count (accent-2), and the date sub-line.
6. Fresh PR cards in the grid render with an accent-2 border (thicker) versus the faint border of non-fresh cards.
7. While PR data is loading, a loading state is shown (not stale/blank content); on load completion the content appears.
8. If the repository returns no PRs (empty state), the screen shows an explicit empty message instead of an empty grid, and the hero card is omitted.
9. If a filter selection yields no matching PRs, a per-filter empty state is shown (e.g. "No PRs for {muscle} yet") with the chips still interactive.
10. If the repository throws, an error state with a retry affordance is shown; no partial/stale content is displayed.
11. All colors, spacing, radii, and typography use Theme tokens; switching palette (Coastal ↔ Mint) re-renders correctly with no hardcoded values.

## Screen / UX behavior
Grounded in design README §7 and `pulse-app.jsx` `PRScreen` (lines 1244–1286) and the `PRS` sample data (lines 103–110).

- **TopBar:** back chevron (pops the stack to You), eyebrow `PERSONAL RECORDS` (Geist Mono, uppercase, letter-spaced), trailing ⋯ overflow control. Screen mount uses the standard fade+rise transition.
- **Header block:** H1 `PRs.` (Hanken Grotesk). Sub-line `{N} lifts tracked · {M} new this month` in `ink-soft`.
- **Filter chips:** horizontally scrollable chip row using the accent chip style; leading `All` then one per muscle group (`Chest`, `Back`, `Legs`, `Arms`, `Delts`, … derived from data). Active chip filled, inactive outlined. Tap toggles the active filter.
- **Hero PR card:** accent-filled card (radius per card token). Top row: a pill (`on-accent` background, `accent` text) reading `NEW · {date}` on the left (shown only when the hero PR is fresh) and the muscle eyebrow on the right. Then the lift name in `on-accent` (Hanken Grotesk, heavy). Then a baseline-aligned lockup: large weight numeral (Oswald ~64pt) in `on-accent` with a small `lb` suffix, beside the rep count (Oswald ~34pt) in **accent-2**. Per the design-system rule, the small highlight (reps) on an accent card uses accent-2 here — this is the explicit reps accent in the JSX; the rule about "small highlight text uses onAccent not accent2" applies to text highlights, while the rep numeral is the design's intended accent-2 figure. (See Open questions.)
- **Grid:** 2-column grid of compact cards. Each card: top row with muscle eyebrow (left) and `NEW` eyebrow in accent-2 (right, when fresh); lift name in `ink`; baseline lockup of weight numeral (Oswald ~24pt) + small unit suffix and rep count (Oswald ~14pt) in accent-2; date eyebrow sub-line. Fresh cards: `accent-2` border, ~2pt width. Non-fresh: `ink-faint` border, ~1.5pt width.
- **Scroll:** header + chips are followed by a scrolling body containing the hero card then the grid.
- **Navigation:** read-only screen. No taps into Exercise Detail are specified by the design for PR cards (see Open questions). Back returns to You.

## Data & state
**Domain model.** Add a `PersonalRecord` model (the design's `PR = {exerciseName, weight, reps, muscle, date, fresh, hero}`). The current `Pulse/Core/Models/WorkoutModels.swift` has no PR type. Proposed shape:

```swift
struct PersonalRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var exerciseID: Exercise.ID?   // link to catalog (nullable for one-offs)
    var exerciseName: String
    var muscleGroup: String
    var weight: Double
    var reps: Int
    var achievedAt: Date
    var isFresh: Bool              // set recently / "this month"
    var isHero: Bool              // standout record for the hero card
}
```

**@Observable model** — `PersonalRecordsModel` in `Pulse/Features/PersonalRecords/`:

```swift
@Observable final class PersonalRecordsModel {
    enum Phase { case loading, loaded, empty, error(String) }
    private(set) var phase: Phase = .loading
    private(set) var records: [PersonalRecord] = []
    var selectedMuscle: String? = nil        // nil == "All"

    var muscleFilters: [String] { /* distinct muscles, ordered */ }
    var filtered: [PersonalRecord] { /* records matching selectedMuscle */ }
    var hero: PersonalRecord? { /* filtered.first(where: isHero) ?? filtered.first */ }
    var gridRecords: [PersonalRecord] { /* filtered minus hero */ }
    var trackedCount: Int { records.count }
    var freshThisMonthCount: Int { records.filter(\.isFresh).count }

    func load() async { /* call repo, set phase */ }
    func select(_ muscle: String?) { selectedMuscle = muscle }
}
```

**Repository protocol** (defined in BAK-6; mock-backed here):
- `PersonalRecordRepository.personalRecords() async throws -> [PersonalRecord]` — all tracked PRs for the user.

**Mock data.** The in-memory `MockPersonalRecordRepository` seeds the design's `PRS` sample set: Bench press 275 ×1 Chest (fresh, hero), Squat 365 ×1, Deadlift 415 ×1 (fresh), OHP 165 ×3, Pulldown 175 ×8, Incline DB 75 ×8 (fresh) — plus enough entries to total the `8 lifts tracked · 4 new this month` summary shown in the design (the JSX sample has 6; see Open questions). The screen renders entirely against these mocks.

## Out of scope
- Real Supabase wiring / PR computation from `SessionSet` history (BAK-6 / data layer).
- Computing/deriving PRs from logged sessions, including 1RM estimation or per-rep-range bests.
- Navigation from a PR card into Exercise Detail or any drill-down.
- The ⋯ overflow menu contents/actions.
- Editing, deleting, or manually adding PRs.
- Units conversion logic (lb vs kg); the screen displays the unit suffix from settings but conversion math lives elsewhere.
- Widgets / Live Activity (BAK-14) — not applicable to this read-only screen.

## Edge cases
- **Empty PR list:** show empty state, omit hero card and grid.
- **Filter yields nothing:** per-filter empty state; chips remain interactive.
- **No fresh PRs:** sub-line reads `… · 0 new this month`; no `NEW` pill on hero, no accent-2 borders.
- **No hero flagged:** fall back to the highest/first PR in the current filter as the hero card (behavior to confirm — see Open questions).
- **Odd number of grid cards:** last row has a single card (standard grid behavior).
- **Long lift names:** truncate or wrap within the card without breaking layout.
- **Theme switch (Coastal ↔ Mint):** all tokens resolve live; verify hero card `on-accent` text and accent-2 reps remain legible in both palettes.
- **Loading/error transitions:** never show stale data when transitioning to error; retry re-enters loading.

## Open questions
1. The design summary says `8 lifts tracked · 4 new this month`, but the JSX `PRS` sample contains only 6 entries (3 fresh). Should the mock seed match the stated counts (8/4), and are the summary numbers derived from the data or independent fields?
2. On the accent hero card, the reps numeral uses **accent-2**, which appears to conflict with the design-system rule "on an accent-filled card, small highlight text uses `onAccent`, never `accent2`." Is the rep figure an intentional exception (a numeral, not "small highlight text"), or should it be `on-accent`?
3. When no PR is flagged `hero` within a filter, what is the hero-selection rule — heaviest weight, most recent, or simply the first? (The JSX only ever flags one global hero.)
4. Does tapping a PR card navigate anywhere (e.g. Exercise Detail for that lift)? The design shows no tap target; confirm whether cards should be interactive.
5. What defines `fresh` / "new this month" precisely — set within the current calendar month, within the last 30 days, or a server-provided flag? Needed for `freshThisMonthCount`.
6. Where should `PersonalRecord` live and how does it relate to the catalog `Exercise` (and its missing `top`/`pr`/`equipment` fields noted in the Exercise Detail spec)? Coordinate with BAK-6.
7. Units: should weight/reps respect the user's `units` preference (lb/kg) here, and is the stored value canonical (e.g. always lb) with display-time conversion?

## Tests required
**Unit tests — `PersonalRecordsModelTests` (PulseTests):**
- `load()` populates `records` and sets `phase = .loaded` against the mock (AC 1).
- `muscleFilters` returns `All`-equivalent plus distinct muscles in stable order (AC 2).
- `select(muscle)` filters `filtered`/`gridRecords`/`hero` correctly; `select(nil)` clears (AC 3).
- `hero` resolves to the `isHero` record within a filter, with documented fallback (AC 4, edge case).
- `gridRecords` excludes the hero (AC 5).
- `trackedCount` and `freshThisMonthCount` compute the sub-line numbers (AC 1).
- Empty repo result → `phase = .empty` (AC 8).
- Filter with no matches → empty `filtered`, model exposes per-filter empty (AC 9).
- Repository throw → `phase = .error`, no stale records retained (AC 10).

**Acceptance/UI tests — `PersonalRecordsUITests`:**
- Header/eyebrow/sub-line render (AC 1).
- Chip row renders with `All` + per-muscle chips, `All` active by default (AC 2); selecting a chip filters hero + grid (AC 3).
- Hero card shows pill/eyebrow/name/weight/reps, with `NEW` pill only when fresh (AC 4).
- Grid renders one card per non-hero filtered PR with fresh flag + accent-2 border on fresh cards (AC 5, AC 6).
- Loading, empty, and error states each render their explicit UI (AC 7, AC 8, AC 10).
- Palette switch re-renders without hardcoded colors (AC 11).

## Files that will change
- `Pulse/Features/PersonalRecords/PersonalRecordsView.swift` — the screen (View).
- `Pulse/Features/PersonalRecords/PersonalRecordsModel.swift` — the `@Observable` model.
- `Pulse/Core/Models/WorkoutModels.swift` (or new `Pulse/Core/Models/PersonalRecord.swift`) — `PersonalRecord` domain struct. *(Placement coordinated with BAK-6.)*
- `Pulse/Core/Data/PersonalRecordRepository.swift` — repository protocol (`personalRecords()`). *(Coordinated with BAK-6; may be partially defined there.)*
- `Pulse/Core/Data/Mock/MockPersonalRecordRepository.swift` — in-memory mock + sample seed. *(Coordinated with BAK-6.)*
- `Pulse/Features/You/YouView.swift` — wire the `Personal records` NavRow to push this screen. *(Coordinated with BAK-15 You screen.)*
- `PulseTests/PersonalRecordsModelTests.swift` — model unit tests.
- `PulseUITests/PersonalRecordsUITests.swift` — acceptance/UI tests.
- `project.yml` — only if new source groups require it; regenerate via `xcodegen generate` (never hand-edit `.xcodeproj`).

**Dependencies:** Design System tokens/components (BAK-7); repository protocols + mocks and the `PersonalRecord` model addition (BAK-6); the You screen NavRow entry point (BAK-15). No dependency on the active-flow engine or Live Activity/Widgets (BAK-14) for this read-only screen.
