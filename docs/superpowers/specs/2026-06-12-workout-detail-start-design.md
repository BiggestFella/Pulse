# Workout Detail + Start — Design

**Date:** 2026-06-12
**Status:** Approved (design) — pending implementation plan
**Related:** Follow-up to the BAK-27 active-flow / library work.

## Problem

A user can build a workout in the Library (the builder works), but there is **no
way to open a saved workout and run it**. In the Library, tapping a workout row
calls `onOpenWorkout`, which is a **no-op** in both `LibraryView` and
`FolderDetailView`. There is no workout-detail screen and no "Start" affordance
that launches the active session with a *chosen* workout.

The engine and data access already exist and work:
- `ActiveWorkoutModel.startWorkout(_ w: Workout)` runs any hydrated `Workout`.
- `WorkoutRepository.fetchWorkout(id:)` / `fetchWorkouts()` return fully
  hydrated workouts (exercises → variation + sets) on the live (Supabase) path.
- The active session takes over the whole screen at the **app-shell** level
  (`AppShell.shell` swaps to `ActiveWorkoutFlowView` when `session.isActive`).

The gap is purely the connection: **Library → view a workout → Start it.**

## Goal

Let a user tap a saved workout in the Library, see its contents on a detail
screen, and start it — launching the existing active-session flow with that
workout.

## Non-goals (this spec)

- **Edit / Delete / Schedule-to-a-day** from the detail screen — these are the
  agreed **next** increment ("scope C") and get their own spec/plan. The detail
  screen is built so they can be added to a toolbar/menu without restructuring.
- Wiring **Today** and **Plan** to real schedule data — they keep their current
  behavior for now.
- Persisting a "last started" workout, search, or reordering.

## User story & acceptance criteria

> As a user, I open a workout I built and start it, so I can train and log it.

1. Tapping a workout row in the Library (top level **or** inside a folder) opens
   a **Workout Detail** screen.
2. The screen shows the workout name and each exercise with its variation and a
   set summary (e.g. *"4 sets · 12·10·8·6"*).
3. A prominent **Start workout** button launches the active session for that
   workout; the app takes over full-screen and runs the existing flow.
4. If the workout has **no exercises**, Start is disabled with a short hint
   (covers the empty duplicate "Legs B" under the *Test* program).
5. Logged sets persist against that workout's session (existing active-flow
   behavior — sessions/PR/history already handle this).

## Architecture decision — how "Start" reaches the session

**Chosen: callback threading.** `LibraryView` gains an
`onStartWorkout: (Workout) -> Void`, supplied by `AppShell`, which calls
`session.startWorkout(_:)`. The callback is threaded down through the Library
navigation to the detail screen.

This matches the **existing pattern** — `TodayModel.onStartWorkout` and
`PlanView(onStartWorkout:)` already hand starting up to the shell the same way —
so it is consistent, explicit, and unit-testable.

Rejected alternatives:
- *Session in the SwiftUI environment* — couples Library views to the engine and
  diverges from the established callback pattern.
- *Route/"pending start" state observed by AppShell* — more moving parts for no
  benefit at this scope.

## Components

### `WorkoutDetailModel` (`@Observable`, `Features/Library/`)
- Input: the workout **id** + display **name** (carried by the route), the
  `WorkoutRepository`, and the `onStart` callback. (The route is `Hashable`, so
  it carries the id/name rather than the non-`Hashable` `Workout`.)
- Loads the workout via `fetchWorkout(id:)`. A missing or failed fetch sets
  `loadState = .error` (Start disabled); the user can go back and re-open.
- Exposes: title; an ordered list of display rows (exercise name, variation
  name, set-count + rep summary); `canStart` (true only once loaded with ≥1
  exercise).
- `start()` invokes `onStart(workout)` when `canStart`; otherwise a no-op.

### `WorkoutDetailView` (`Features/Library/`)
- Header: workout name (+ exercise count).
- List of exercise rows (Theme tokens only — Hanken/Oswald/Geist per design system).
- Sticky **Start workout** primary button; disabled with a hint when `!canStart`.
- Toolbar left intentionally roomy for the future Edit/Delete/Schedule menu (C).

### Navigation
- Add `LibraryRoute.workoutDetail(id: UUID, name: String)` (the route is
  `Hashable`, so it carries id + name; the model fetches the workout by id).
- Wire the no-op `onOpenWorkout` in **`LibraryView`** and **`FolderDetailView`**
  to push `.workoutDetail`.

### Shell wiring
- `LibraryView(onStartWorkout:)` new parameter; `AppShell` passes
  `{ workout in session.startWorkout(workout) }`.
- No change to the active flow itself — it opens on its existing pre-workout
  phase and runs as today.

## Data & edge cases

- The model fetches the workout by id via `fetchWorkout(id:)` (fully hydrated on
  the live path).
- Empty workout → `canStart == false`, Start disabled with a hint.
- A missing/failed fetch → `loadState = .error`, Start disabled; the user can go
  back and re-open the workout.

## Testing

- **Unit (`PulseTests`):** `WorkoutDetailModel` — loads a workout and exposes the
  expected rows; `canStart` reflects exercise presence; `start()` invokes the
  callback with the workout.
- **Acceptance/UI:** Library → tap a workout → detail shows its exercises → tap
  Start → active flow appears. Uses the mock repository path; gated via
  `-only-testing:PulseTests` per the known UI-runner defect on Xcode/iOS 26.5.
- Keep any cross-process work (widgets/Live Activity) inert under the mock path
  so the UI suite stays deterministic.

## Future scope (next increment — "C")

A second spec will add, on this same screen: **Edit** (opens the existing
builder), **Delete** (with confirmation), and **Schedule to a day** (writes a
`plan_entries` row via `ScheduleRepository`). The detail screen's toolbar/menu is
reserved for these.
