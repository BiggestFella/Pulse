# Library Polish (#39 Follow-ups) — Design

**Date:** 2026-06-11
**Status:** Approved (design); pending spec review
**Source:** Code-review follow-ups deferred from PR #39 (Library folders + DB)
**Branch:** extends `feature/bak-27-library-folders` (PR #39) — these refine unmerged Part A code, committed to the same branch so #39 ships complete.

## Overview

Three user-facing polish items on the new Library folder feature, plus a reload
fix the work exposes. Performance items from the #39 review (move-picker N+1,
full `fetchWorkouts` for recents) are explicitly **out of scope** — invisible at a
solo user's data sizes; revisit if data grows.

## 1. Recent Workouts — relative-date subline

**Problem:** `LibraryModel.recent(_:workouts:)` sets each recent row's `sub` to
`"N sets"`. The mock originally showed a relative date ("5d ago"), which is more
useful for "recent".

**Change:** subline becomes `"<N> set(s) · <relative date>"`, where the relative
date is derived from `session.startedAt`:
- same day → `"Today"`
- previous day → `"Yesterday"`
- 2–6 days → `"N days ago"`
- 7+ days → `"D MMM"` (e.g. `"3 Jun"`)

**Testability:** the relative-date helper is a pure static function
`LibraryModel.relativeDay(_ date: Date, now: Date) -> String`. App code calls it
with `Date()`; `recent(_:workouts:now:)` gains a `now: Date = Date()` parameter so
tests pass a fixed reference date. Newest-first ordering is unchanged
(`fetchSessions` already returns newest first).

## 2. Delete confirmation — item count, and confirm only when non-empty

**Problem:** deleting a folder shows an unconditional generic alert ("…also
deletes everything inside it…") with no item count, even for empty folders.

**Change:** the decision moves into the model (testable), one method shared in
spirit by both `LibraryModel` and `FolderDetailModel`:

- `requestDelete(_ folder: LibraryFolder)` fetches `folderRepo.contents(of: folder.id)`.
- Let `n = contents.folders.count + contents.workouts.count + contents.programs.count`
  (direct children).
- If `n == 0` → delete immediately (`deleteFolder` + reload); no dialog.
- If `n > 0` → set `pendingDelete` to a value carrying the folder and `n`; the view
  binds its `.alert` to `pendingDelete`. Confirm copy:
  *"Delete "<name>" and the N item(s) inside it? This can't be undone."*
  (N = direct-children count; "inside it" reads correctly for direct children, and
  the cheap single `contents()` call is the same one used to decide empty-ness.)

A small value type carries the pending state:
```swift
struct PendingFolderDelete: Equatable { let folder: LibraryFolder; let itemCount: Int }
```
Both `LibraryModel` (root) and `FolderDetailModel` (detail) expose
`private(set) var pendingDelete: PendingFolderDelete?`, `func requestDelete(...)`,
`func confirmDelete()` (performs the delete + reload), and `func cancelDelete()`.

## 3. Edit folder (rename + recolor)

**Problem:** `renameFolder(id:name:color:)` exists in both repository
implementations but has no UI.

**Change — reuse `FolderBuilderView` in an edit mode:**
- `FolderBuilderModel` gains `var editingFolderID: Folder.ID? = nil` and an edit
  initializer `init(folders:editing:)` taking the folder to edit (seeds `name`,
  `colorToken`, `editingFolderID`, and `parentID` is irrelevant for edit).
  `save()` branches: if `editingFolderID != nil` → `renameFolder(id:name:color:)`,
  else → `createFolder(name:color:parentID:)`.
- `FolderBuilderView` shows eyebrow `"EDIT FOLDER"` and primary `"Save changes →"`
  when `editingFolderID != nil`, otherwise the existing create labels.
- New route `LibraryRoute.folderEdit(folderID: UUID, name: String, colorToken: String)`
  carries the folder's current values; `LibraryView.destination` builds the edit
  model from them. (`colorToken` is the `FolderColor` raw value; recovered via
  `FolderColor(rawValue:) ?? .default`.)
- An **"Edit"** button is added to the folder context menu in
  `FolderContentsSection` (alongside Move and Delete).

## 4. Reload-on-return (exposed by this work)

**Problem:** creating a folder via the pushed `FolderBuilderView` does not refresh
the Library on return — `LibraryView`'s `.task` runs once (`guard model == nil`),
so a newly created (or edited) folder isn't shown until another reload trigger.

**Change:** when a pushed builder pops back, the originating list reloads. The root
`LibraryView` reloads its model and bumps `refreshID` (which the existing
`FolderDetailView.onChange(of: refreshID)` already observes) when the navigation
`path` returns from a builder route. Concretely: `LibraryView` observes path
changes and, on a pop back to a non-builder top (or empty path), calls
`model.load()` and bumps `refreshID`. This makes **create and edit** both refresh
the visible list. (Move/delete already reload via their own paths.)

## Testing (acceptance-criteria driven)

- `LibraryModel.relativeDay(_:now:)` — Today / Yesterday / "N days ago" / "D MMM"
  boundaries with a fixed `now`.
- `LibraryModel.recent(_:workouts:now:)` — subline includes set count + relative date.
- `requestDelete` (on `LibraryModel`, with `InMemoryFolderRepository`) — empty
  folder deletes immediately (`pendingDelete` stays nil, folder gone); non-empty
  folder sets `pendingDelete` with the correct count and does NOT delete until
  `confirmDelete()`.
- `FolderBuilderModel` edit mode — `save()` with `editingFolderID` set calls
  `renameFolder` (folder's name/color change in the store) and does NOT create a
  new folder.

## Out of scope
- Move-picker N+1 `contents()` calls; full-table `fetchWorkouts` for recents
  (deferred perf — solo-app data sizes make these invisible).
- Recursive total-descendant count in the delete message (direct-children count is
  used; a recursive count would reintroduce a tree walk).
