# Per-workout Scheduling — Design

**Date:** 2026-06-14
**Status:** Approved (design, verbally) — building. User waived the spec/plan review gates.
**Linear:** [BAK-57](https://linear.app/bakinglions/issue/BAK-57/per-workout-scheduling-recurring-weekdays-specific-dates-sp2) · **subsumes** [BAK-42](https://linear.app/bakinglions/issue/BAK-42)
**Related:** Sub-project **2 of 4** of the Dropset-inspired redesign (SP1 Targets+Picker done). Prerequisite for **SP3** (the guided create wizard's Schedule step).

## Problem

Scheduling today is split across two layers that don't compose:
- **`Workout.weekday: Int?`** — a *single* repeating day; only `todaysWorkout(on:)` reads it (Today's hero).
- **`plan_entries`** — a per-*date* table (`planned`/`rest`/`done`); the Plan tab and Today's week-strip/streak read it.

A workout can't recur on *multiple* days, the Plan calendar doesn't reflect a workout's recurrence at all (only manual per-date rows), and the active-flow **Start** launches a **hardcoded** workout, not the scheduled one ([BAK-42](https://linear.app/bakinglions/issue/BAK-42)).

## Goal

A workout carries its own **recurring weekdays** (multi-select) and can also be dropped on **specific calendar dates**; Today and the Plan calendar both reflect that, computed consistently; and Start launches the workout actually scheduled for today.

## Confirmed model (user decisions)

1. A workout has **`weekdays: [Int]`** (1–7, recurring, multi-select), replacing the single `weekday`. Empty = unscheduled.
2. A workout can also be assigned to **specific dates** via the existing per-date `plan_entries` (what the Plan tab already does).
3. **Reconciliation precedence for any date: specific `plan_entry` → recurring weekday → rest.** Specific dates override recurrence. Composed on read (no pre-materialising future entries).
4. **No "frequency"** mode (every-N-days) — specific dates cover one-offs.
5. If two workouts recur on the same weekday, the **lowest `order`** wins (one effective workout per day).

## A. Data model & migration

- `Pulse/Core/Models/WorkoutModels.swift`: `Workout.weekday: Int?` → `var weekdays: [Int] = []`.
- Migration `supabase/migrations/0009_workout_weekdays.sql`:
  ```sql
  alter table workouts add column weekdays int[] not null default '{}';
  update workouts set weekdays = array[weekday] where weekday is not null;
  alter table workouts drop column weekday;
  ```
  (Apply via the Supabase dashboard — no local psql.)
- Thread through `WorkoutRow` / `WorkoutWriteRow` (`weekday: Int?` → `weekdays: [Int]`) and `WorkoutGraphWriter`.
- `SupabaseWorkoutRepository.todaysWorkout(on:)`: the `eq("weekday", appWeekday)` filter becomes an array-contains (`.contains("weekdays", value: [appWeekday])`).
- `InMemoryWorkoutRepository.todaysWorkout(on:)`: `first { $0.weekdays.contains(appWeekday) }`.
- Mock `SampleData`: `pushWorkout … weekday: 1` → `weekdays: [1]`, Pull → `[3]`, Legs → `[5]`; the schedule generator's `$0.weekday == appWeekday` → `$0.weekdays.contains(appWeekday)`. Update `TodaysWorkout.swift` and `SampleDataTests` (the BAK-38 agreement test) to the new field.

## B. Read-side composition — the resolver (keystone)

A pure, testable resolver decides the effective plan for a date, shared by Today and Plan so they can never disagree.

`Pulse/Core/Workout/ScheduleResolver.swift` (new):
```swift
enum ScheduleResolver {
    /// Effective plan for `date`: a specific plan entry wins; else a recurring
    /// workout whose `weekdays` include that weekday (lowest `order`); else rest.
    static func plan(for date: Date,
                     entry: DayPlan?,
                     workouts: [Workout],
                     calendar: Calendar) -> DayPlan {
        if let entry { return entry }                 // specific assignment / done / rest
        let appWeekday = appWeekday(of: date, calendar: calendar)   // Mon=1…Sun=7
        let recurring = workouts
            .filter { $0.weekdays.contains(appWeekday) }
            .sorted { $0.order < $1.order }
        if let w = recurring.first { return .workout(w.id) }
        return .rest
    }
    static func appWeekday(of date: Date, calendar: Calendar) -> Int { /* (greg+5)%7+1 */ }
}
```

- **`TodaySnapshotComposer`**: `composeCard` and `composeWeek` route through the resolver (passing the user's workouts + the date's plan entry) instead of calling `todaysWorkout`/`schedule.plan` independently. The hero is the resolver's `.workout(id)` for today (suppressed when the day resolves to `.done`).
- **`PlanModel.buildSchedule` / `buildAgenda`**: today they read `scheduleRepo.plan(for:)` only. They now also load the user's workouts (already have `workoutRepo`) and resolve each day → recurring workouts appear on the calendar automatically; specific entries override.
- `todaysWorkout(on:)` remains (weekday-set match) but the *effective* today workout (incl. specific-date override) comes from the resolver — see D.

## C. Editing UI (minimal, on `WorkoutDetailView`)

`WorkoutDetailView` + `WorkoutDetailModel` (currently read-only: shows a workout + Start) gain:
- **"Repeats on" weekday multi-select** (M T W T F S S) → toggles `workout.weekdays`, persisted via `WorkoutRepository.saveWorkout`.
- **"Schedule on a date"** → a date picker → `ScheduleRepository.setPlan(.workout(id), on: date)` (a specific-date assignment).

This realizes the "Schedule" piece parked as "scope C" in `2026-06-12-workout-detail-start-design.md`. (Full Edit of a workout = BAK-56; this is just scheduling.)

## D. BAK-42 — Start the real scheduled workout

`AppShell` currently sets a hardcoded `startWorkout` (`TodaysWorkout.workout` / `ActiveWorkoutSample`). Replace with the **resolver's effective workout for today**, fetched from the repos:
- Resolve today's `DayPlan` (specific entry → recurrence). If `.workout(id)`, fetch the hydrated `Workout` (`fetchWorkout(id:)`) and Start launches it.
- Empty/rest today → no hero (existing empty handling); Start affordance hidden/disabled.
- Mock path resolves via `SampleData`; live path via the repos. `TodaysWorkout.swift` (hardcoded) is removed once unused.

## Data & edge cases

- Existing workouts: migration backfills `weekdays` from the old `weekday` (single-day workouts keep their day; null → `[]`).
- A specific `plan_entry` of `.rest` on a recurring day → that day is rest (override), per precedence.
- `.done` entries always win (a logged session) — unchanged streak behaviour.
- Multiple recurring workouts on a weekday → lowest `order` is the hero; others aren't surfaced as the single hero (acceptable for v1; refine when the dashboard/multi-workout-day exists).

## E. Testing

- **Unit (`PulseTests`):** `ScheduleResolver` precedence (specific > recurrence > rest; `.rest`/`.done` overrides; multi-workout tiebreak by `order`; `appWeekday` mapping); `todaysWorkout` weekday-set match; `weekdays` round-trip (model/row/in-memory repo); `WorkoutDetailModel` editing intents (toggle weekday persists; schedule-on-date calls `setPlan`); `TodaySnapshotComposer` + `PlanModel` produce a consistent effective schedule for the same date.
- **Acceptance (`PulseTests`):** set a workout to Mon+Fri → it resolves as today's workout on those weekdays and appears in the Plan agenda; a specific-date assignment overrides recurrence; Start resolves to the scheduled workout.
- **UI (`PulseUITests`, runs now):** the Workout-Detail "Repeats on" editor toggles + persists; Plan/Today reflect a scheduled workout. Gate full suite + `PulseTests`.

## F. Out of scope (deferred)

- **Frequency** (every-N-days), **cooldowns**, dashboard card **"Layout"**, calendar **"Pattern"** — later / SP3–SP4.
- The rich Schedule *step* UI = **SP3** wizard. Per-workout settings sheet = **SP4**.
- Streaks unchanged (already work). Full workout **Edit** = BAK-56.
