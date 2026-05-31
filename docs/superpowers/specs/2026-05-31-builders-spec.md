# Builders (Workout / Routine / Folder) — Spec

**Linear:** BAK-18  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview
Builders are the creation surfaces a lifter reaches from the Library **Create chooser** (BAK-10): a **Workout Builder** (name, tags, exercise list with supersets, per-set editing), a **Routine Builder** (name, program length, weekly split of workouts + rest days), and a **Folder** creation screen (name + color). They push as stack overlays. This feature also delivers the three supporting sheets that the builders host: the **Set Editor**, the **Exercise Picker**, and the **Workout Picker**. All screens bind to repository protocols backed by in-memory mocks; real Supabase persistence (saving the built workout/routine/folder) is deferred to BAK-6.

## User story
As a lifter, I want to build my own workouts (choosing exercises, supersets, and per-set rep/RIR/type prescriptions), assemble them into a multi-week routine, and organize everything into colored folders — so that I can design and store my own training instead of only following a preset program.

## Acceptance criteria
1. **Workout Builder** shows a top bar with eyebrow **NEW WORKOUT** and a trailing ⋯ action, an editable name field styled as H1 (default text `New workout`), a tag-chip row **PUSH / PULL / LEGS** (exactly one active at a time, active chip uses the `accent2` fill / `onAccent` text) plus a decorative dashed **+ TAG** chip, and a header row `EXERCISES · {n}` (left) / `{totalSets} SETS` (right).
2. The Workout Builder exercise list renders one row per `WorkoutExercise`: grip handle, an index badge (`1, 2, …`) or superset letter badge (`A, B, …`, tinted `accent2`/`onAccent`), the exercise name, a sub-line `{setCount} sets · {repsSummary}` with ` · MIXED` appended when any set is non-working, a **⛓ link** toggle (hidden on the last row), and a remove ✕.
3. Tapping a Workout Builder exercise row opens the **Set Editor** sheet for that exercise.
4. Tapping **⛓** on a row links it with the row directly below into a superset: the linked pair (or run of linked rows) renders inside an `accent2`-bordered grouped card headed `SUPERSET · {n} MOVES` with an **UNLINK** control; members are re-badged `A / B / C / D`. Tapping ⛓ again, or **UNLINK**, dissolves the group. Linking is only offered when a row below exists.
5. Tapping **+ ADD EXERCISE** opens the **Exercise Picker** sheet; confirming a selection appends the picked exercises (each seeded with a default set list) to the list, skipping ids already present.
6. **Set Editor** sheet shows eyebrow `{MUSCLE} · {n} SETS`, title = exercise name, a `SET / REPS / RIR` column header, and one editable row per set: numbered badge (`accent2` fill when the set type is non-working), a numeric reps input, a RIR −/+ stepper clamped to **0–5**, a remove ✕ (disabled when only one set remains), and a per-set type-chip row **Working / Warm-up / Drop set / To failure / AMRAP** (selected chip = `accent` fill / `onAccent`). A **+ Add set** control clones the last set (as a `working` set) and appends it; **Done** dismisses.
7. **Exercise Picker** sheet shows eyebrow `ADD EXERCISE`, title `Pick exercises.`, a **pinned** (non-scrolling) decorative search field and group filter-chip row (`All` + muscle groups, accent chip style), and a scrollable multi-select catalog grouped by muscle. Already-added exercises render dimmed with a ✓ and are not selectable; tapping a selectable row toggles selection (selected = accent border + ✓ glyph). The footer shows **Cancel** and a primary button reading `Add {n} selected` (disabled / reduced when 0 selected, label `Select exercises`).
8. **Routine Builder** shows top bar eyebrow **NEW ROUTINE** + ⋯, an editable name (default `New routine`), a **PROGRAM LENGTH** week stepper (Oswald numeral + `wks`, − clamped to a minimum of 1, no upper clamp), a `WEEKLY SPLIT` / `{n} WORKOUTS / WK` header (count excludes rest days), and a day list.
9. The Routine Builder day list renders one row per day: a day-of-week badge (`M, T, W…` by position), workout name, sub `{DOW} · {sub}` (rest days dashed and dimmed), and a remove ✕. **+ ADD / CREATE WORKOUT** opens the **Workout Picker** sheet; **+ Add rest day** appends a rest day directly.
10. **Workout Picker** sheet shows eyebrow `ADD TO ROUTINE`, title `Add a workout.`, a **pinned** accent-bordered `Create new workout` card at the top, then a scrollable `FROM YOUR LIBRARY` list of saved workouts (name + sub + a **+** affordance). Picking the create-new card or any saved workout appends a day to the routine and dismisses the sheet.
11. **Folder** creation screen shows top bar eyebrow **NEW FOLDER** + ⋯, a centered large colored folder-icon preview, a centered editable name (default `New folder`), a `FOLDER COLOR` eyebrow, and a 6-swatch color picker (the six brand colors); selecting a swatch updates both the selected state and the preview tint.
12. Each builder has a footer with **Cancel** (secondary) and a primary save action (`Save workout` / `Save routine` / `Create folder`); both navigate back. On save, the model calls the appropriate repository write method (mock) with the assembled draft.
13. All colors, spacing, radii, and typography come from `Theme` tokens; every builder and sheet renders correctly in both Coastal and Mint palettes with no hardcoded colors.

## Screen / UX behavior

### Workout Builder (`workoutBuilder` stack screen)
- **Top bar:** Geist Mono eyebrow `NEW WORKOUT`; trailing ⋯ (overflow — decorative this release, see Open Questions). Editable **name** rendered in the H1 type ramp (Hanken Grotesk), transparent background, no border.
- **Tags:** chip row `PUSH / PULL / LEGS` — single-select; active chip fills `accent2` with `onAccent` text and an `ink` border, inactive chips are bordered with `ink-soft` text. A dashed **+ TAG** chip is decorative (no add-tag flow).
- **Header counts:** `EXERCISES · {items.count}` left, `{sum of set counts} SETS` right.
- **Exercise list (scroll):** consecutive items sharing a non-nil `supersetGroup` are visually grouped. A group of ≥2 renders an `accent2`-bordered card with `SUPERSET · {count} MOVES` + `UNLINK`; a lone row (or single-member group) renders ungrouped. Each row: grip handle (`ink-faint`), badge (index, or A/B/C/D when in a superset — `accent2`/`onAccent`), name, sub `{n} sets · {reps joined by "-"}` + ` · MIXED` if any non-working set, ⛓ link toggle (active = `accent2`, only shown when not the last row), and remove ✕. Row tap → Set Editor.
- **Link semantics:** ⛓ toggles the link between row `idx` and `idx+1`. If both already share a group, it breaks the lower row out; otherwise it assigns a shared group id to both. Mirrors the prototype `toggleLink`.
- **Add / footer:** dashed **+ ADD EXERCISE** row → Exercise Picker. A helper caption reads "Tap ⛓ on an exercise to superset it with the one below." Footer: **Cancel** (secondary, back) + **Save workout →** (primary, back + save).

### Set Editor sheet
- Standard sheet chrome (dim backdrop tap-to-close, drag handle, top radius, ✕). Eyebrow `{MUSCLE} · {n} SETS`, title `{exercise name}.`.
- Column header `SET / REPS / RIR`. Per set row: numbered badge (transparent/`ink` when `working`, `accent2`/`onAccent` otherwise), reps numeric input (digits only, Oswald numeral), RIR −/+ stepper clamped 0–5 (value in `accent`), remove ✕ disabled & dimmed when `setList.count <= 1`. Below each row a type-chip row: `Working / Warm-up / Drop set / To failure / AMRAP`; the selected type fills `accent` with `onAccent`, others bordered `ink-faint`/`ink-soft`.
- **+ Add set** (dashed, `accent`) clones the last set's reps/RIR with type forced to `working`. **Done** (primary, full width) dismisses. Edits mutate the builder's in-memory item directly.

### Exercise Picker sheet
- Eyebrow `ADD EXERCISE`, title `Pick exercises.`. **Pinned** (non-scrolling) decorative search field + horizontally scrollable group filter chips (`All` + each catalog muscle group, accent chip style; `All` default).
- Scroll body: catalog grouped by muscle (eyebrow `{MUSCLE}` per group). Rows show name + `{equip}` sub. Already-added rows are dimmed (opacity reduced), non-interactive, glyph ✓. Selectable rows toggle on tap: selected = `accent` border (2px) + filled ✓ glyph; unselected = `+` glyph.
- Footer: **Cancel** (secondary) + primary `Add {n} selected` (label `Select exercises` and reduced opacity when none selected). Confirm calls back with selected ids.

### Routine Builder (`routineBuilder` stack screen)
- Top bar eyebrow `NEW ROUTINE` + ⋯; editable H1 name.
- **Week stepper:** `PROGRAM LENGTH` eyebrow + IconBtn − / Oswald `{weeks}wks` / IconBtn +. − clamps at 1; + unbounded.
- Header: `WEEKLY SPLIT` left, `{non-rest day count} WORKOUTS / WK` right.
- **Day list (scroll):** one row per day — DOW badge (first letter of MON/TUE/… by position, fallback `D`), name, sub `{DOW or DAY n}{ · sub}`; rest days use a dashed border and reduced opacity. Remove ✕ per row. Dashed **+ ADD / CREATE WORKOUT** → Workout Picker; dashed **+ Add rest day** appends `{nm:"Rest", rest:true}`.
- Footer: **Cancel** + **Save routine →**.

### Workout Picker sheet
- Eyebrow `ADD TO ROUTINE`, title `Add a workout.`. **Pinned** `Create new workout` card (accent border + accent-tinted fill, plus-tile + "Build from scratch" sub + chevron) — picking it appends a `New workout` day flagged new. Then eyebrow `FROM YOUR LIBRARY` and a scroll list of saved workouts (name + sub + accent **+** affordance). Picking any appends that workout as a day. Either action dismisses.

### Folder creation screen (`folderBuilder` stack screen)
- Top bar eyebrow `NEW FOLDER` + ⋯. Centered column: a large rounded folder-icon preview (filled with the selected color, `ink` border + hard offset shadow) and a centered editable name. `FOLDER COLOR` eyebrow + a 6-swatch grid (brand palette — see Open Questions on whether these are tokenized). Selected swatch gets an `ink` border + an `accent2` focus ring. Footer: **Cancel** + **Create folder →**.

### Navigation & motion
- All three builders are pushed onto the hosting `NavigationStack` from the Library Create chooser (BAK-10). Cancel and Save both pop back. Sheets slide up over a dim backdrop; screens mount with the standard fade+rise. Buttons/chips follow the design-system pill style (2px `ink` border + hard offset shadow, press-down translate). On accent-filled surfaces, highlight text uses `onAccent`, never `accent2`.

## Data & state
Three `@Observable` models, one per builder, each in `Pulse/Features/Builders/`.

```swift
@Observable final class WorkoutBuilderModel {
    var name: String = "New workout"
    var tag: WorkoutTag = .push            // .push | .pull | .legs
    var items: [BuilderExercise] = []      // editable WorkoutExercise drafts
    var pickerPresented = false
    var editingItemID: BuilderExercise.ID? = nil   // drives Set Editor
    var saveState: SaveState = .idle       // .idle | .saving | .saved | .error(String)
    // intent: load(), addExercises([Exercise.ID]), removeItem(id),
    //         toggleLink(at:), updateSet(itemID:index:patch:), addSet(itemID:),
    //         removeSet(itemID:index:), save(), cancel()
    var totalSets: Int { items.reduce(0) { $0 + $1.sets.count } }
}

@Observable final class RoutineBuilderModel {
    var name: String = "New routine"
    var weeks: Int = 8                     // clamped >= 1
    var days: [BuilderDay] = []            // { name, sub, isRest }
    var pickerPresented = false
    var saveState: SaveState = .idle
    // intent: load(), incWeeks(), decWeeks(), addWorkout(BuilderDay),
    //         addRestDay(), removeDay(at:), save(), cancel()
    var workoutsPerWeek: Int { days.filter { !$0.isRest }.count }
}

@Observable final class FolderBuilderModel {
    var name: String = "New folder"
    var colorToken: FolderColor = .blue    // one of 6
    var saveState: SaveState = .idle
    // intent: select(color:), save(), cancel()
}
```

**Display / draft structs** (UI-first; co-located until the persisted shape is finalized in BAK-6):
- `BuilderExercise { id, exercise: Exercise, variationID?, supersetGroup: String?, sets: [SetSpec] }` — a mutable editing view over `WorkoutExercise` from `Core/Models`.
- `BuilderDay { id, name: String, sub: String, isRest: Bool, sourceWorkoutID: Workout.ID? }`.
- `WorkoutTag` enum (`push/pull/legs`); `FolderColor` enum mapping to the 6 brand swatches (see Open Questions on tokenization).
- The Exercise Picker renders `MuscleGroupCatalog` / `CatalogExercise` (the same display shapes used by the Library catalog, BAK-10).

**Repository protocols (defined in BAK-6; consumed here via mocks):**
- `ExerciseCatalogRepository.catalog() async throws -> [MuscleGroupCatalog]` — feeds the Exercise Picker and seeds added exercises.
- `WorkoutRepository.savedWorkouts() async throws -> [WorkoutSummary]` — feeds the Workout Picker `FROM YOUR LIBRARY` list.
- `WorkoutRepository.saveWorkout(_ draft: Workout) async throws` — Workout Builder save.
- `RoutineRepository.saveRoutine(_ draft: Program) async throws` — Routine Builder save.
- `FolderRepository.saveFolder(name:colorToken:) async throws` — Folder save.

Models call these in their intent methods, setting `saveState` accordingly. Read-only catalog/saved-workout loads set a `loadState`-style flag the picker sheets observe.

**Mock data** (in-memory mocks + sample data, coordinated with BAK-6, mirroring the prototype):
- Default Workout Builder items: `Flat bench` (5 sets: warmup/working×3/failure) and `Incline` (4 working sets), so the builder opens non-empty exactly as the prototype does.
- Exercise Picker catalog: the prototype `EXERCISE_CATALOG` grouped by muscle (Chest, Back, Legs, Shoulders, Triceps, …) with equipment labels.
- Workout Picker saved list: `Chest & Tris (7)`, `Back & Bis (6)`, `Legs (5)`, `Shoulders (5)`, `Arms · finisher (4)`, `Active recovery (3)`.
- Default Routine: 8 weeks, 5-day split (`Chest & Tris`, `Back & Bis`, `Legs`, `Rest`, `Shoulders & Arms`).
- Folder swatches: `#26B6F6, #FF6A1F, #00D9B8, #FFCC33, #FF4D6D, #9B6BFF` (blue default).

**Dependencies:** Design System tokens & components — chips, rows, badges, IconBtn, `Sheet`, `FolderIcon`, buttons (BAK-7). Repository protocols + in-memory mocks + sample data (BAK-6). Reached from the Library Create chooser (BAK-10).

## Out of scope
- Real Supabase persistence and any networked reads/writes (BAK-6 wires the mocks to real storage).
- Drag-to-reorder of exercises or routine days (a grip handle is shown but reordering is deferred — see Open Questions).
- Functional search in the Exercise Picker (the search field is decorative this release).
- The **+ TAG** add-tag flow and any tag beyond PUSH/PULL/LEGS; multi-tag selection.
- The ⋯ overflow menu in any builder top bar (rename/delete/duplicate, etc.).
- Editing an *existing* saved workout/routine/folder (this feature creates new ones; edit-in-place is a future feature unless clarified — see Open Questions).
- Choosing/assigning a variation per exercise inside the builder, and any per-exercise cue/finisher fields.
- Setting target weights in the builder (the Set Editor edits reps/RIR/type only; weight is captured live during a session per `Core/Models`).
- Assigning a routine's workouts to specific weekdays / scheduling (Plan/Calendar, BAK separate); the day list here is an ordered split, not a calendar.
- The Create chooser sheet itself (delivered in Library, BAK-10) and all non-builder screens.
- Live Activity / Widgets (BAK-14).

## Edge cases
- **Empty workout:** a Workout Builder with zero exercises shows only the `+ ADD EXERCISE` row + helper caption; `EXERCISES · 0`, `0 SETS`; Save behavior on an empty workout is undefined by the prototype (see Open Questions).
- **Single set:** the Set Editor remove ✕ is disabled & dimmed when one set remains; you can never delete the last set.
- **RIR bounds:** RIR stepper clamps at 0 (no negatives) and 5 (max); reps input strips non-digits and never goes empty (falls back to 0).
- **Last-row link:** the ⛓ toggle is hidden on the final exercise row (nothing below to link).
- **Superset of 3+:** linking three consecutive rows produces one card `SUPERSET · 3 MOVES` badged A/B/C; UNLINK on the group dissolves it (prototype dissolves from the first pair).
- **Adding a duplicate exercise:** the Exercise Picker disables already-added rows; confirming still filters out any ids already present.
- **Week stepper minimum:** weeks cannot go below 1; there is no enforced maximum in the prototype.
- **All-rest routine:** a routine of only rest days shows `0 WORKOUTS / WK`; saving such a routine is undefined (see Open Questions).
- **Loading the picker catalog:** while `ExerciseCatalogRepository.catalog()` / `savedWorkouts()` is in flight, the sheet shows a loading affordance; on throw, an error state with retry; both deferred-detail per BAK-6 mock timing.
- **Save failure:** a throwing save mock sets `saveState = .error`; the screen surfaces an error and does not pop.
- **Theme switching:** switching Coastal ↔ Mint live re-skins all chips, badges, superset cards, swatches, and folder preview via tokens; the 6 folder swatches are fixed brand colors and intentionally do not re-skin (confirm in Open Questions).
- **Sheet dismissal:** backdrop tap / ✕ / drag-down closes any builder sheet without committing partial selections (Exercise Picker selection state is discarded on cancel).
- **Long names:** editable name fields and rows truncate gracefully without breaking layout.

## Open questions
1. **Save targets & persistence:** the prototype's Save buttons only navigate back (no write). What exactly should `saveWorkout` / `saveRoutine` / `saveFolder` persist, and where does a built workout land (a folder? the "One-offs" folder? unscheduled)? Repository write signatures need confirming with BAK-6.
2. **Drag-to-reorder:** a grip handle is rendered but the prototype has no reorder behavior. Is reorder in scope for this feature or deferred?
3. **Editing existing items:** is this feature create-only, or must the same builders open and edit an existing saved workout/routine/folder (and if so, how is the entry point wired)?
4. **Variation selection:** `WorkoutExercise` carries a `variationID`, but the builder never lets you pick one. Should the builder assign a default variation, or expose a variation switcher per exercise?
5. **Tags:** are PUSH/PULL/LEGS the complete tag set, is exactly one required, and is **+ TAG** ever meant to be functional? What does the tag map to in the persisted `Workout` (it has no tag field today)?
6. **Folder color tokenization:** the 6 swatches are raw hex in the prototype, which conflicts with the "never hardcode colors / Theme tokens only" rule. Should these become named brand-color tokens, and should they stay fixed across Coastal/Mint?
7. **Routine ↔ Program mapping:** the prototype routine is `{name, weeks, days[]}` with day rows that are just `{nm, sub}` strings — not real `Workout` references. How does a built routine map onto the `Program → Workout` domain model (do days reference saved Workout ids; what about the "Create new workout" day)?
8. **Saved-workout sub-lines:** the Workout Picker shows `"7 exercises"` etc. — are these counts computed from stored workouts or canned? Affects the `savedWorkouts()` shape.
9. **Empty / degenerate saves:** is saving a zero-exercise workout or an all-rest routine allowed, blocked, or silently permitted?
10. **`+ Add set` type:** the prototype always clones the last set as `working` (dropping the prior type). Is that intended, or should it preserve the cloned set's type?
11. **⋯ overflow:** what actions belong in the top-bar ⋯ on each builder (if any in this release)?

## Tests required

**Unit tests — `WorkoutBuilderModel`:**
- `addExercises` appends seeded exercises and skips ids already in `items`. (AC5)
- `removeItem` drops the matching item. (AC2)
- `toggleLink(at:)` links a row with the next (assigns a shared group id) and unlinks when already paired; the last row cannot link. (AC4)
- `addSet` clones the last set as `working` and appends; `removeSet` removes by index but refuses when only one set remains. (AC6)
- `updateSet` patches reps/RIR/type; RIR clamps to 0–5. (AC6)
- `totalSets` sums set counts; `MIXED` flag derives from any non-working set. (AC1, AC2)
- `save()` calls `WorkoutRepository.saveWorkout` and sets `saveState`; a throwing mock yields `.error`. (AC12)

**Unit tests — `RoutineBuilderModel`:**
- `incWeeks` / `decWeeks` adjust `weeks`; `decWeeks` clamps at 1. (AC8)
- `addWorkout` appends a day; `addRestDay` appends a rest day; `removeDay` removes by index. (AC9)
- `workoutsPerWeek` excludes rest days. (AC8)
- `save()` calls `RoutineRepository.saveRoutine` and sets `saveState`. (AC12)

**Unit tests — `FolderBuilderModel`:**
- `select(color:)` updates `colorToken`. (AC11)
- `save()` calls `FolderRepository.saveFolder` and sets `saveState`. (AC12)

**Acceptance / UI tests:**
- Workout Builder shows eyebrow `NEW WORKOUT`, editable name, PUSH/PULL/LEGS chips (single active), `EXERCISES · n` / `SETS` header, and the seeded exercise rows. (AC1, AC2)
- Tapping a row opens the Set Editor with the correct eyebrow/title; editing reps/RIR/type and adding/removing sets reflects back into the row's sub-line and the `SETS` count. (AC3, AC6)
- Tapping ⛓ groups two rows into a `SUPERSET · 2 MOVES` card badged A/B; UNLINK dissolves it. (AC4)
- `+ ADD EXERCISE` opens the Exercise Picker; added rows are dimmed with ✓, selecting two and confirming appends two rows; `Add 2 selected` enables only when a selection exists. (AC5, AC7)
- Routine Builder shows `NEW ROUTINE`, the week stepper (− clamps at 1), `WEEKLY SPLIT` / `WORKOUTS / WK` count excluding rest days, and the seeded day list; `+ Add rest day` adds a dashed rest row; `+ ADD / CREATE WORKOUT` opens the Workout Picker. (AC8, AC9, AC10)
- Workout Picker shows the pinned `Create new workout` card + `FROM YOUR LIBRARY` list; picking appends a day and dismisses. (AC10)
- Folder screen shows `NEW FOLDER`, the colored preview, editable centered name, and the 6 swatches; selecting a swatch updates the preview. (AC11)
- Each builder's Cancel pops back without saving; Save invokes the repository and pops. (AC12)
- Loading / empty / error states for the picker sheets render as specified. (Edge cases)
- Snapshot/visual parity under both Coastal and Mint palettes. (AC13)

## Files that will change
- `Pulse/Features/Builders/WorkoutBuilderView.swift` (new)
- `Pulse/Features/Builders/WorkoutBuilderModel.swift` (new `@Observable` model)
- `Pulse/Features/Builders/SetEditorSheet.swift` (new sheet view)
- `Pulse/Features/Builders/ExercisePickerSheet.swift` (new sheet view)
- `Pulse/Features/Builders/RoutineBuilderView.swift` (new)
- `Pulse/Features/Builders/RoutineBuilderModel.swift` (new `@Observable` model)
- `Pulse/Features/Builders/WorkoutPickerSheet.swift` (new sheet view)
- `Pulse/Features/Builders/FolderBuilderView.swift` (new)
- `Pulse/Features/Builders/FolderBuilderModel.swift` (new `@Observable` model)
- `Pulse/Features/Builders/BuilderModels.swift` (new display/draft structs: `BuilderExercise`, `BuilderDay`, `WorkoutTag`, `FolderColor`, `SaveState`) — or co-located with the models
- `Pulse/Core/Data/WorkoutRepository.swift` (protocol — coordinated with BAK-6; may already exist)
- `Pulse/Core/Data/RoutineRepository.swift` (protocol — coordinated with BAK-6)
- `Pulse/Core/Data/FolderRepository.swift` (protocol — coordinated with BAK-6)
- `Pulse/Core/Data/ExerciseCatalogRepository.swift` (protocol — shared with BAK-10/BAK-6)
- `Pulse/Core/Data/Mocks/MockWorkoutRepository.swift` (in-memory mock + sample data — coordinated with BAK-6)
- `Pulse/Core/Data/Mocks/MockRoutineRepository.swift` (in-memory mock + sample data — coordinated with BAK-6)
- `Pulse/Core/Data/Mocks/MockFolderRepository.swift` (in-memory mock — coordinated with BAK-6)
- `Pulse/Core/Data/Mocks/MockExerciseCatalogRepository.swift` (shared mock — coordinated with BAK-10/BAK-6)
- `PulseTests/WorkoutBuilderModelTests.swift` (new)
- `PulseTests/RoutineBuilderModelTests.swift` (new)
- `PulseTests/FolderBuilderModelTests.swift` (new)
- `PulseUITests/BuildersTests.swift` (new acceptance/UI tests)
