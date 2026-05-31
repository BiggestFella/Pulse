# Plan / Calendar Tab — Spec

**Linear:** BAK-12  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview
The Plan tab is the third tab (Today · Library · **Plan** · You) and exists to let a lifter see and manage *when* they train. It offers two views of the same schedule — a month **Calendar** grid and a vertical **Agenda** list — and lets the user assign, replace, clear, or rest-day any non-completed day via a **Schedule** sheet. Tapping today's planned day launches the active workout flow. This feature is built UI-first against mock repositories; real Supabase persistence arrives with the data layer (BAK-6).

## User story
As a lifter, I want to see my training schedule on a calendar (or as an agenda) and assign or change which workout falls on each day, so that I can plan my week ahead and know what's coming next.

## Acceptance criteria
1. The Plan tab shows a `PLAN` top-bar eyebrow and a segmented **Calendar / Agenda** toggle that defaults to **Calendar**; toggling switches the body and persists the selection while the tab is in memory.
2. **Calendar** view renders a `May.` / `2026` month header, a "THIS MONTH" accent summary card showing `{done} / {planned}` and a completion percentage, a Mon-start weekday header row (`M T W T F S S`), and a month grid with correct leading blank cells for the month's first-weekday offset.
3. Each calendar day cell renders by state: `done` (accent fill + onAccent dot), `today` (accent-2 outline), `plan` (faint fill + accent-2 dot), and empty/unscheduled (dashed border, no fill).
4. Tapping a day whose state is `today` launches the active workout flow (callback out of this feature). Tapping any other day (scheduled-not-done, planned, or empty) opens the **Schedule** sheet for that day.
5. Below the grid, the Calendar view shows a highlighted "today" row (eyebrow `WED · MAY 28`, workout name, `N EXERCISES · ~XXM` sub, accent border) that also launches the workout when tapped.
6. **Agenda** view renders a vertical list of upcoming days, each row = day-of-week eyebrow + large Oswald day number + workout row (name + sub); the today entry is emphasized (accent numeral, larger size, accent border) and launches the workout when tapped; rest days render dimmed with no trailing chevron.
7. The **Schedule** sheet shows eyebrow `MAY <day> · 2026` and a title that reflects state: `Completed.` for done days, `Scheduled.` for planned days, `Schedule a day.` for empty days.
8. For a `done` day the Schedule sheet shows the completed workout row (accent border, `DONE`) and offers **no** edit actions (no CLEAR, no picker).
9. For a `plan`/scheduled (non-done) day the Schedule sheet shows the assigned workout row (accent-2 border, `PLANNED`) with a `CLEAR` action, and a `REPLACE WITH` list of saved workouts plus a dashed `Rest day` option.
10. For an empty day the Schedule sheet shows a `PICK A WORKOUT` list of saved workouts plus a dashed `Rest day` option.
11. Assigning a workout (or Rest day) from the sheet updates that day's calendar/agenda state and closes the sheet; clearing a planned day removes its entry and closes the sheet.
12. **Loading state:** while the schedule is loading the body shows a non-interactive placeholder (skeleton/spinner) rather than an empty grid.
13. **Empty state:** if the month has no scheduled days, the grid still renders all day cells as empty/dashed and the summary card reads `0 / 0` (or hides the percentage) — the screen is still usable to assign days.
14. **Error state:** if the schedule fails to load, the body shows an inline error message with a Retry affordance; no crash.
15. All colors/spacing/typography come from `Theme` tokens; the screen renders correctly under both **Coastal** and **Mint** palettes.

## Screen / UX behavior
**Top bar.** Eyebrow `PLAN`. (The JSX repurposes the top-bar right button to toggle the view; in SwiftUI we use the dedicated segmented control below as the source of truth — see Open questions.)

**Segmented toggle.** A pill-shaped two-segment control (`Calendar` / `Agenda`), Geist Mono uppercase labels, the active segment filled `ink` with `bg`-colored label, inactive `inkSoft` on transparent, container bordered `inkFaint` on `surface`. Default `Calendar`.

**Calendar view (scroll).**
- Header row: `May.` (H1, Hanken Grotesk) left, `2026` (Oswald, `inkSoft`) right, baseline-aligned.
- Summary card: `card accent` style. Eyebrow `THIS MONTH`; big Oswald `{done}` with a smaller `/ {planned}` suffix; right-aligned Oswald `{pct}%` in `onAccent`. Highlight text on the accent card uses `onAccent` (never `accent2`), per design rules.
- Weekday header: 7-column grid, `M T W T F S S` (Monday-start), Geist Mono `inkSoft`.
- Day grid: 7-column grid, leading `monthStartOffset` empty cells, then day cells 1…daysInMonth. Cell visuals per state per AC-3. `done`/`plan`/`today` cells show a 4pt dot (onAccent for done, accent2 for today/plan).
- Today row: eyebrow `<DOW> · <MON> <day>`, then a bordered row (accent border, width 2) with a `T` badge, workout name, `N EXERCISES · ~XXM` sub, trailing `→` in accent. Taps launch the workout.

**Agenda view (scroll).** Vertical list of upcoming entries. Each entry: left column = day-of-week eyebrow (accent2 if today, else inkSoft) over a large Oswald day number (accent + larger if today; ink if has workout; inkSoft if rest/empty). Right = bordered row with name + optional sub; today gets accent border + `→`; non-today workout days get a chevron; rest/empty days are dimmed (opacity) with no trailing glyph and are non-interactive.

**Schedule sheet.** Standard sheet chrome (dim backdrop tap-to-close, drag handle, eyebrow + title, ✕). Content per AC-7..10. Saved-workout rows show name + sub with a `+` icon-button (accent border/color); `Rest day` row is dashed with `RECOVERY` sub. Assigning calls back into the model; clearing calls back into the model.

**Navigation.** This screen owns no stack pushes of its own in v1. It emits one outward action — "start today's workout" — wired by the app shell to the active workout flow (BAK-14). The Schedule sheet is presented within the Plan feature.

## Data & state
A single `@Observable` model, `PlanModel`, in `Pulse/Features/Plan/`.

```swift
@Observable final class PlanModel {
    enum ViewMode { case calendar, agenda }
    enum LoadState { case loading, loaded, failed }

    var mode: ViewMode = .calendar
    var loadState: LoadState = .loading

    // calendar
    private(set) var month: MonthContext            // title "May", year 2026, monthStartOffset, daysInMonth
    private(set) var schedule: [Int: ScheduledDay]  // dayOfMonth -> { state, workoutName? }
    private(set) var summary: MonthSummary          // done, planned, pct

    // agenda
    private(set) var agenda: [AgendaEntry]          // { day, dow, name, sub, isToday, isRest }

    // sheet
    var scheduleSheetDay: Int?                       // non-nil = sheet presented
    private(set) var savedWorkouts: [SavedWorkoutRef]

    func load() async { … }                          // schedule + saved workouts
    func selectDay(_ day: Int)                        // today -> onStartWorkout(); else open sheet
    func assign(day: Int, workout: SavedWorkoutRef)   // or .restDay
    func clear(day: Int)
    var onStartWorkout: () -> Void = {}               // wired by app shell
}
```

Supporting view-data types (`MonthContext`, `ScheduledDay`, `DayState{done,today,plan,empty}`, `MonthSummary`, `AgendaEntry`, `SavedWorkoutRef`) live with the model unless they are reused domain types. `ScheduledDay.state` maps from the design's `done | today | plan` plus an `empty` case for unscheduled days.

**Repository dependency (BAK-6).** The model depends only on repository protocols, never Supabase directly:
- A `ScheduleRepository` protocol: `func schedule(forMonth:year:) async throws -> [Int: ScheduledDay]`, `func assign(day:month:year:workoutID:) async throws`, `func clearDay(day:month:year:) async throws`, `func agenda(from:limit:) async throws -> [AgendaEntry]`.
- A `WorkoutLibraryRepository` (or equivalent already defined for Library/BAK-9) exposing saved workouts for the picker: `func savedWorkouts() async throws -> [SavedWorkoutRef]`.

This feature **assumes mock implementations exist** (in-memory, seeded with sample data matching the JSX: 20 done days, day 28 `today` "Chest & Tris", days 29/30 planned "Shoulders" / "Arms · finisher"; agenda for 28→03; `SAVED_WORKOUTS` list of six). Exact protocol names/locations are owned by BAK-6 — see Open questions. The model renders against these mocks for the entire UI-first build.

**Design-system dependency (BAK-7).** All visuals use `Theme` tokens (`accent`, `accent2`, `onAccent`, `ink`, `inkSoft`, `inkFaint`, `surface`, `surface2`, `bg`) and shared components (TopBar eyebrow, Sheet, row, badge, Eyebrow, button styles).

## Out of scope
- Real Supabase persistence / sync (BAK-6 wires the live repositories).
- Launching, running, or any internals of the active workout flow (BAK-14); this feature only emits the "start today" callback.
- Month navigation (prev/next month, paging across months/years) — v1 shows the current month only (see Open questions).
- Creating new workouts/routines from the Schedule sheet (the sheet only assigns from existing saved workouts; the Workout Builder is BAK-13/Library scope).
- Multi-day drag-to-reschedule, recurring schedules, or program auto-population of the calendar.
- Widgets / Live Activities (BAK-14).
- Notifications / reminders for upcoming sessions.

## Edge cases
- **Month-start offset:** correct leading blanks for any first-weekday (Monday-start week). May 2026 starts Friday → offset 4. Must not hardcode the seed offset for the live repo.
- **Done day tapped:** opens a read-only Schedule sheet (`Completed.`) with no edit actions; never launches a workout (only `today` launches).
- **Today already completed vs. pending:** spec assumes a single `today` state that launches the workout. If today is already done, see Open questions on whether it shows `done` or `today`.
- **Clearing a planned day** returns it to `empty` (dashed); a `done` day can never be cleared.
- **Rest day assignment** stores a recovery entry; how it renders in the calendar grid (faint vs. dashed) is unspecified — see Open questions.
- **Empty month:** grid all-dashed, summary `0 / 0`; screen still functional.
- **Loading / error:** body shows placeholder (loading) or inline error + Retry (failed); the toggle remains usable.
- **Theme switching:** switching Coastal↔Mint under You → Palette must recolor all states live (done fill, accent-2 outlines/dots, dashed borders) with no hardcoded hex.
- **Agenda rest/empty rows** are non-interactive and dimmed; only `isToday` rows trigger the start callback.

## Open questions
1. **Top-bar right button:** the JSX overloads the top-bar right icon to toggle Calendar/Agenda *and* renders a `+` icon in Agenda mode. Do we keep a top-bar action at all, or is the segmented control the sole toggle? If the `+` is meaningful, what does it do (quick-schedule? jump to today?)?
2. **Month navigation:** v1 shows only the current month with no prev/next paging. Is single-month acceptable for v1, or is month paging required?
3. **Today-is-done:** when today's workout is already completed, does the day cell show `done` (accent fill) or stay `today` (accent-2 outline)? Does tapping still launch, restart, or open the read-only sheet?
4. **Agenda window:** how many days/how far ahead does Agenda list, and where does the range start (today vs. start of week)? The JSX hardcodes 7 entries (28→03).
5. **Rest-day rendering in the calendar grid:** the JSX assigns rest as `plan` state with name "Rest", so it shows a faint fill + accent-2 dot identical to a planned workout. Is that intended, or should rest days have a distinct visual (e.g., dashed/dimmed like the agenda)?
6. **Saved-workout sub line:** the picker sub shows `N exercises` from `SAVED_WORKOUTS`. Is that derived from the real Workout model's exercise count, or a stored field? (Resolved by BAK-6 repo shape.)
7. **Repository ownership:** does the schedule live on its own `ScheduleRepository`, or is "scheduled day → workout" a field on a Program/Routine the user is following (i.e., is the calendar a *view* of an active routine rather than free-form per-day assignment)? This materially affects assign/clear semantics and is owned by BAK-6.
8. **Persistence of `mode`:** should the Calendar/Agenda selection persist across app launches (UserDefaults), or only in memory for the session?

## Tests required
**Unit tests (`PlanModelTests` in `PulseTests/`), against the mock repositories:**
- `load()` populates `schedule`, `summary`, `agenda`, and `savedWorkouts`, and sets `loadState = .loaded`.
- `load()` failure path sets `loadState = .failed` and leaves the body empty (AC-14).
- Month context: `monthStartOffset` and `daysInMonth` are computed correctly for a known month (e.g., May 2026 → offset 4, 31 days) (AC-2).
- Day-state mapping: a seeded done/today/plan/empty day maps to the expected `DayState` (AC-3).
- `selectDay(28)` (today) invokes `onStartWorkout` and does **not** open the sheet (AC-4).
- `selectDay(29)` (plan) and `selectDay(<empty>)` set `scheduleSheetDay` (AC-4).
- `selectDay(<done>)` opens the sheet in a read-only/`Completed.` configuration (AC-8).
- `assign(day:workout:)` updates the day's state to `plan`, refreshes the summary, and clears `scheduleSheetDay` (AC-11).
- `assign(day:, .restDay)` records a rest entry and closes the sheet (AC-11).
- `clear(day:)` removes a planned entry (→ empty) and closes the sheet; clearing a done day is a no-op / unavailable (AC-9, AC-11, edge case).
- Empty-month load → summary `0 / 0`, all days empty (AC-13).
- `mode` toggling flips between `.calendar` and `.agenda` (AC-1).

**Acceptance / UI tests (`PlanUITests` or snapshot tests) mapping to ACs:**
- AC-1: toggle switches body Calendar↔Agenda; defaults to Calendar.
- AC-2/AC-3: calendar renders header, summary card, weekday row, grid with correct offset and per-state cell visuals.
- AC-4: tapping `today` triggers start; tapping other days presents the Schedule sheet.
- AC-5/AC-6: today row (calendar) and today entry (agenda) are emphasized and launch the workout; rest/empty agenda rows are non-interactive.
- AC-7..10: Schedule sheet title/content differs across completed / scheduled / empty days.
- AC-11: assign and clear update the views.
- AC-12/AC-14: loading placeholder and error+Retry states render.
- AC-15: snapshot under both Coastal and Mint palettes.

## Files that will change
- `Pulse/Features/Plan/PlanView.swift` — replace the placeholder with the real Calendar/Agenda screen + segmented toggle.
- `Pulse/Features/Plan/PlanModel.swift` — new `@Observable` model.
- `Pulse/Features/Plan/CalendarMonthView.swift` — new (month header, summary card, weekday row, day grid, today row).
- `Pulse/Features/Plan/AgendaListView.swift` — new (agenda list).
- `Pulse/Features/Plan/ScheduleSheet.swift` — new (the Schedule drawer).
- `Pulse/Features/Plan/PlanViewData.swift` — new (view-data types: `MonthContext`, `ScheduledDay`, `DayState`, `MonthSummary`, `AgendaEntry`, `SavedWorkoutRef`) unless co-located in `PlanModel.swift`.
- `Pulse/Core/Data/ScheduleRepository.swift` *(coordinate with BAK-6)* — protocol + in-memory mock + sample seed, if not already provided by the data-layer feature.
- `Pulse/App/…` — wire `PlanView`'s `onStartWorkout` callback into the app shell / tab container (small edit; depends on BAK-14 wiring).
- `PulseTests/PlanModelTests.swift` — new unit tests.
- `PulseUITests/PlanUITests.swift` (or `PulseTests/PlanSnapshotTests.swift`) — new acceptance/UI/snapshot tests.
- `project.yml` — only if new files require a target/membership change; regenerate via `xcodegen generate` (never hand-edit `.xcodeproj`).
