# Workout History + Session Detail — Spec

**Linear:** BAK-17  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview

Workout History is a read-only stack screen (reached from You → Workout history) that lists a lifter's past logged sessions, grouped by recency and filterable by program/type/PR. Tapping a session row opens **Session Detail** — a read-only receipt of one completed session: its headline stats (volume, PRs), the full per-exercise log, and actions to re-use the workout (Duplicate / Repeat workout). Together they let a lifter browse what they've done and drill into any single session without entering the active flow.

This is a **UI-first** build: both screens bind to repository protocols backed by in-memory mock implementations with sample data (per BAK-6). No real Supabase wiring is included here.

## User story

As a lifter, I want to browse my past workout sessions and open any one of them to see exactly what I lifted, so that I can review my training history, check what I did last time, and quickly repeat a workout.

## Acceptance criteria

1. Tapping the `Workout history` NavRow in the You tab navigates to the Workout History stack screen.
2. The History top bar eyebrow reads `WORKOUT HISTORY` (uppercase, Geist Mono); the H1 reads `History.`; a sub line reads a session count + since-date (e.g. `183 sessions · since Feb 2024`).
3. A horizontally scrollable filter chip row shows `All`, `PPL`, `One-offs`, `+ PR`; `All` is selected by default and renders in the selected (on) chip style, the others in the off style.
4. Selecting a filter chip updates the displayed sessions: `PPL` shows only program sessions, `One-offs` shows only non-program sessions, `+ PR` shows only sessions that set at least one PR, `All` shows everything. Only one chip is active at a time.
5. Sessions are grouped under recency eyebrows (`THIS WEEK`, `LAST WEEK`, and any further past groups), most-recent first within each group.
6. Each session row shows: a left date block (day-of-week eyebrow over the day-of-month numeral in Oswald), the session name, a `time · volume` sub line (e.g. `58m · 12.4k LBS`), an optional PR badge, and a trailing chevron.
7. Tapping a session row navigates to Session Detail for that session's id.
8. The Session Detail top bar eyebrow reads `<DOW> · <MONTH DAY> · <DURATION>` (e.g. `WED · MAY 21 · 58M`); the H1 is the session name; a sub line reads `<programLabel> · Week <n> · Day <n> · completed`.
9. Session Detail shows a 2-up StatBox row: `VOLUME` (value + `K`/unit + `lbs` sub) and `PR` (e.g. `+1` with the PR source as sub), where the PR box uses the accent-bordered style.
10. A `LOG` eyebrow precedes a list of numbered exercise rows; each row shows an index badge, the exercise name, a set-detail sub line (e.g. `15·12·10·8 @ 140lb`, `3 rounds`, `To failure · 18`), an optional PR tag, and a trailing per-exercise volume figure (e.g. `5.7k`, `BW`).
11. Session Detail shows a footer with a secondary `Duplicate` button and a primary `Repeat workout →` button.
12. Loading state: while history (or a session) is being fetched, the list/detail shows a placeholder/skeleton (or is hidden) and does not crash; static chrome (top bar, H1) may render immediately.
13. Empty state: if there are no sessions (or no sessions match the active filter), History shows an empty message (e.g. `No sessions yet` / `No sessions match this filter`) instead of group eyebrows + rows.
14. Error state: if loading fails, each screen shows a non-crashing error message and does not render stale/placeholder rows as if they were real data.
15. The back affordance returns to the previous screen (History → You; Session Detail → History).
16. All colors, spacing, radii, and type come from `Theme` tokens; switching palette (Coastal ↔ Mint) restyles both screens with no layout change.

## Screen / UX behavior

Grounded in design README §8 (Workout History) and §9 (Session Detail), and `pulse-app.jsx` `HistoryScreen` / `SessionDetailScreen`.

### Workout History

- **Top bar:** back chevron (left), eyebrow `WORKOUT HISTORY` (Geist Mono uppercase, letter-spacing per token), trailing `⋯` overflow glyph (decorative — see Out of scope).
- **H1:** `History.` (Hanken Grotesk, size ~30).
- **Sub line:** `<n> sessions · since <month year>` in `ink-soft`.
- **Filter chips:** horizontally scrollable row `All / PPL / One-offs / + PR`. Selected chip = `accent`-style on chip; unselected = off/outline style. Single-select.
- **Scroll body:** recency-grouped. Group eyebrow (`THIS WEEK`, `LAST WEEK`, …) then rows. Each row (`row` style, padding ~`10px 12px`):
  - **Date block** (min width ~46): day-of-week eyebrow (~9pt) over the day-of-month numeral (Oswald). The most-recent group's numerals render heavier/`ink`; older groups render lighter/`ink-soft` (per prototype's two render styles).
  - **Name block:** `nm-name` (session name) over `nm-sub` (`<time> · <volume> LBS`).
  - **PR badge** when the session set a PR.
  - **Trailing chevron.**
- **Interaction:** row tap → Session Detail (`go("session-detail")` in the prototype, parameterized by session id here). Filter chip tap re-filters in place.

### Session Detail (read-only)

- **Top bar:** back chevron, eyebrow `<DOW> · <MONTH DAY> · <DURATION>` (e.g. `WED · MAY 21 · 58M`), trailing `⋯` overflow glyph (decorative).
- **H1:** session name (e.g. `Chest & Tris.`).
- **Sub line:** `<programLabel> · Week <n> · Day <n> · completed`.
- **Stat boxes:** 2-column grid. `VOLUME` box (value + unit `K` + `lbs` sub). `PR` box rendered with the **accent-bordered** StatBox variant; value = `+<prCount>`, sub = PR source (e.g. `Flat machine`).
- **`LOG` eyebrow** + scrollable list of numbered rows. Each row: index badge (~20pt, accent badge style), `nm-name` (~13pt) over `nm-sub` (~9pt, the set detail), optional PR tag, trailing per-exercise volume figure (`end` style, ~14pt). Supersets render as a single combined row (e.g. `Tri / Lat superset`, sub `3 rounds`). Failure sets render as `To failure · <reps>`; bodyweight volume shows `BW`.
- **Footer:** flex row — secondary `Duplicate` (sm) + primary `Repeat workout →` (sm, flex-1). Both use design-system `Btn` styles (pill, 2px ink border, hard shadow).

**Navigation:** History entered from You → Workout history NavRow; back returns to You. Session Detail entered from a History row; back returns to History. The footer actions (`Duplicate` / `Repeat workout`) target the active flow / builders — see Out of scope + Open questions for their wiring boundary.

**Sheets:** none in scope for this feature.

## Data & state

New feature folders: `Pulse/Features/WorkoutHistory/` and `Pulse/Features/SessionDetail/`.

### `@Observable` model — `WorkoutHistoryModel`

- State:
  - `phase: LoadPhase` — `.loading | .loaded | .empty | .error(String)`.
  - `sessions: [SessionSummary]` — all loaded summaries, most-recent first.
  - `selectedFilter: HistoryFilter` — `.all | .program | .oneOff | .pr` (default `.all`).
  - `headerCount: Int` / `sinceLabel: String` — for the sub line.
  - Derived: `filteredGroups: [SessionGroup]` — sessions filtered by `selectedFilter`, then bucketed into recency groups (`THIS WEEK`, `LAST WEEK`, older) with a display label each.
  - Derived: `isEmpty` (no sessions match the active filter).
- Methods: `load() async` — calls the repository, populates `sessions` + header fields, sets `phase`; `select(_ filter: HistoryFilter)` — re-derives groups (no re-fetch needed if all sessions are in memory).

`SessionSummary` shape (mapped to a row): `{ id, dayOfWeek: String, date: Date, dayNumber: String, name: String, durationLabel: String, volumeLabel: String, hasPR: Bool, isProgram: Bool }`.

### `@Observable` model — `SessionDetailModel`

- Inputs: `sessionID: WorkoutSession.ID` (passed on construction).
- State:
  - `phase: LoadPhase`.
  - `session: SessionDetail?` — `{ dateEyebrow: String, name: String, subLine: String, volumeLabel, volumeUnit, prCount: Int, prSource: String?, log: [LogRow] }`.
  - `LogRow` = `{ name: String, detail: String, volumeLabel: String, hasPR: Bool }`.
- Methods: `load() async` — fetches the session detail; `duplicate()` / `repeatWorkout()` — invoke the relevant action (boundary in Open questions).

### Repository protocols (defined in BAK-6, mock-backed here)

- `SessionRepository.recentSessions(limit:) async throws -> [SessionSummary]` — session summaries, most-recent first, for the History list.
- `SessionRepository.session(id:) async throws -> SessionDetail` — full read-only detail for one session.

Mock data: the in-memory `SessionRepository` mock seeds summaries from the design's `RECENT` array (`Legs`/`Back & Bis`/`Arms`/`Shoulders`/`Chest & Tris`, with `pr:true` on two of them) and the `SessionDetailScreen`'s hard-coded `Chest & Tris` log (Flat Machine Press `15·12·10·8 @ 140lb`, … Tricep Pushup `To failure · 18` `BW`). Both screens render entirely against these mocks.

**Domain model gap (note for BAK-6 / dependency):** the current `WorkoutSession` in `Pulse/Core/Models/WorkoutModels.swift` has `workoutID, startedAt, endedAt, sets: [SessionSet]` but **no** computed/stored display fields these screens need — name, program label / week / day, total volume, PR count + PR source, per-exercise rollups, and the program-vs-one-off flag used by filters. These must be added to the model or surfaced via a summary/detail projection produced by the data layer. This spec assumes that gap is closed by BAK-6; exact placement is an open question below.

## Out of scope

- The `⋯` overflow menu actions on either screen — glyph only, non-functional.
- Editing or deleting a past session (read-only).
- The actual behavior of `Duplicate` and `Repeat workout` (creating a draft workout / launching the active flow) — wired to the builders/active-flow features (BAK-14 and builders), not implemented here. These specs only render the buttons and expose model hooks.
- Real Supabase persistence/queries (deferred to BAK-6).
- Pagination / infinite scroll of very long history (see Open questions).
- Search within history.
- Per-exercise drill-in from the Session Detail log (no row tap navigation here).
- Live Activity / widget surfaces (BAK-14).

## Edge cases

- **No sessions at all:** History shows an empty message in place of groups/rows; the sub line either reports `0 sessions` or is suppressed (Open question).
- **Filter yields no matches:** show a filter-specific empty message; do not show empty group eyebrows.
- **All sessions fall in one recency bucket:** only that group eyebrow renders; no empty `LAST WEEK` header.
- **Session with no PR:** History row omits the PR badge; Session Detail PR box shows `+0` / `—` (Open question on exact copy) and no PR source.
- **Bodyweight / failure exercises in the log:** volume renders `BW`; detail renders `To failure · <reps>`.
- **Superset entries in the log:** rendered as one combined row (`… superset`, `N rounds`), not split into A/B.
- **Long session names / long log lists:** H1 wraps gracefully; the LOG list scrolls; no truncation that hides the volume figure.
- **Theme switch mid-screen:** Coastal ↔ Mint restyles tokens only (selected chip, accent PR StatBox border, PR badges, buttons) with no layout shift.
- **Unknown / missing session id:** `SessionDetailModel` resolves to `.error` (or a sensible fallback) rather than crashing.
- **Recency bucketing across week/timezone boundaries:** "this week" / "last week" must be computed against a defined week-start and the user's calendar (Open question).

## Open questions

1. **Filter source of truth:** `PPL`, `One-offs`, `+ PR` — is `PPL` literally "matches the active program name" or "any program-backed session"? The prototype hard-codes the chips. Confirm whether the program chips are dynamic (one per program the lifter has run) or a fixed set.
2. **Recency grouping rule:** prototype hard-codes `THIS WEEK` (first 2) / `LAST WEEK` (rest). Confirm the real bucketing (calendar week vs rolling 7 days, week-start day, and what groups exist beyond `LAST WEEK` — e.g. month headers for older sessions).
3. **`Duplicate` vs `Repeat workout` semantics:** what does each do? (Duplicate = create an editable copy in the library? Repeat = launch the active flow pre-loaded with this workout?) And where does control hand off — builders, active flow, or both?
4. **Domain model placement (BAK-6):** where do session display fields live — computed on `WorkoutSession`, on a stored summary, or projected by the repository? What determines `isProgram` for the One-offs filter?
5. **PR box copy when prCount == 0:** does the PR StatBox still render (e.g. `+0` / `None`), or is it replaced/hidden?
6. **Per-exercise volume + set-detail derivation:** the prototype hard-codes strings. Confirm how `15·12·10·8 @ 140lb`, `3 rounds`, and per-exercise `5.7k` are computed from `SessionSet`s (working sets only? rounding? how supersets roll up).
7. **Units:** weights/volumes shown as `lbs`/`K LBS`. Should both screens respect the You → Preferences Units setting, and does conversion happen in the repository or the model?
8. **Date/duration formatting & locale:** confirm canonical formats for the History date block, the Session Detail eyebrow (`WED · MAY 21 · 58M`), and whether they are locale-aware.
9. **History length / pagination:** with `183 sessions`, is the full list loaded at once or paged? `recentSessions(limit:)` assumes a cap — confirm the intended window and whether older groups load on demand.
10. **Session count + since-date source:** are `183 sessions` / `since Feb 2024` aggregate stats from the repository, or derived from the loaded list?

## Tests required

**Unit tests — `WorkoutHistoryModel` (`PulseTests/WorkoutHistory/WorkoutHistoryModelTests.swift`):**

- `load()` populates `sessions` and sets `phase = .loaded` against the mock repository; sessions are ordered most-recent first.
- `selectedFilter` defaults to `.all`.
- `select(.pr)` yields only sessions with `hasPR == true`; `select(.program)` only program sessions; `select(.oneOff)` only non-program; `select(.all)` restores everything.
- `filteredGroups` buckets sessions into the correct recency groups with correct group labels and per-group ordering.
- A filter with no matches sets `isEmpty` / `phase = .empty` and produces no groups, without crashing.
- Empty repository → `phase = .empty`; repository throwing → `phase = .error` with a message and no stale data.

**Unit tests — `SessionDetailModel` (`PulseTests/SessionDetail/SessionDetailModelTests.swift`):**

- `load()` populates `session` and sets `phase = .loaded` for a known mock id.
- `log` rows preserve order and map detail/volume/PR fields correctly (including a `BW` / `To failure` row and a superset row).
- `prCount == 0` path renders the agreed PR-box state (per Open Q5) without crashing.
- Unknown session id → `phase = .error` (or fallback), no crash.
- `duplicate()` / `repeatWorkout()` invoke their hooks (stubbed/spy in mock) without performing real navigation in this feature.

**Acceptance / UI tests (`PulseUITests` or equivalent), mapping to acceptance criteria:**

- AC1/AC15: navigate You → Workout history → (row) → Session Detail and back through both.
- AC2/AC3: eyebrow, H1, sub line, and the default-selected filter chip render.
- AC4: selecting `+ PR` shows only PR sessions; selecting `All` restores the full list.
- AC5/AC6: grouped eyebrows and row anatomy (date block, name, sub, PR badge, chevron) render.
- AC7: tapping a row opens the matching Session Detail.
- AC8/AC9/AC10/AC11: Session Detail eyebrow, stat boxes (accent PR box), LOG rows, and footer buttons render.
- AC12/AC13/AC14: loading, empty (no sessions / filter-empty), and error states render without crashing.
- AC16: toggling palette restyles both screens without layout change (snapshot or token-binding assertion).

## Files that will change

- `Pulse/Features/WorkoutHistory/WorkoutHistoryView.swift` — new History screen view.
- `Pulse/Features/WorkoutHistory/WorkoutHistoryModel.swift` — new `@Observable` model.
- `Pulse/Features/SessionDetail/SessionDetailView.swift` — new Session Detail screen view.
- `Pulse/Features/SessionDetail/SessionDetailModel.swift` — new `@Observable` model.
- `Pulse/Core/Data/SessionRepository.swift` — repository protocol (`recentSessions(limit:)`, `session(id:)`) plus `SessionSummary` / `SessionDetail` / `LogRow` projection types. *(Coordinated with BAK-6; may already be partially defined there.)*
- `Pulse/Core/Data/Mock/MockSessionRepository.swift` — in-memory mock + sample summaries/detail seeded from `RECENT` and the prototype log. *(Coordinated with BAK-6.)*
- `Pulse/Core/Models/WorkoutModels.swift` — additions to `WorkoutSession` (display/name/program/week/day/volume/PR fields) or a new summary/detail type. *(Resolves Open Q4; coordinated with BAK-6.)*
- Navigation wiring from the You tab `Workout history` NavRow into `WorkoutHistoryView`, and from a History row into `SessionDetailView(sessionID:)`. *(Files depend on the You feature + app navigation layout, e.g. `Pulse/Features/You/…` and the app shell.)*
- `PulseTests/WorkoutHistory/WorkoutHistoryModelTests.swift` and `PulseTests/SessionDetail/SessionDetailModelTests.swift` — model unit tests.
- `PulseUITests/HistorySessionDetailUITests.swift` (or the project's UI test target) — acceptance tests.
- `project.yml` — only if new folders/targets require regeneration via `xcodegen generate` (no hand-editing of the `.xcodeproj`).

**Dependencies:** Design System tokens/components (BAK-7); repository protocols + mocks and domain-model additions (BAK-6). The footer actions' real behavior depends on the active-flow / builders work (BAK-14 + builder features) and is out of scope here — these read-only screens do not otherwise depend on the session engine.
