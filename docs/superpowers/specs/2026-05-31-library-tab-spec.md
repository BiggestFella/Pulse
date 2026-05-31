# Library Tab — Spec

**Linear:** BAK-10  |  **Date:** 2026-05-31  |  **Status:** Draft for review

## Overview
The Library tab is the third tab in Pulse's bottom tab bar (Today · Library · Plan · You). It is the browse-and-organize surface for everything the lifter has built: folders (which group workouts and surface the active program), recently used workouts, and the full exercise catalog grouped by muscle. From the top bar, a **+** button opens the **Create chooser** sheet (Workout / Routine / Folder). This feature delivers the Library screen, its filter behavior, and the Create chooser sheet, all bound to repository protocols backed by in-memory mocks (real Supabase wiring is BAK-6).

## User story
As a lifter, I want to browse my folders, recent workouts, and exercise catalog in one place — and start creating new workouts, routines, or folders — so that I can find and organize my training without hunting through screens.

## Acceptance criteria
1. The Library tab shows a top bar with the eyebrow label **LIBRARY** and a **+** action on the right, an H1 reading **Library.**, a decorative (non-functional, placeholder-only) search field, and a horizontal filter-chip row with chips **All / Workouts / Folders / Exercises / Programs** (default selected: **All**).
2. With the **All** filter active, the body shows a **FOLDERS · {count}** section listing each folder (folder icon tinted by the folder color + name + sub-line), followed by a **RECENT** section header (with a trailing **BROWSE EXERCISES →** affordance) and a list of recent workout rows (name + sub-line).
3. With the **Exercises** filter active, the body shows the exercise catalog grouped by muscle, each group preceded by an eyebrow header `{MUSCLE} · {count}`; each row shows the exercise name, a sub-line of `{equipment}` plus ` · N variations` when the exercise has more than zero variations, and a PR badge when the exercise has a tracked PR.
4. Tapping an exercise row (Exercises filter) navigates to Exercise Detail for that exercise id.
5. Tapping a folder row that represents the active program navigates to Program Detail; tapping a non-program folder navigates to that folder's contents (Folder Detail) — see Open Questions if Folder Detail is out of this feature's scope.
6. Tapping the **BROWSE EXERCISES →** affordance switches the active filter to **Exercises**.
7. Tapping **+** in the top bar presents the **Create chooser** sheet over a dimmed, tap-to-close backdrop, with a drag handle, eyebrow **CREATE NEW**, title **What are you making?**, and three rows — **Workout** (accent tint), **Routine** (accent-2 tint), **Folder** (ink-faint tint) — each with name, sub-line, and a leading icon tile.
8. Selecting **Workout** in the chooser dismisses the sheet and navigates to the Workout Builder; selecting **Routine** dismisses and navigates to the Routine Builder; selecting **Folder** dismisses and navigates to the Folder creation screen.
9. While the model is loading data, the body shows a loading state (no folder/catalog rows rendered, no error); when both folders and recent workouts are empty under **All**, an empty state is shown instead of bare section headers; when the repository call fails, an error state with a retry affordance is shown.
10. All colors, spacing, radii, and typography come from `Theme` tokens; the screen renders correctly in both Coastal and Mint palettes with no hardcoded colors.

## Screen / UX behavior
**Top bar.** Geist Mono eyebrow `LIBRARY` (uppercase, letter-spaced) on the left; a **+** icon button on the right that opens the Create chooser sheet. Below it, the H1 **Library.** in Hanken Grotesk.

**Search field.** A pill/rounded-rect (radius per card token) with `surface` background and an `ink-faint` border, containing placeholder text in `ink-soft`. This release is **decorative only** — it does not accept input or filter results. It exists to lock the layout (filtering is a future feature; see Open Questions).

**Filter chips.** A horizontally scrollable row of `FilterChip`s: `All`, `Workouts`, `Folders`, `Exercises`, `Programs`. The selected chip uses the active chip style (per design system); the rest use the inactive style. Selecting a chip updates `selectedFilter` and re-renders the body.
- For this feature, the body has two concrete renderings: **Exercises** (catalog grouped by muscle) and **everything else** (the "All / default" rendering). `Workouts`, `Folders`, and `Programs` render the default All view in this release; narrowing those to filtered subsets is deferred (see Open Questions).

**Default (All / Workouts / Folders / Programs) body.** A vertical scroll:
- Eyebrow `FOLDERS · {n}` then one `row` per folder: a `FolderIcon` tinted with the folder's color token, name (`nm-name`), sub (`nm-sub`), trailing chevron. Program folder → Program Detail; others → Folder Detail.
- A header row with eyebrow `RECENT` on the left and a tappable eyebrow `BROWSE EXERCISES →` on the right (switches filter to Exercises).
- One `row` per recent workout: name + sub (e.g. `7 exercises · used today`), trailing chevron.

**Exercises body.** A vertical scroll of muscle groups in catalog order. Each group: eyebrow `{MUSCLE} · {count}`, then rows with name, sub (`{equip}` + ` · N variations` when `variations.count > 0`), an optional `PrTag` when the exercise has a PR, and a trailing chevron. Row tap → Exercise Detail (`exdetail:<id>`).

**Create chooser sheet.** Standard sheet chrome: dim backdrop (tap to close), top drag handle, top radius per sheet token, eyebrow `CREATE NEW`, title `What are you making?`, and a ✕ close control. Three rows, each with a 38pt rounded icon tile (Workout = `accent` fill / `onAccent` glyph; Routine = `accent-2` fill / `onAccent` glyph; Folder = `ink-faint` fill / `ink` glyph), a name, a sentence-case sub-line, and a trailing chevron:
- Workout — "A single session you can run" → Workout Builder.
- Routine — "A multi-week program of workouts" → Routine Builder.
- Folder — "Group workouts together" → Folder creation.

**Navigation.** Library is a tab root hosting a `NavigationStack`. Row taps push Exercise Detail / Program Detail / Folder Detail (those destination screens are separate features). Create chooser selections dismiss the sheet, then push the relevant Builder. Screen mount uses the standard fade+rise; the sheet slides up.

**Motion / styling.** Buttons and chips follow the design-system pill style (2px ink border + hard offset shadow, press-down translate). On any accent-filled element, highlight text uses `onAccent`, never `accent2`.

## Data & state
**Model:** `@Observable final class LibraryModel` in `Pulse/Features/Library/`.

State:
```swift
enum LibraryFilter: String, CaseIterable { case all, workouts, folders, exercises, programs }
enum LoadState { case loading, loaded, error(String) }

@Observable final class LibraryModel {
    var selectedFilter: LibraryFilter = .all
    var loadState: LoadState = .loading
    var folders: [LibraryFolder] = []
    var recentWorkouts: [WorkoutSummary] = []
    var catalog: [MuscleGroupCatalog] = []   // grouped by muscle
    var isCreateSheetPresented = false
    // intent: load(), retry(), select(filter:), presentCreate(), dismissCreate()
}
```

View-facing display structs (UI-first; not necessarily the final persisted shape):
- `LibraryFolder { id, name, sub, colorToken, isProgram: Bool }`
- `WorkoutSummary { id, name, sub }`
- `MuscleGroupCatalog { muscle: String, items: [CatalogExercise] }`
- `CatalogExercise { id, name, equipment: String, variationCount: Int, hasPR: Bool }` (derived from `Exercise` in `Core/Models`, with `top`/`pr` mapped to `hasPR`).

**Repository protocols (defined in BAK-6; this feature consumes them via mocks):**
- `LibraryRepository.folders() async throws -> [LibraryFolder]`
- `LibraryRepository.recentWorkouts() async throws -> [WorkoutSummary]`
- `ExerciseCatalogRepository.catalog() async throws -> [MuscleGroupCatalog]`

`LibraryModel.load()` calls these (in parallel where sensible), sets `loadState = .loaded` on success, `.error` on throw. `retry()` re-invokes `load()`.

**Mock data** (in-memory mock conforming to the protocols, lives with the data layer / mock fixtures from BAK-6, mirroring the design prototype):
- Folders: `Push / Pull / Legs` ("6 workouts · active program", accent, isProgram=true), `Cardio & Conditioning` ("4 workouts", accent-2), `One-offs` ("7 workouts", ink-faint).
- Recent: `Chest & Tris` ("7 exercises · used today"), `Back & Bis` ("6 exercises · 5d ago"), `Leg day` ("5 exercises · 7d ago").
- Catalog: Chest (5), Back, Legs, Shoulders, Triceps groups from the prototype's `EXERCISE_CATALOG`, with equipment, variation counts, and PR flags (`bench`, `pulldown`, `deadlift`, `squat`, `ohp` flagged PR).

**Dependencies:** Design System tokens & components — `FilterChip`, `FolderIcon`, `PrTag`, row, eyebrow, `Sheet` (BAK-7). Repository protocols + in-memory mocks + sample data (BAK-6).

## Out of scope
- Functional search / text filtering (the search field is decorative this release).
- Distinct filtered renderings for `Workouts`, `Folders`, `Programs` chips (they render the default All view for now).
- Exercise Detail, Program Detail, Folder Detail screens and the Workout/Routine/Folder Builders (separate features; this feature only routes to them).
- Creating, renaming, deleting, or reordering folders/workouts from the Library list (no swipe actions, no context menus).
- Real Supabase persistence and any write operations (BAK-6).
- Live Activity / Widgets (BAK-14).
- The Today, Plan, and You tabs.

## Edge cases
- **Empty all-view:** zero folders and zero recent workouts → show an empty state, not naked section headers.
- **Empty catalog:** Exercises filter with zero exercises → empty state for the catalog.
- **Group with one item:** the `· N variations` suffix only appears when `variationCount > 0`; a single variation still reads `· 1 variations` per the prototype (see Open Questions on pluralization).
- **Exercise with no PR:** no `PrTag` rendered; layout unaffected.
- **Loading:** body shows loading affordance; `+`/Create chooser still openable.
- **Error:** repository throw → error state with retry; sheet still openable.
- **Theme switching:** switching Coastal ↔ Mint (from You → Palette) recolors folder icons, chips, sheet tiles, and PR badges live via tokens; no hardcoded hex anywhere.
- **Sheet dismissal:** tapping the backdrop, the ✕, or dragging down dismisses the Create chooser without navigating.
- **Long folder/exercise names:** rows truncate gracefully (single line, tail truncation) without breaking the chevron alignment.

## Open questions
1. Should the `Workouts`, `Folders`, and `Programs` filter chips render distinct filtered lists in this release, or is rendering the default All view acceptable until a later filtering feature?
2. What does tapping a **non-program folder** (Cardio, One-offs) navigate to? The prototype only wires the program folder (→ Program Detail) and does nothing for others. Is Folder Detail in scope for BAK-10 or a separate feature?
3. Is the search field expected to become functional in a near-term feature, and if so should this spec reserve the model hooks now, or leave it purely decorative?
4. What defines the **RECENT** list — most-recently-run workouts, most-recently-edited, or a manual recents cap (e.g. last 3/5)? The prototype hardcodes three.
5. Variation count pluralization: the prototype prints `· 1 variations`. Should the shipped copy pluralize correctly (`1 variation`)?
6. PR badge source: should `hasPR` derive from `Exercise.top > 0`, an explicit `pr` flag, or the Personal Records data set? The prototype uses an explicit `pr:true` flag inconsistently with `top`.
7. Folder sub-line counts ("6 workouts") — are these computed from folder contents or stored? Affects the mock and the eventual repository shape.

## Tests required
**Unit tests (`LibraryModel`):**
- `load()` populates `folders`, `recentWorkouts`, `catalog` from the mock repos and sets `loadState = .loaded`. (AC2, AC3)
- `load()` on a failing mock sets `loadState = .error`; `retry()` re-runs and recovers with a now-succeeding mock. (AC9)
- Default `selectedFilter == .all`. (AC1)
- `select(.exercises)` updates `selectedFilter`; the catalog grouping is exposed in catalog order. (AC3)
- `presentCreate()` sets `isCreateSheetPresented = true`; `dismissCreate()` clears it. (AC7)
- `CatalogExercise` mapping: `variationCount > 0` drives the variations suffix flag; `hasPR` maps from the source exercise. (AC3)
- Folder `isProgram` flag correctly identifies the active-program folder. (AC5)

**Acceptance / UI tests:**
- Library tab shows eyebrow `LIBRARY`, H1 `Library.`, decorative search field, and the five filter chips with `All` selected. (AC1)
- All view renders a `FOLDERS · 3` header, three folder rows, a `RECENT` header with `BROWSE EXERCISES →`, and recent workout rows. (AC2)
- Tapping `BROWSE EXERCISES →` selects the Exercises chip and shows the grouped catalog. (AC6, AC3)
- Exercises view shows muscle-group headers with counts, variation sub-lines only where applicable, and PR badges on flagged exercises. (AC3)
- Tapping an exercise row routes to Exercise Detail for the correct id. (AC4)
- Tapping the program folder routes to Program Detail. (AC5)
- Tapping `+` presents the Create chooser with eyebrow `CREATE NEW`, title `What are you making?`, and three rows; backdrop tap dismisses it. (AC7)
- Selecting Workout / Routine / Folder dismisses the sheet and routes to the matching Builder/screen. (AC8)
- Loading, empty, and error states render as specified. (AC9)
- Snapshot/visual parity holds under both Coastal and Mint palettes. (AC10)

## Files that will change
- `Pulse/Features/Library/LibraryView.swift` (replace placeholder with the real screen)
- `Pulse/Features/Library/LibraryModel.swift` (new `@Observable` model)
- `Pulse/Features/Library/CreateChooserSheet.swift` (new Create chooser sheet view)
- `Pulse/Features/Library/LibraryRowViews.swift` (new — folder row, recent row, catalog row subviews; optional split)
- `Pulse/Core/Data/LibraryRepository.swift` (protocol — coordinated with BAK-6; may already exist there)
- `Pulse/Core/Data/ExerciseCatalogRepository.swift` (protocol — coordinated with BAK-6)
- `Pulse/Core/Data/Mocks/MockLibraryRepository.swift` (in-memory mock + sample data — coordinated with BAK-6)
- `Pulse/Core/Data/Mocks/MockExerciseCatalogRepository.swift` (in-memory mock + sample data — coordinated with BAK-6)
- `Pulse/Core/Models/LibraryModels.swift` (new display structs `LibraryFolder`, `WorkoutSummary`, `MuscleGroupCatalog`, `CatalogExercise`, `LibraryFilter`) — or co-located with the model
- `PulseTests/LibraryModelTests.swift` (new unit tests)
- `PulseUITests/LibraryTabTests.swift` (new acceptance/UI tests)
