# Targets + Exercise Picker — Design

**Date:** 2026-06-13
**Status:** Approved (design) — pending spec review
**Linear:** [BAK-52](https://linear.app/bakinglions/issue/BAK-52/targets-exercise-picker-rebuild-dropset-inspired-sp1)
**Related:** Sub-project **1 of 4** in the Dropset-inspired workout-creation
redesign. Later slices: SP2 per-workout scheduling, SP3 guided create wizard,
SP4 per-workout settings sheet. This slice reshapes the workout **builder** and
**exercise picker** only.

## Problem

The workout builder has a single-select, decorative **PUSH/PULL/LEGS**
`WorkoutTag` (`Pulse/Features/Builders/BuilderModels.swift`) that drives nothing
and is **never persisted** — there is no `tag` column anywhere in the schema, so
it is pure builder-local UI state.

The exercise picker (`ExercisePickerSheet`) groups exercises by muscle with
functional filter chips but a **decorative** search box. You select exercises
(each seeded with one working set + the exercise's default variation), then edit
sets and variation in a separate `SetEditorSheet`. **Variation can only be
changed inside the set editor**, and only when an exercise has more than one.

Dropset's create flow — the inspiration — uses multi-select muscle **Targets**
that pre-filter the picker, an A–Z scrubber for browsing, and an inline
equipment/variation choice while picking. This slice brings the equivalent to
Pulse.

## Goal

Let a user tag a workout with the **muscle groups it targets**, and pick
exercises through a picker that is pre-filtered to those targets, searchable,
A–Z browsable, and lets them choose each exercise's **variation inline** — then
manage exercises via a per-row **`⋯` menu** (Replace / Change variation /
Remove).

## Confirmed product decisions

1. **A Target = a catalog muscle group** — `Legs, Chest, Back, Shoulders,
   Biceps, Triceps, Other` — **multi-select** on a workout. (Not coarse
   Push/Pull buckets; the catalog is already muscle-organised and this suits a
   hypertrophy tracker.)
2. **Hybrid picker layout:** muscle-grouped sections by default (filtered to the
   active targets); a flat **alphabetical** list with an **A–Z scrubber** when
   browsing "All" or searching.
3. The picker **opens pre-filtered** to the workout's Targets as **removable
   chips**; an **All** chip clears the filter.
4. **Search becomes functional** (filters by exercise name) and flips the list
   into alphabetical mode.
5. **Inline variation while picking:** selecting an exercise reveals a Variation
   dropdown over that exercise's variations — shown **only when the exercise has
   more than one** variation; default = the exercise's `defaultVariationID`. The
   chosen variation is carried into the workout.
6. Each builder exercise row gains a tappable **`⋯` button** (not a long-press)
   opening: **Replace exercise** (keeps the set structure), **Change variation**,
   **Remove**.

## Non-goals (this spec)

- **Tracking unit** (per-exercise measurement type: reps×weight / time /
  distance / reps-only) — its own ticket; it ripples into the active session,
  stats, and PRs.
- **Per-workout scheduling, the guided create wizard, the settings sheet** —
  SP2 / SP3 / SP4.
- **Set-model change** (kg+reps) and **inline Sets editing in the picker** — set
  editing stays in the existing `SetEditorSheet`. (Dropset shows a *Sets ▾* in
  the picker; deferred with the set-model work.)
- **Templates / Share.**
- **Auto-suggesting targets** from added exercises — cut for v1 (trivial to add
  later).

## User story & acceptance criteria

> As a user, I tag a workout with the muscles it trains and pick exercises from
> a list focused on those muscles, choosing each exercise's variation as I go.

1. The builder shows a **multi-select Targets** row (the six muscle groups +
   Other) in place of the PUSH/PULL/LEGS tag. Selecting/deselecting toggles a
   target; selections persist when the workout is saved and reload with it.
2. Opening the picker from a workout shows it **pre-filtered to that workout's
   Targets** as removable chips. Removing all chips (or tapping **All**) shows
   the whole catalog.
3. With ≥1 target chip active, the picker shows **muscle-grouped sections**
   limited to those targets. With **All** active or a non-empty search, it shows
   a **flat alphabetical list with an A–Z scrubber**; tapping a letter jumps to
   it.
4. **Search** filters the list by exercise name (case/diacritic-insensitive).
5. Selecting an exercise that has **more than one variation** reveals an inline
   **Variation** dropdown (default = the exercise's default variation); the
   chosen variation is applied when the exercise is added. Single-variation
   exercises are added directly.
6. A builder exercise row's **`⋯`** opens a menu: **Replace exercise** swaps the
   exercise (resets variation to the replacement's default) while **keeping the
   set structure**; **Change variation** picks among the exercise's variations
   (shown when >1); **Remove** deletes the row.

## Data model & persistence

### `MuscleGroup` enum — new, `Pulse/Core/Models/`

```swift
enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Equatable {
    case legs = "Legs"
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case other = "Other"
    var id: String { rawValue }
}
```

The rawValues match the catalog's `muscle_group` strings (seeded in
`0005_seed_exercise_catalog.sql` / `0006_catalog_additions.sql`), so a workout's
targets line up exactly with `Exercise.muscleGroup` for filtering. The six
muscles + `Other` (Farmer Carry) are the complete current catalog set; when
mapping an `Exercise.muscleGroup` string to a `MuscleGroup` (for grouping or
filtering), any value outside this set falls back to `.other`.

### `Workout.targets`

Add to `Workout` (`Pulse/Core/Models/WorkoutModels.swift`):

```swift
var targets: [MuscleGroup] = []
```

Defaulted so existing call sites compile and existing rows load as "no targets".

### Migration — `supabase/migrations/0008_workout_targets.sql`

`0007_folders.sql` is the latest migration (note: two `0006_*` files already
exist); the next free number is **0008** — confirm at implementation time.

```sql
alter table workouts add column targets text[] not null default '{}';
```

- Thread `targets` through the Supabase row mapping (`WorkoutRow` in
  `Core/Data/Supabase/Rows/Rows.swift` + the workout write path) and
  `InMemoryWorkoutRepository`.
- Existing rows default to `'{}'` → empty targets.
- Context for later slices (not this one): `workouts.program_id` is still
  `NOT NULL` and `folder_id` is a separate axis; `targets` is an independent
  column and the builder→save path is otherwise unchanged.

### Retire `WorkoutTag`

Delete the `WorkoutTag` enum and `WorkoutBuilderModel.tag`; remove the tag-pill
row from `WorkoutBuilderView`. **No DB migration** — it was never persisted.

## Components

### Builder — Targets selector

- **`WorkoutBuilderModel`**: replace `var tag: WorkoutTag` with
  `var targets: Set<MuscleGroup> = []` and a `toggleTarget(_:)` intent. `save()`
  writes `Array(targets)` into the `Workout`; the load/hydrate path reads
  `workout.targets` (used once editing a saved workout exists — empty for new).
- **`WorkoutBuilderView`**: swap the `WorkoutTag.allCases` pill row
  (`WorkoutBuilderView.swift:91`) for a multi-select muscle-target chip row over
  `MuscleGroup.allCases`. Selected = filled (`accent` / `onAccent`), unselected =
  outline. Eyebrow label "TARGETS". Theme tokens only (Hanken / Oswald / Geist).

### Exercise picker — `ExercisePickerSheet` rebuild

New/changed inputs: the workout's `targets` (seeds the active filter). The sheet
already receives the full catalog (`[BuilderCatalogGroup]`, each carrying whole
`Exercise` models incl. variations), so variations are available inline.

- **Filter chips**: initialise to the workout's targets as removable chips; an
  **All** chip clears to no filter.
- **Two modes (hybrid):**
  - *Sectioned* (default; ≥1 target chip active): muscle-grouped sections limited
    to the active targets — today's layout.
  - *Alphabetical* (search non-empty **or** All / no chips): one flat list sorted
    by name with an **A–Z scrubber** (a `ScrollViewReader` + a letter index
    overlay; tapping a letter scrolls to that section). Respects active chips.
- **Search**: functional over exercise name (case/diacritic-insensitive);
  non-empty search → alphabetical mode.
- **Inline variation**: a selected row whose exercise has **>1 variation**
  expands to a Variation control (a menu over `exercise.variations`, default
  `defaultVariationID`), recording the chosen `variationID` for that exercise.
- **Selection**: keep the ordered multi-select array (`selected:
  [Exercise.ID]`, tap-order preserved) and dimmed already-added rows. The
  confirm callback changes to carry the chosen variation per exercise:

```swift
struct PickedExercise: Equatable { let id: Exercise.ID; let variationID: Variation.ID? }
// onConfirm: ([PickedExercise]) -> Void   // was ([Exercise.ID]) -> Void
```

### Builder model intents

- `addExercises(_:)` accepts `[PickedExercise]`; seeds each `BuilderExercise`
  with its chosen variation (fallback to `defaultVariationID`) + one working set
  (existing dedupe of already-added exercises unchanged).
- **New** `replaceExercise(itemID:with:)`: swaps `exercise`, resets `variationID`
  to the replacement's default (or the picked variation), and **keeps `sets` and
  `supersetGroup`**.
- Reuse existing `updateVariation(itemID:variationID:)` for **Change variation**.
- Reuse existing `removeItem(id:)` for **Remove**.

### Builder row `⋯` menu — `WorkoutBuilderView`

- Replace the decorative dots with a tappable **`⋯` button** per exercise row
  opening a menu:
  - **Replace exercise** → opens `ExercisePickerSheet` in a **single-select
    "replace" mode** scoped to that row; returns one `PickedExercise` →
    `replaceExercise`.
  - **Change variation** → menu of the exercise's variations (shown when >1) →
    `updateVariation`.
  - **Remove** → `removeItem`.

## Data & edge cases

- **Existing saved workouts**: `targets = []` → picker opens in All / alphabetical
  mode; builder shows no targets selected.
- **Single-variation exercises**: no inline Variation control; added directly.
  "Change variation" is hidden/disabled for them.
- **"Other"** is a selectable target so Farmer Carry stays reachable.
- **Variation label**: the dropdown lists **variation names** (Pulse's unit —
  variations bundle equipment *and* variants like "Incline"/"Wide Grip"), not a
  separate equipment list.
- **A–Z scrubber** over ~48 exercises is light today but built to scale as the
  catalog grows.

## Testing

Acceptance-criteria driven, per CLAUDE.md.

- **Unit (`PulseTests`):**
  - `WorkoutBuilderModel`: `toggleTarget` updates targets; `save()` persists
    `targets`; `addExercises` applies the chosen variation per exercise;
    `replaceExercise` swaps the exercise + resets variation but **keeps sets &
    supersetGroup**.
  - Row mapping / `InMemoryWorkoutRepository`: `targets` round-trips
    (save → fetch).
  - Picker filtering/search (extract the filter+sort+letter-index into a pure,
    testable function): target filter, search match, alphabetical sort, letter
    index.
- **Acceptance / UI:** set targets in the builder → open the picker → it is
  pre-filtered to those targets → clear to **All** → list becomes alphabetical
  with the A–Z scrubber → search filters → select an exercise → choose its
  variation inline → Add → the builder row shows the chosen variation → `⋯` →
  Replace keeps sets; Change variation; Remove. Mock repository path; gated via
  `-only-testing:PulseTests` per the known UI-runner defect on Xcode/iOS 26.5.
  Keep any cross-process work (widgets / Live Activity) inert under the mock path
  so the suite stays deterministic.

## Out of scope / future

- **Tracking unit** (own ticket). **Inline Sets editing** in the picker.
- **Per-workout scheduling / guided wizard / settings sheet** (SP2–SP4).
- **Auto-suggest targets** from added exercises. **Coarse movement buckets**
  (Push/Pull). **Templates / Share.**
