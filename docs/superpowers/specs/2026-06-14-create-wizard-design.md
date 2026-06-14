# Guided Create Wizard + Workout Editor — Design

**Date:** 2026-06-14
**Status:** Design locked (decisions confirmed). **Build deferred until SP2/#51 merges** (this builds on it). User waived the spec/plan review gates.
**Linear:** [BAK-59](https://linear.app/bakinglions/issue/BAK-59) · **subsumes** [BAK-54](https://linear.app/bakinglions/issue/BAK-54) (folder-on-create) + [BAK-56](https://linear.app/bakinglions/issue/BAK-56) (edit) · **depends on** [BAK-57](https://linear.app/bakinglions/issue/BAK-57)
**Related:** Sub-project **3 of 4** of the Dropset-inspired redesign (SP1 Targets+Picker ✓, SP2 Scheduling in #51). SP4 = per-workout settings sheet.

## Problem

Creating a workout today is a single screen (`WorkoutBuilderView`: name + a tag/targets row + add-exercises inline) reached via Library `+` → `CreateChooserSheet` → `.workoutBuilder`. There are no guided steps, no schedule or folder choice at creation ([BAK-54](https://linear.app/bakinglions/issue/BAK-54) — the current folder context isn't even threaded to the workout builder), and no way to re-open a saved workout to edit it ([BAK-56](https://linear.app/bakinglions/issue/BAK-56)). The Dropset flow the user wants is **shell-first and multi-step**.

## Goal

A guided, multi-step **create wizard** (Name → Targets → Schedule → Folder → Create) that lands the user in a **workout editor** to add exercises — and that editor is reused for **editing** a saved workout.

## Confirmed decisions

1. **Multi-step wizard**, progress bar, **shell-first**. **Custom-only** for v1 (no Push/Pull presets — the starting-point wheel is dropped since there's only "Custom").
2. **Steps:** Name → Targets (SP1 muscle chips) → Schedule (SP2 weekday multi-select) → Folder (explicit picker, incl. "Library root") → **Create**.
3. **After Create → land in the workout editor** (the restructured builder), hydrated with the new empty workout, to add exercises via the SP1 picker.
4. **Edit ([BAK-56](https://linear.app/bakinglions/issue/BAK-56))** = open a saved workout in the **same editor**, hydrated. Create = wizard front → editor; edit = editor directly.
5. **Layout + Pattern dropped** (Dropset dashboard-card visuals; Pulse has no workout-card dashboard).
6. The **Add sheet** "A workout" launches the **wizard** instead of the old single-screen builder.

## Dependency on SP2 (#51)

Reuses, from #51: `Workout.weekdays`, the weekday multi-select control (Schedule step), `ScheduleResolver` (so a newly-scheduled workout immediately shows in Today/Plan). Build branches off `main` **after #51 is merged**.

## Architecture & components

### Create wizard (new) — `Pulse/Features/Builders/CreateWizard/`
- **`CreateWizardModel`** (`@MainActor @Observable`): draft state — `name: String`, `targets: Set<MuscleGroup>`, `weekdays: Set<Int>`, `folderID: Folder.ID?` (seeded from the folder the user tapped `+` from); `step: Step` (`.name/.targets/.schedule/.folder`); `next()`/`back()`; `canAdvance` (e.g. name non-empty on the Name step); `create() async -> Workout.ID?` — persists the workout and places it in the folder.
- **`CreateWizardView`**: a stepped container with a top progress bar and Back/Continue; step subviews (`NameStep`, `TargetsStep` reusing the SP1 target chips, `ScheduleStep` reusing SP2's weekday multi-select, `FolderStep` reusing the `MoveToFolder` folder tree). The final step's **Create** persists and routes onward.
- **Create persistence:** `workoutRepo.saveWorkout(draft)` (name + targets + weekdays) then `folders.moveWorkout(id:, toFolder: folderID)` when a non-root folder was chosen (mirrors the established folder-placement mechanism). Returns the new workout's id.

### Workout editor (restructure) — `WorkoutBuilderView` / `WorkoutBuilderModel`
- Restructure `WorkoutBuilderModel` to **hydrate from an existing `Workout`** (loaded by id) rather than only build-from-scratch: it exposes the workout's name + targets + exercises (+ the SP1 picker: add / replace / change-variation / remove) and **saves in place** (`saveWorkout` already deletes-and-reinserts by id, preserving the id).
- Reached two ways: (a) from the wizard immediately after Create (new, empty workout); (b) from a saved workout via an **Edit** affordance on `WorkoutDetailView` (BAK-56).
- The old single-screen "create from scratch" builder is **replaced**: creation now flows through the wizard; the builder *is* the editor.

### Add sheet & routing — `CreateChooserSheet` / `LibraryView`
- `create.workout` → presents `CreateWizardView` (was `.workoutBuilder`). The wizard's Folder step is seeded with the current `createParentID` (the folder being viewed), finally honoring it (BAK-54).
- `WorkoutDetailView` gains an **Edit** action → pushes the editor hydrated with that workout (BAK-56). (The SP2 weekday editor already lives on `WorkoutDetailView`; Edit covers name/targets/exercises.)

## Data flow

Wizard draft → **Create** → `saveWorkout` + folder placement → **editor** (hydrated, empty) → add exercises → `saveWorkout` (in place). Edit: saved workout → editor (hydrated) → modify → `saveWorkout`.

## Edge cases

- **Name required** (Continue/Create disabled until non-empty); Targets/Schedule optional; Folder defaults to the current folder (or root).
- **Cancel/back** mid-wizard discards the draft — nothing is persisted before Create.
- Create persists a **zero-exercise** workout; the editor then adds exercises (Start stays disabled while empty, per the workout-detail spec).
- Editing preserves the workout id (in-place save); changing weekdays re-resolves Today/Plan via SP2's resolver.

## Testing

- **Unit (`PulseTests`):** `CreateWizardModel` — step navigation, `canAdvance` validation, `create()` persists name/targets/weekdays and places the workout in the chosen folder; editor hydration (loads a saved workout's name/targets/weekdays/exercises) + in-place save; folder-placement (created-in-folder → workout's `folder_id` is that folder).
- **Acceptance:** full create flow (wizard → Create → editor → add exercises → saved with the right folder/targets/weekdays); edit a saved workout (open → modify → save, same id).
- **UI (`PulseUITests`, runs now):** step through the wizard to Create; the editor adds an exercise; the Edit entry opens a saved workout.

## Out of scope

Dashboard-card **Layout** + calendar **Pattern**, starting-point **presets**, the per-workout **Settings sheet** (SP4), **templates/share**, **frequency/cooldowns**. The plan (with verbatim code for the builder restructure) is authored at build-time against the merged SP2 code.
