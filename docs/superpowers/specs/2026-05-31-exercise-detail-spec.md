# Exercise Detail — Spec

**Linear:** BAK-11  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview

Exercise Detail is a read-only stack screen reached by tapping an exercise row in the Library → Exercises catalog (`exdetail:<id>`). It gives a lifter a focused, single-exercise progress view: the all-time personal-best top set, a short volume trend, and the last four logged sessions for that exercise. It exists so a lifter can quickly answer "how am I trending on this lift and what did I do last time" without opening a full session.

This is a **UI-first** build: the screen binds to repository protocols backed by in-memory mock implementations with sample data (per BAK-6). No real Supabase wiring is included here.

## User story

As a lifter, I want to open any exercise and see my personal best, my recent volume trend, and my last few sessions for that lift, so that I can gauge my progress and decide what to do next time I train it.

## Acceptance criteria

1. Tapping an exercise row in the Library → Exercises catalog navigates to Exercise Detail for that exercise's id.
2. The top bar eyebrow reads `<MUSCLE GROUP> · <EQUIPMENT>` (uppercase, Geist Mono) and the H1 shows the exercise name.
3. If the exercise has more than one variation, a horizontally scrollable row of variation pills is shown, prefixed with an `All` pill; if the exercise has zero or one variation, no pill row is shown.
4. The default selected variation pill is the first named variation when variations exist; otherwise `All`. The selected pill renders in the `accent` filled style and unselected pills in the outline style.
5. A `Personal Best` accent card is shown **only when** the exercise's top-set weight is greater than zero. It renders a Lockup: the top weight as the Oswald numeral, the most-recent session date as the top label (in `onAccent`), eyebrow `PERSONAL BEST` (or `PERSONAL BEST · TRACKED` when the exercise is a tracked PR), and the bottom label `lbs · top set.`
6. A `VOLUME · LAST 4` eyebrow precedes a 4-bar chart, one bar per recent session ordered oldest→newest; the most-recent (last) bar uses `accent2`, the others use `accent` at reduced opacity; bar heights are scaled to the max volume in the set.
7. A `LAST 4 SESSIONS` eyebrow precedes a list of up to 4 session rows; each row shows the session date and rep line on the left, and the top weight (Oswald) plus volume on the right. The first (most-recent) row is rendered with an `accent` 2px border; the rest use the default faint border.
8. Loading state: while session history is being fetched, the chart and sessions list show a placeholder/skeleton (or are hidden) and no crash occurs; the header and PB card may render as soon as the exercise is loaded.
9. Empty state: if the exercise has no logged session history, the volume chart and `LAST 4 SESSIONS` list show an empty message (e.g. `No sessions logged yet`) instead of bars/rows; the PB card is still hidden if top weight is 0.
10. Error state: if loading the exercise or its history fails, the screen shows a non-crashing error message and does not display stale/placeholder bars as if they were real data.
11. The back affordance in the top bar returns to the Library Exercises view.
12. All colors, spacing, radii, and type come from `Theme` tokens; switching palette (Coastal ↔ Mint) restyles the screen with no layout change.

## Screen / UX behavior

Layout top-to-bottom (grounded in design README §3 and `pulse-app.jsx` `ExerciseDetailScreen`):

- **Top bar:** back chevron (left), eyebrow `<GROUP.uppercased> · <EQUIP>` (Geist Mono uppercase, letter-spacing per token), trailing `⋯` overflow glyph (decorative for now — see Out of scope).
- **H1:** exercise name with a trailing period, Hanken Grotesk, condensed line-height (~0.98), font size ~28.
- **Variation pills:** shown only when `variations.count > 1` (after prepending `All`). Horizontally scrollable, pill radius `999`. Selected = `accent` fill with `onAccent` text; unselected = transparent with `ink-faint` border and `ink-soft` text. Tapping a pill updates the selected variation (see Open questions on whether this re-filters history).
- **Scroll body** (vertical, small inter-item spacing):
  - **Personal Best card** — `accent`-filled card, radius 14–20. Eyebrow `PERSONAL BEST` / `PERSONAL BEST · TRACKED`. Lockup numeral = top weight (Oswald), top label = most-recent session date in `onAccent`, bottom label `lbs · top set.` On this accent card all highlight text uses `onAccent`, never `accent2` (design rule). Hidden when top weight is 0.
  - **`VOLUME · LAST 4`** eyebrow + 4-bar mini chart, bars bottom-aligned, fixed row height (~56). Last bar `accent2` at full opacity; preceding bars `accent` at ~0.55 opacity. Bar top corners rounded.
  - **`LAST 4 SESSIONS`** eyebrow + list of rows. Each row: left `nm` block (date as name, `<repLine> REPS` as sub); right column (top weight in Oswald — `accent` color on the first row, `ink` otherwise — over `<volume> VOL` sub). First row border `accent` width 2; others `ink-faint` width 1.5.

**Navigation:** entered from Library Exercises catalog row tap; back returns there. No outbound navigation from this screen in this feature.

**Sheets:** none in scope for this feature.

## Data & state

New feature folder: `Pulse/Features/ExerciseDetail/`.

`@Observable` model — `ExerciseDetailModel`:

- Inputs: `exerciseID: Exercise.ID` (passed on construction).
- State:
  - `phase: LoadPhase` — `.loading | .loaded | .empty | .error(String)` (or equivalent enum).
  - `exercise: Exercise?`
  - `personalBest: PersonalBest?` (top-set weight + date; nil when none) — see Open questions / model gap below.
  - `sessions: [ExerciseSessionSummary]` — up to 4, most-recent first. Shape: `{ date: String (or Date), repLine: String, topWeight: String, volume: String }` mapped to the row + chart.
  - `variations: [VariationOption]` (computed: `All` + exercise's named variations).
  - `selectedVariationIndex: Int`.
  - Derived: `showsVariationPills` (`variations.count > 1`), `showsPersonalBest` (PB present / top > 0), `maxVolume` for chart scaling.
- Methods: `load()` (async) — calls the repository, populates `exercise` + `sessions`, sets `phase`; `selectVariation(_:)`.

Repository protocols it calls (defined in BAK-6, mock-backed here):

- `ExerciseRepository.exercise(id:) async throws -> Exercise` — fetch the catalog exercise.
- `ExerciseRepository.history(exerciseID:variationID:limit:) async throws -> [ExerciseSessionSummary]` — last N session summaries for the exercise (optionally filtered by variation). The JSX prototype **synthesizes** this from the `top` weight (`synthHistory`); the mock implementation should return realistic sample summaries (4 entries) so the screen renders without real Supabase data.

Mock data: the in-memory `ExerciseRepository` mock seeds the catalog from the design's `EXERCISE_CATALOG` (Chest/Back/Legs/Shoulders/Triceps; e.g. `flat` Flat Machine Chest Press, top 150, variations D-bar/Neutral/Wide) and provides per-exercise sample session summaries. The screen renders entirely against these mocks.

**Domain model gap (note for BAK-6 / dependency):** the current `Exercise` struct in `Pulse/Core/Models/WorkoutModels.swift` has `id, name, muscleGroup, variations, defaultVariationID` but **no** `equipment`, **no** top-set/PB weight (`top`), and **no** `pr` flag — all of which this screen displays. These need to be added to `Exercise` (or surfaced via a separate `ExercisePB`/catalog metadata type and a `PersonalRecord` model). This spec assumes that gap is closed by the data layer; the exact placement is an open question below.

## Out of scope

- The `⋯` overflow menu actions (edit exercise, add to workout, etc.) — glyph only, non-functional.
- Editing or logging from this screen (read-only).
- Real Supabase persistence/queries (deferred to BAK-6).
- Cross-linking to related lifts (that lives in the active-flow History sheet, not here).
- Ranges/time-window selectors beyond the fixed "last 4" window.
- Per-variation PR tracking semantics beyond selecting a pill.
- Live Activity / widget surfaces (BAK-14).

## Edge cases

- **Bodyweight / top == 0** (e.g. `pushup` Tricep Push Up): no Personal Best card; session rows show `bodyweight` instead of a weight; volume may be `—`.
- **No history at all:** show empty message in place of chart + list; do not render zero-height bars as if data.
- **Single or zero variations:** no pill row.
- **Long exercise names / long variation lists:** H1 wraps gracefully; pill row scrolls horizontally; no truncation that hides the selected pill.
- **Volume scaling when all volumes equal or one is zero:** bars use a minimum floor height (per prototype, ~8px floor) so nothing renders invisible.
- **Theme switch mid-screen:** Coastal ↔ Mint restyles tokens only; selected-pill, accent card, accent-2 last bar, and accent first-row border all re-derive from tokens with no layout shift.
- **Unknown / missing exercise id:** model resolves to `.error` (or a sensible fallback) rather than crashing.

## Open questions

1. **Variation filtering:** the prototype lets you select a variation pill but does **not** change the displayed history (history is synthesized from a single `top`). Should selecting a variation actually re-query/filter the PB, chart, and last-4 sessions for that variation, or is the pill purely cosmetic for now? Design does not specify.
2. **Where do equipment, top-set/PB weight, and `pr` live?** The design exposes `equip`, `top`, and `pr` on the catalog exercise, but the current `Exercise` model omits them. Should these be added to `Exercise`, or derived from a separate `PersonalRecord` repository / computed from `SessionSet` history? (Dependency on BAK-6 data layer.)
3. **Real history vs synthesized:** the prototype fakes history from `top` (`synthHistory`). Confirm the production shape of an exercise session summary (what counts as the "rep line" and the "top weight" — heaviest set? working sets only? includes warmups?).
4. **Date format & timezone:** rows show `FRI · MAY 23`-style strings in the prototype. Confirm the canonical format and whether it should be locale-aware.
5. **Units:** weights are shown as `lbs`. Should this screen respect the user's Units preference (LBS/IMPERIAL vs metric) from You → Preferences, and if so does that conversion happen in the repository or the model?
6. **Window size:** "last 4" — is 4 fixed, or should it follow the number of available sessions (e.g. show fewer when <4)?
7. **PB card date semantics:** the prototype uses the most-recent session date as the PB card's top label, not the date the PB was actually set. Is that intentional, or should it show the true PB date?

## Tests required

**Unit tests — `ExerciseDetailModel` (`PulseTests/ExerciseDetail/ExerciseDetailModelTests.swift`):**

- `load()` populates `exercise`, `sessions`, and sets `phase = .loaded` against the mock repository.
- `showsPersonalBest` is true when top weight > 0 and false when 0 (bodyweight exercise).
- `showsVariationPills` is true only when `variations.count > 1`; default `selectedVariationIndex` points at the first named variation when variations exist, else `All`.
- `variations` is `["All"] + namedVariations`.
- `maxVolume` is computed correctly and is never 0 (floor) for scaling.
- Empty history → `phase = .empty` (or sessions empty + empty flag) and no crash.
- Repository throwing → `phase = .error` with a message; no stale data shown.
- `selectVariation(_:)` updates the index (and, depending on Open Q1, re-loads history).
- Sessions are ordered most-recent first and capped at the window size.

**Acceptance / UI tests (`PulseUITests` or equivalent), mapping to acceptance criteria:**

- AC1/AC11: navigate from Library Exercises into Exercise Detail and back.
- AC2: eyebrow and H1 reflect the chosen exercise.
- AC3/AC4: pill row presence and default selection for a multi-variation exercise (`flat`) vs a no-variation exercise (`incline`).
- AC5: PB card present for `flat` (top 150), absent for `pushup` (top 0).
- AC6/AC7: 4 bars and up to 4 session rows render; first bar/row carry the accent-2 / accent emphasis.
- AC8/AC9/AC10: loading, empty, and error states render their respective UI without crashing.
- AC12: toggling palette restyles without layout change (snapshot or token-binding assertion).

## Files that will change

- `Pulse/Features/ExerciseDetail/ExerciseDetailView.swift` — new screen view.
- `Pulse/Features/ExerciseDetail/ExerciseDetailModel.swift` — new `@Observable` model.
- `Pulse/Core/Data/ExerciseRepository.swift` — repository protocol additions (`exercise(id:)`, `history(exerciseID:variationID:limit:)`) and an `ExerciseSessionSummary` type. *(Coordinated with BAK-6; may already be partially defined there.)*
- `Pulse/Core/Data/Mock/MockExerciseRepository.swift` — in-memory mock + sample catalog/history seed data. *(Coordinated with BAK-6.)*
- `Pulse/Core/Models/WorkoutModels.swift` — likely additions to `Exercise` (equipment, PB/top weight, `pr`) or a new PB/record type. *(Resolves Open Q2; coordinated with BAK-6.)*
- Navigation wiring from the Library Exercises catalog row into `ExerciseDetailView(exerciseID:)`. *(File depends on Library feature layout, e.g. `Pulse/Features/Library/…`.)*
- `PulseTests/ExerciseDetail/ExerciseDetailModelTests.swift` — model unit tests.
- `PulseUITests/ExerciseDetailUITests.swift` (or the project's UI test target) — acceptance tests.
- `project.yml` — only if new folders/targets require regeneration via `xcodegen generate` (no hand-editing of the `.xcodeproj`).

**Dependencies:** Design System tokens/components (BAK-7); repository protocols + mocks and domain-model additions (BAK-6). No dependency on the active-flow engine or Live Activity (BAK-14) for this read-only screen.
