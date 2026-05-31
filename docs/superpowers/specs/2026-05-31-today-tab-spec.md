# Today Tab — Spec
**Linear:** BAK-9  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview
The Today tab is the app's home screen and the first tab in the bottom tab bar (Today · Library · Plan · You). Its single job is to answer "what do I do right now?": it surfaces today's prescribed workout in a bold accent hero card with a one-tap **Start →**, shows the current week's progress as a 7-dot strip, and offers a tap-through recap of yesterday's session. This feature delivers the Today screen UI bound to repository protocols backed by in-memory mocks; real Supabase wiring lands in BAK-6, and the active-workout flow that **Start →** launches lands in BAK-14.

## User story
As a lifter, I want to open the app and immediately see today's workout, my week's progress, and how yesterday went, so that I can start training in one tap without hunting through menus.

## Acceptance criteria
1. The Today tab renders as the default/first tab and uses a `NavigationStack`; switching away and back resets its navigation path (per the global navigation model).
2. The top bar shows a Geist Mono date eyebrow for the current day (format `WED · MAY 28`) and a trailing `⋯` overflow glyph.
3. A greeting H1 (`Hey, <firstName>.`) renders on the leading edge with the user's streak count on the trailing edge as an Oswald numeral in `accent2` with a small Hanken `D` suffix (e.g. `27D`), baseline-aligned with the H1.
4. The hero card renders on an `accent` fill with: an eyebrow (`TODAY · <programLabel> · WEEK <n>`), a Lockup (giant Oswald numeral = today's exercise count, top mono label = `Day <n>`, bottom bold = workout name), a footer eyebrow (`<count> EXERCISES · <est>`), and a dark **Start →** button (fill `ink`, text `bg`).
5. Tapping **Start →** invokes the start-workout callback for today's workout (in this feature, the callback is a no-op stub or simple navigation hook; the actual active flow is BAK-14).
6. The week strip renders exactly 7 cells keyed by per-day state: `done` (accent fill, `onAccent` text, accent border), `today` (transparent, 2px `accent2` border), `plan` (transparent, faint `inkFaint` border), `rest` (transparent, dashed `inkFaint` border, dimmed opacity).
7. The week strip header shows `THIS WEEK` (leading) and `<doneCount> OF <plannedCount> DONE` (trailing), where `plannedCount` excludes rest days and `doneCount` counts `done` cells.
8. A `YESTERDAY` recap row renders the most recent prior session (name + sub line `<time> · <volume> · <prSummary>`) and is tappable; tapping pushes the Session Detail screen (Session Detail itself is out of scope here — push target is a placeholder/stub).
9. **Loading state:** while the model fetches data, the screen shows a non-blocking loading treatment (skeleton or spinner) and no stale/blank hero.
10. **Empty / rest-day state:** when there is no workout scheduled today (e.g. a rest day or program gap), the hero card shows a rest/empty treatment instead of a Start button (exact copy is an open question — see Open questions).
11. **Error state:** if the repository call fails, the screen shows a recoverable error treatment (message + retry affordance) rather than crashing or showing partial data.
12. All colors, spacing, radii, and type come from `Theme` tokens; switching palette (Coastal ↔ Mint) under You re-skins the screen instantly with no hardcoded values and no background flash.

## Screen / UX behavior
Layout top-to-bottom, inside the Today `NavigationStack` root:

- **Top bar:** date eyebrow (Geist Mono, uppercase, `inkSoft`, `.16em` tracking) leading; `⋯` icon button trailing (icon-button press behavior per Design System — `translateY(1px)` on press only). The `⋯` action is unspecified in the design (see Open questions) — render the glyph but treat tap as inert/placeholder.
- **Greeting row:** baseline-aligned `HStack` — H1 `Hey, <firstName>.` (Hanken 800, ~28–32pt) leading; streak numeral trailing (Oswald 700 ~26pt, `accent2`, `lineHeight ~.85`) with a small Hanken `D` suffix (~10pt, opacity ~.7).
- **Scroll body:**
  - **Hero card:** radius ~20, `accent` fill, padding ~18. Eyebrow `TODAY · <programLabel> · WEEK <week>` at ~.85 opacity. Lockup composition (numeral `onAccent`; top mono label = `Day <day>`; bottom bold Hanken = workout name, which may wrap, e.g. `Chest & Tris.`). Footer `HStack`: eyebrow `<exerciseCount> EXERCISES · <est>` (~.85 opacity) leading; **Start →** small button trailing. The Start button is a special inverted variant (fill `ink`, text `bg`, `2px solid ink`) — note this is the one place a button is filled `ink` rather than `accent`. On accent fills, any small highlight text uses `onAccent`, never `accent2`.
  - **Week strip:** header `HStack` with `THIS WEEK` and `<done> OF <planned> DONE` eyebrows. Below: 7 equal-flex cells (`aspectRatio ~.82`, radius ~8) showing each day's letter (Geist Mono). State styling per AC #6. Cells are display-only in this feature (no tap target specified in the design).
  - **Yesterday recap:** `YESTERDAY` eyebrow, then a single row (`surface`/row style, radius ~14) showing `name` + sub line; trailing chevron. Whole row is tappable → pushes Session Detail. Row is rendered at ~.85 opacity per the prototype.
- **Transitions:** screen mount uses the standard fade+rise (`fadein`, .28s, +6pt). Tab switches re-trigger via the tab/path identity.
- **Navigation:** this is a tab root; the only outbound navigation is the Yesterday row → Session Detail push and the Start → callback (active flow, BAK-14). Both targets are stubs in this feature.

This screen depends on the Design System (BAK-7) for `Theme`, the Lockup view, the pressable `ButtonStyle`, eyebrow/H1/numeral text styles, and the row component. It depends on the data-layer repository protocols + mocks (BAK-6).

## Data & state
A single `@Observable` model, `TodayModel`, in `Pulse/Features/Today/`. It loads on appear and exposes view-ready state:

```swift
@Observable final class TodayModel {
    enum Phase { case loading, loaded, empty, error }
    private(set) var phase: Phase = .loading

    private(set) var dateEyebrow: String = ""      // "WED · MAY 28"
    private(set) var greetingName: String = ""     // "Alex"
    private(set) var streak: Int = 0               // 27

    private(set) var today: TodayWorkoutCard?      // nil on rest/empty day
    private(set) var week: [WeekDayCell] = []      // exactly 7
    private(set) var yesterday: SessionRecap?      // nil if none

    var doneCount: Int { week.filter { $0.state == .done }.count }
    var plannedCount: Int { week.filter { $0.state != .rest }.count }

    func load() async { … }                        // sets phase + fields
    func startTodaysWorkout() { … }                // BAK-14 hook (stub)
    func openYesterday() { … }                     // pushes Session Detail (stub)
}
```

View-model value types (Today-local view models projected from `Core/Models`):
- `TodayWorkoutCard { programLabel, week, day, name, exerciseCount, est }` (e.g. `PPL`, `4`, `23`, `Chest & Tris`, `7`, `~60 min`).
- `WeekDayCell { dayLetter, label, state: .done|.today|.plan|.rest }`.
- `SessionRecap { name, subline }` (e.g. `Legs`, `71M · 18.7K LBS · +1 PR`).

**Repository calls (protocols from BAK-6, backed by mocks):**
- A program/schedule repository to fetch today's prescribed workout + the current 7-day week strip (e.g. `WorkoutRepository.todaysWorkout()` and `.currentWeek()`).
- A session/history repository for the most recent completed session (e.g. `SessionRepository.mostRecentSession()`).
- A user/profile repository for `firstName` and `streak` (e.g. `UserRepository.currentUser()` / `.streak()`).

Exact protocol method names are owned by BAK-6; this spec assumes mock implementations returning the sample data below. The model must access data ONLY through repositories (never Supabase directly), injected via the initializer for test substitution.

**Mock sample data** (mirrors `pulse-app.jsx`):
- Today's workout = `Chest & Tris`, `PPL`, week 4, day 23, 7 exercises, `~60 min`.
- Week = `[M Chest&Tris done, T Back&Bis done, W Legs done, T Shoulders today, F Arms·finisher plan, S Rest rest, S Rest rest]` → header reads `3 OF 5 DONE`.
- Yesterday = `Legs`, `71M · 18.7K LBS · +1 PR`.
- User = name `Alex`, streak `27`, date eyebrow `WED · MAY 28`.

## Out of scope
- The active workout flow that **Start →** launches (pre-workout, active set, rest, summary) — BAK-14.
- The Session Detail screen the Yesterday row pushes to — separate feature; here it is a push to a stub/placeholder.
- Real Supabase repositories and persistence — BAK-6 (this feature uses mocks only).
- Live Activity / Dynamic Island / widget timer — BAK-14-dependent, not on this screen.
- The `⋯` overflow menu contents and any settings actions.
- Week-strip cell tap interactions (the design specifies display-only cells; calendar editing lives in the Plan tab).
- Streak computation logic, PR detection, and volume aggregation (consumed as pre-computed values from repositories).
- The other three tabs and the global tab bar chrome (assumed provided by the app-shell feature).

## Edge cases
- **Rest day / no workout today:** `today == nil` → hero renders an empty/rest treatment with no Start button (copy TBD — Open questions).
- **No prior session:** `yesterday == nil` → omit the `YESTERDAY` section entirely (do not render an empty row).
- **Streak of 0:** render `0D` (or hide — Open questions); must not crash or show blank.
- **Plan with zero planned days this week** (all rest): header should read `0 OF 0 DONE`; avoid divide-by-zero in any percentage display (none currently shown).
- **Long workout names** (e.g. `Active recovery`): Lockup bottom label must wrap/scale and not clip the hero card.
- **Week array not exactly 7:** treat as a data/error condition; do not render a malformed strip (render error or clamp — Open questions).
- **Theme switch (Coastal ↔ Mint):** all tokens re-resolve instantly; no hardcoded color survives the switch; no background-color flash (don't animate the background on palette change).
- **Repository latency/failure:** loading shows skeleton; failure shows retry; a slow load must not leave a half-populated hero.
- **Dynamic Type / accessibility:** Oswald numerals and eyebrows must remain legible; respect accessibility text sizes without breaking the hero layout (verify against largest supported size).

## Open questions
1. What does the `⋯` top-bar overflow menu do on Today? (Not specified in the design.)
2. What is the rest-day / no-workout-today hero treatment — exact copy and whether it offers any CTA (e.g. "Rest day" vs "Browse library")?
3. Greeting name source and fallback: full name vs first name, and what to show if the user has no name set?
4. Is the streak `D` suffix always days, and what is shown at streak 0 — `0D` or hidden?
5. Date eyebrow format and timezone: is it always device-local current date, and does the abbreviation always uppercase (`WED · MAY 28`)?
6. Should the week strip reflect a Monday-start week (Plan/Calendar is explicitly Mon-start) and how does it align with the 7 letters in the prototype (`M T W T F S S`)?
7. Does tapping a week-strip cell do anything, or is it strictly display-only? (Prototype cells have no handler.)
8. Pull-to-refresh: should the Today scroll support manual refresh, or is appear-time load sufficient?
9. Units in the yesterday/recap sub line — are `LBS`/volume strings pre-formatted by the repository or formatted in the view (affects mock shape and the units setting under You)?

## Tests required
**Unit tests — `TodayModelTests` (PulseTests):**
- `load()` sets `phase = .loaded` and populates `dateEyebrow`, `greetingName`, `streak`, `today`, `week` (count 7), and `yesterday` from a mock repo with sample data.
- `doneCount` / `plannedCount` compute correctly from the sample week (`3` and `5`).
- Rest-day mock (no today's workout) → `phase == .empty` (or `today == nil` with loaded phase, per resolved design) and no Start affordance state.
- No-prior-session mock → `yesterday == nil`.
- Repository failure → `phase == .error`; a subsequent successful `load()` recovers to `.loaded`.
- `startTodaysWorkout()` invokes the injected start callback exactly once with today's workout identity.
- `openYesterday()` triggers the Session Detail navigation hook only when `yesterday != nil`.
- All-rest week mock → `plannedCount == 0`, `doneCount == 0`, no crash.

**Acceptance / UI tests (map to acceptance criteria):**
- AC2/AC3: date eyebrow, greeting, and streak numeral are present with expected text from mock data.
- AC4/AC5: hero card shows exercise-count numeral, `Day 23`, workout name, footer, and a **Start →** button; tapping it triggers the start hook.
- AC6/AC7: week strip renders 7 cells and header `3 OF 5 DONE` for sample data.
- AC8: tapping the Yesterday row pushes Session Detail (asserts navigation to the stub target).
- AC9/AC11: loading shows skeleton; injected-failure mock shows retry.
- AC10: rest-day mock shows the empty hero treatment (no Start).
- AC12: toggling palette between Coastal and Mint re-skins without crash (snapshot in both themes if snapshot infra exists).

## Files that will change
- `Pulse/Features/Today/TodayView.swift` — the screen (View).
- `Pulse/Features/Today/TodayModel.swift` — the `@Observable` model.
- `Pulse/Features/Today/TodayViewModels.swift` — Today-local view-model value types (`TodayWorkoutCard`, `WeekDayCell`, `SessionRecap`) if not colocated in the model file.
- `Pulse/Core/Data/` — repository protocol method additions/mocks consumed here are owned by BAK-6; this feature only references them (no new files expected unless a Today-specific protocol is introduced).
- `Pulse/App/` — register the Today tab in the tab bar / app shell if not already wired (root tab root + `NavigationStack`).
- `PulseTests/TodayModelTests.swift` — unit tests for the model.
- `PulseUITests/TodayTabTests.swift` — acceptance/UI tests mapping to the acceptance criteria.
- `project.yml` — only if new files require target membership wiring; regenerate via `xcodegen generate` (never hand-edit `.xcodeproj`).
