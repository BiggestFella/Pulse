# Per-workout Settings Sheet — Design

**Date:** 2026-06-15
**Status:** Design locked (decisions confirmed). User waived the spec/plan review gates — build after the spec is written.
**Linear:** [BAK-63](https://linear.app/bakinglions/issue/BAK-63) · **builds on** [BAK-57](https://linear.app/bakinglions/issue/BAK-57) (scheduling), [BAK-59](https://linear.app/bakinglions/issue/BAK-59) (wizard/editor), [BAK-60](https://linear.app/bakinglions/issue/BAK-60) (in-place save).
**Related:** Sub-project **4 of 4** (final) of the Dropset-inspired redesign.

## Problem

A workout's configuration is scattered: **Schedule** (weekday chips) lives on `WorkoutDetailView`, **Targets** are edited in the workout editor, and **Folder** is set only at create (wizard) or via Library → Move. There's no per-workout **rest timer**, no **notes**, and no in-context **delete**. Dropset puts all of this in one per-workout **Settings** sheet (gear icon on the workout). The active session also **hardcodes 90s rest** and never reads even the global default — so any rest setting is currently inert.

## Goal

One **per-workout Settings sheet** — opened from the editor's `⋯` overflow and a gear on Workout Detail — that consolidates a workout's settings: Schedule, Targets, Rest timer (new), Notes (new), Folder, and Delete (new). Rest is wired through to the live session.

## Confirmed decisions (user)

1. **Consolidation hub** — one sheet holds everything (not just new settings).
2. **Move, don't mirror** — Schedule leaves `WorkoutDetailView`; Targets leave the editor. The sheet is the single edit surface. (Folder also stays reachable via Library → Move; the wizard still sets these at create time.)
3. **Rest wired end-to-end** — a per-workout override changes the live rest timer (and the global default gets wired in passing).
4. **Open from both** — the editor's inert `⋯` overflow + a gear on Workout Detail.

## A. Data model & migration

- `Pulse/Core/Models/WorkoutModels.swift` — `Workout` gains:
  - `var restSeconds: Int? = nil` — per-workout rest override; `nil` = use the global default.
  - `var notes: String = ""` — freeform notes.
- Migration `supabase/migrations/0010_workout_settings.sql` (apply via the Supabase dashboard — no local psql):
  ```sql
  alter table workouts add column rest_seconds int check (rest_seconds is null or rest_seconds between 15 and 600);
  alter table workouts add column notes text not null default '';
  ```
- Thread through `WorkoutRow` (read) + `WorkoutWriteRow` (write, explicit-null encoding for `rest_seconds`) + `WorkoutGraphWriter` (the upsert row now carries `rest_seconds` + `notes`). `InMemoryWorkoutRepository` round-trips them (it stores the struct). `SampleData` workouts keep `restSeconds: nil`, `notes: ""` (defaults). The BAK-60 in-place upsert already preserves `folder_id` + `plan_entries`; these two columns ride the same row.

## B. The Settings sheet — `Pulse/Features/Library/WorkoutSettings/`

A new `@Observable` model + a `SheetChrome`-based view (the app's standard sheet, `Pulse/Core/DesignSystem/BottomSheet.swift`).

- **`WorkoutSettingsModel`** (`@MainActor @Observable`): `init(workoutID:, workoutRepo:, scheduleRepo:, folderRepo:)`; `load()` hydrates a `Workout` + its current folder + folder options (via `FolderOptions.load`); state: `weekdays: Set<Int>`, `targets: Set<MuscleGroup>`, `restSeconds: Int?`, `notes: String`, `folderID: Folder.ID?`. Intents (each persists via the repos, reusing established mechanisms):
  - `toggleWeekday(_:)` / `scheduleOnDate(_:)` — moved from `WorkoutDetailModel` (persist via `saveWorkout` for weekdays, `scheduleRepo.setPlan` for a specific date).
  - `toggleTarget(_:)` — persists `targets` via `saveWorkout`.
  - `setRestSeconds(_:)` / `useDefaultRest()` — sets/clears `restSeconds`, persists via `saveWorkout`.
  - `setNotes(_:)` — persists `notes` via `saveWorkout` (on commit/blur, not per-keystroke).
  - `setFolder(_:)` — `folderRepo.moveWorkout(id:, toFolder:)`.
  - `delete()` — `workoutRepo.deleteWorkout(id:)`; signals the host to dismiss + pop.
  - **Critical — never drop exercises:** the model retains the **full hydrated `Workout`** (`private var workout: Workout`, including its exercise graph, even though the sheet shows no exercises). Each persist takes that stored `Workout`, overrides only the one edited field (`weekdays`/`targets`/`restSeconds`/`notes`), `saveWorkout`s it, and updates the stored copy. This preserves id/order/exercises across every setting change (the editor's `makeDraft` discipline). A model that saved a settings-only struct would wipe the workout's exercises — it must not.
- **`WorkoutSettingsSheet`** (View): `SheetChrome(eyebrow: "WORKOUT", title: "<name>.")` containing, top→bottom:
  1. **Schedule** — "REPEATS ON" weekday `PillChip`s (M T W T F S S) + "Schedule on a date" (the SP2 controls, relocated verbatim).
  2. **Targets** — "TARGETS" muscle `PillChip`s (SP1).
  3. **Rest timer** — "REST" row: a stepper (15s steps, 15–600s) with a "Use default (Ns)" reset; sub-label shows "Uses default rest timer" when `nil`.
  4. **Notes** — "NOTES" multi-line `TextField` ("Type anything…"); commits on blur.
  5. **Folder** — "FOLDER" — the `FolderOptions` indented list (root + folders), current selection checked.
  6. **Delete workout** — destructive row (red, `theme.accent2`), confirm `alert` → `delete()`.
  - a11y ids: `settings.repeat-day-<1..7>`, `settings.scheduleDate`, `settings.target-<raw>`, `settings.rest.stepper.inc/dec`, `settings.rest.useDefault`, `settings.notes`, `settings.folder.<id|root>`, `settings.delete`.

## C. Rest wiring (end-to-end)

- `UserSettings.defaultRestSeconds` (90, `ProfileModels.swift`) is the global fallback (already persisted; edited on the You tab).
- `ActiveWorkoutModel`: replace the hardcoded `let restTotal: TimeInterval = 90` with an effective value `effectiveRestSeconds = workout.restSeconds ?? defaultRestSeconds`, where `defaultRestSeconds` is provided **at start**. `startRest()` uses it.
- **Resolving the default despite sync init:** `AppShell` builds the session synchronously (the BAK-35 wrinkle), but every Start path is already **async** (`fetchWorkout(id:)`). At start, load `UserSettings` (`container.settings.load()`), compute the effective default, and hand it to the model alongside the workout — e.g. `session.startWorkout(workout, defaultRestSeconds: settings.defaultRestSeconds)`. The per-workout override comes from the fetched `workout.restSeconds`. This wires both the global default (previously ignored) and the per-workout override without unblocking the full sync-init refactor.
- Mock path: `-uiMock` loads `UserSettings.default` (90) via the in-memory settings repo; SampleData workouts have `restSeconds: nil`, so rest stays 90 (existing UI tests like `testMinusStepperDecrementsWeight` that assume 90s rest stay green).

## D. Relocations & access points

- **`WorkoutDetailView`** — remove the "REPEATS ON" + "Schedule on a date" block (→ sheet); body becomes title + exercises + Start. Add a **gear** toolbar button (leading of "Edit") that presents `WorkoutSettingsSheet`. `WorkoutDetailModel` sheds `toggleWeekday`/`scheduleOnDate`/`weekdays` (moved to `WorkoutSettingsModel`); after the sheet dismisses, Detail reloads (schedule/targets may have changed).
- **Editor (`WorkoutBuilderView`)** — remove `targetRow` (→ sheet); the editor keeps name + exercises. Wire the `BuilderScaffold` `⋯` overflow (`builder-overflow`, currently inert) to present the sheet for the workout being edited. `WorkoutBuilderModel` keeps `targets` only as hydrated state it still persists in `makeDraft` (so a settings change to targets and an editor save don't clobber each other — both round-trip the same `Workout`). *(See edge cases.)*
- **Wizard** — unchanged. It still sets Name/Targets/Schedule/Folder at create; the sheet is the edit-time equivalent.
- Sheet presented via `pulseSheet`/`SheetChrome` with `.presentationDetents([.large])`.

## Data flow

Open sheet (from ⋯ or gear) → `load()` hydrates workout + folder options → user edits a setting → intent persists immediately via the repo (saveWorkout in-place / moveWorkout / setPlan) → on dismiss, the host (Detail/editor) reloads. Start a workout → load settings + fetch workout → `startWorkout(workout, defaultRestSeconds:)` → rest timer uses `workout.restSeconds ?? defaultRestSeconds`.

## Edge cases

- **Editor + sheet both edit `targets`:** the editor still hydrates + persists `targets` in `makeDraft`. If the sheet changes targets while the editor is open, the editor's next save (rebuilding from its own hydrated state) could overwrite. Mitigation: the editor opens the sheet modally; on sheet dismiss the editor re-hydrates (`load()`) before any further save, so it picks up the sheet's changes. (Same for any field the sheet touches.)
- **Delete from the editor's ⋯:** confirm → delete → dismiss the sheet → pop the editor → Library refresh. From Detail: same, pop to the previous list.
- **Rest bounds:** stepper clamps 15–600s; `nil` means "default" (not 0). DB check enforces the range.
- **Notes:** committed on blur/done, not per-keystroke (avoids a save per character).
- **Specific-date schedule + delete:** `deleteWorkout` cascades children; `plan_entries.workout_id` is `on delete set null` (a one-off assignment becomes empty) — acceptable.

## E. Testing

- **Unit (`PulseTests`):** `WorkoutSettingsModel` — load hydrates weekdays/targets/rest/notes/folder; each intent persists (toggleWeekday, toggleTarget, setRestSeconds/useDefaultRest, setNotes, setFolder, delete); `saveWorkout` round-trips `restSeconds`/`notes` (model + in-memory repo); rest resolution (`effective = override ?? default`) in `ActiveWorkoutModel`.
- **Acceptance:** open settings for a workout → change rest + notes + a weekday + target + folder → all persisted on the same workout id; delete removes it. Start resolves the per-workout rest override; falls back to the global default when `nil`.
- **UI (`PulseUITests`, runs now):** open the sheet from the editor `⋯` and the Detail gear; change the rest stepper + a weekday; delete with confirm. **Retarget** SP2 `WorkoutScheduleUITests` (weekday chips now inside the sheet) + any editor target-chip assertions.

## F. Out of scope

Share, dashboard **Layout**, calendar **Pattern** (no Pulse dashboard), per-exercise **Equipment** / **Tracking-unit** (a separate per-exercise concern, not workout settings), per-movement progression increments, units beyond kg. The full async-settings-into-sync-init refactor (BAK-35) stays out — rest is resolved at start instead.
