# Library Folders + Workout Builder Fixes — Design

**Date:** 2026-06-11
**Status:** Approved (design); pending spec review
**Source:** Testing feedback (Library not wired to DB; builder reorder/selection order; reps editing UX)

## Overview

Two related but independently shippable bodies of work, captured in one spec and
split into **two implementation plans / two PRs**:

- **Part A — Library folders + database.** The Library tab is only half-wired:
  the exercise catalog loads from Supabase, but Folders and Recent Workouts are
  hard-coded mock data, and folders were never modeled in the database at all.
  Part A builds the folder data layer end-to-end (migration → model → repository
  → RLS → UI) and wires Recent Workouts to real sessions.
- **Part B — Workout builder & set-editing fixes.** Small, unrelated UI bugs in
  the workout builder: exercises can't be reordered, multi-select doesn't
  preserve tap order, and the reps field can't be cleared / lacks +/- steppers /
  has misaligned column headers.

Part B can ship first and independently; Part A is the larger feature.

---

## Part A — Library folders + database

### Problem (root cause)

- `LibraryView.swift:30` always instantiates `MockLibraryRepository()`, ignoring
  the app's mock-vs-live `RepositoryContainer`. So Folders + Recent Workouts show
  hard-coded sample data even on the live Supabase path.
- There is **no folder concept in the database** — no `folders` table, no
  `Folder` domain model, no `SupabaseFolderRepository`. The existing
  `FolderRepository` protocol has only a write-only `saveFolder(...)` consumed by
  the mock; `RepositoryContainer` always uses `InMemoryFolderRepository`.
- The `LibraryFolder` UI projection carries an `isProgram` flag that conflates
  Programs and user folders in one grid.

### Confirmed product decisions

1. **A folder is a generic container** holding workouts, programs, **and** other
   folders (nesting).
2. **Arbitrary nesting depth.**
3. **Deleting a folder cascade-deletes its contents** (workouts, programs,
   sub-folders), behind a strong "delete N items" confirmation.
4. **A "Move to folder" action** lets users relocate items/folders (including to
   the Library root) — e.g. to pull things out before a destructive delete.

### Data model — adjacency-list tree (chosen approach)

Rejected alternatives: a polymorphic `folder_items` join table (loses FK
integrity, multi-parent not needed — YAGNI) and a closure table (heavier writes
than simple drill-down needs).

New migration `supabase/migrations/0007_folders.sql` (0006 already exists on this
branch — confirm the next free number at implementation time):

```sql
create table folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_folder_id uuid references folders(id) on delete cascade,  -- null = top level
  name text not null,
  color_token text not null,           -- FolderColor raw value: blue|orange|teal|yellow|pink|purple
  "order" int not null default 0,
  created_at timestamptz not null default now()
);

alter table workouts add column folder_id uuid references folders(id) on delete cascade;
alter table programs add column folder_id uuid references folders(id) on delete cascade;

alter table folders enable row level security;
create policy "own_folders" on folders
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

Mapping of decisions to schema:

- **Cascade delete** is entirely DB-driven via `ON DELETE CASCADE` on the three
  FKs (`parent_folder_id`, `workouts.folder_id`, `programs.folder_id`). Deleting
  a folder row destroys its sub-folders, workouts, and programs recursively. No
  app logic needed for the destruction itself.
- **Arbitrary depth** via the self-referencing `parent_folder_id`.
- **Holds three child types** — each child carries its own parent pointer; a
  folder's contents are the three "children where parent = me" queries.
- **Orthogonal axes** — `workouts.program_id` stays NOT NULL; `folder_id` is a
  separate organizing axis. The current builder→active-program save path
  (`SupabaseWorkoutRepository.saveWorkout`) is unchanged.

### Domain models — `Pulse/Core/Models/Folder.swift`

```swift
struct Folder: Identifiable, Equatable {
    let id: UUID
    var name: String
    var color: FolderColor      // existing enum in BuilderModels.swift
    var parentID: UUID?
}

/// A folder's direct children — the three child types the Library renders.
struct FolderContents: Equatable {
    var folders: [Folder]
    var workouts: [Workout]
    var programs: [Program]
}
```

### Repository layer

Replace the write-only `FolderRepository` with:

```swift
protocol FolderRepository {
    func contents(of parentID: Folder.ID?) async throws -> FolderContents   // nil = Library root
    func createFolder(name: String, color: FolderColor, parentID: Folder.ID?) async throws -> Folder
    func renameFolder(id: Folder.ID, name: String, color: FolderColor) async throws
    func moveFolder(id: Folder.ID, toParent: Folder.ID?) async throws        // cycle-guarded
    func moveWorkout(id: Workout.ID, toFolder: Folder.ID?) async throws
    func moveProgram(id: Program.ID, toFolder: Folder.ID?) async throws
    func deleteFolder(id: Folder.ID) async throws                            // DB cascades children
}
```

Implementations:

- **`SupabaseFolderRepository`** (new, in `Core/Data/Supabase/`). `contents(of:)`
  runs three filtered selects (`.eq("folder_id"/"parent_folder_id", …)`, or
  `.is(..., value: nil)` at root). `moveFolder` walks the target's parent chain
  and throws `RepositoryError` if the moved folder appears in it (cycle guard).
  Cross-user folder references are blocked by the `own_folders` RLS select policy.
  Folder rows decode via a new `FolderRow` in `Rows.swift`; writes via
  `WriteRows.swift`, matching existing repository patterns.
- **`InMemoryFolderRepository`** (extend existing). Same operations over arrays,
  keeping the `shouldThrow` test hook. Existing test usage of `saveFolder`
  migrates to `createFolder`.

Wiring:

- `RepositoryContainer` (`AppEnvironment.swift`) flips `folders` from
  "always in-memory" to "Supabase on live, in-memory on mock", like every other
  repo.
- **Delete `LibraryRepository` + `MockLibraryRepository`.** `LibraryModel`
  composes `repos.folders` (folders), `repos.sessions` (recent workouts), and
  `repos.exercises`/`repos.prs` (catalog) — removing the hard-coded-mock root
  cause.
- `FolderBuilderModel.save()` switches to `createFolder(…, parentID:)`, passing
  the folder currently being browsed (nil at root).

### UI & navigation

- **Drill-down via the existing `NavigationStack`.** `LibraryModel` is the root
  (`parentID == nil`). Each pushed `.folderDetail(folderID:)` is backed by a
  folder-contents model loading `repos.folders.contents(of: folderID)`.
  Breadcrumbs come free from the nav stack; arbitrary depth = more pushes.
- **Each folder screen renders three child groups in order:** Folders (tap →
  push `.folderDetail`), Workouts (tap → workout), Programs (tap →
  `.programDetail`). Empty folder → empty state with an add hint.
- **Create** — existing `+` / `CreateChooserSheet`; the chosen builder receives
  the current `parentID`, so new items land in the folder being viewed.
- **Move** — a row context action (swipe or `•••` menu) opens a "Move to folder"
  picker: a compact folder tree (excluding the item itself and, for folders, its
  descendants) plus a "Library root" option → `moveFolder/moveWorkout/moveProgram`.
- **Delete** — destructive context action. Non-empty folder shows a confirmation:
  *"Delete '<name>' and the N items inside it? This can't be undone."* → cascade.
- The `isProgram` flag on `LibraryFolder` is removed; folders and programs are
  now distinct child types.

### Recent Workouts

Replace the mock with `repos.sessions.fetchSessions(limit:)`, mapped to
`WorkoutSummary` (workout name + relative-date subline), newest first.

### Part A acceptance criteria

- On the live path, Library shows the user's real folders, programs, and recent
  sessions — not sample data.
- Create a folder (at root and inside another folder); it persists and appears.
- Nest folders to arbitrary depth and navigate in/out via the nav stack.
- Move a workout, a program, and a folder into another folder and back to root.
- Moving a folder into its own descendant is rejected.
- Deleting a non-empty folder shows a count confirmation and cascade-deletes its
  contents.
- A user only ever sees their own folders (RLS).

---

## Part B — Workout builder & set-editing fixes

### B1. Preserve exercise selection order
`ExercisePickerSheet` tracks selection in `Set<Exercise.ID>` (`:16`), which is
unordered, so `Array(selected)` loses tap order before the builder sees it. Switch
to an order-preserving selection (an array; append on tap, remove on deselect) so
`onConfirm` returns exercises in the order tapped. `WorkoutBuilderModel.addExercises`
already appends in received order — no model change needed.

### B2. Reorder exercises in the builder
No reorder support exists; `WorkoutBuilderView.swift:158` renders a decorative
`☰` handle with no `.onMove`. Add `.onMove` + an `EditButton` (or drag) and a
`move(from:to:)` on `WorkoutBuilderModel.items`, wiring the existing handle.

### B3. Reps editing
In `SetEditorSheet.swift`:
- **Can't clear the field** — `format: .number` on the `Int` binding (`:80-88`)
  blocks an empty intermediate state. Replace with a `Binding<String>` + focus
  state allowing empty while editing; commit on blur (empty → 0, reusing the
  existing `max(0,)` clamp in `updateSet`).
- **No +/- steppers** — RIR already has +/- (`:90-101`); reps doesn't. Reuse the
  active session's `StepperField` (`ActiveSetView.swift:199-225`) for reps, for
  parity.
- **Misaligned headers** — header row uses `Spacer()`-spread labels (`:41-47`)
  while the data row uses fixed-width columns (`:77-114`). Give the header the
  same fixed column widths as the data row so REPS/RIR labels align with their
  fields.

### Part B acceptance criteria

- Selecting exercises A, B, C in the picker adds them in that order.
- Builder rows can be dragged to reorder; order persists on save.
- The reps field can be cleared to empty and retyped; +/- steppers adjust reps;
  REPS/RIR labels visually align with their fields.

---

## Testing

Acceptance-criteria driven, per CLAUDE.md. UI/acceptance tests pinned to the mock
path (`-uiMock`), consistent with the repo convention.

- **Repository:** `InMemoryFolderRepository` unit tests — create, nest, move,
  cycle rejection, cascade-delete counts.
- **Models:** `LibraryModel` / folder-contents model — loads three child groups,
  root vs nested, empty states, error path. Builder model — selection-order
  preservation, `move(from:to:)`, reps clamp + empty-string handling.
- **Gate:** per the known UI-test-runner defect, use `-only-testing:PulseTests`
  as the CI gate.

## Out of scope

- Reordering folder *contents* (the `order` column exists for a future drag-sort;
  not part of this work).
- Redesigning the workout↔program relationship (folders are an orthogonal axis).
- Search wiring for the Library search field.
