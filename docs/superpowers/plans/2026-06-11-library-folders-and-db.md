# Library Folders + Database Implementation Plan (Part A)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Library tab reflect real data — build the folder data layer end-to-end (DB → model → repository → RLS → UI), wire Folders and Recent Workouts to live data, and remove the hard-coded mock that froze them.

**Architecture:** Folders are an adjacency-list tree (`folders.parent_folder_id` self-reference; nullable `folder_id` on `workouts`/`programs`). Folders hold workouts, programs, and sub-folders to arbitrary depth. Cascade delete is DB-driven via `ON DELETE CASCADE` on three FKs. The Library navigates the tree by drill-down, loading direct children per folder. `folder_id` is an organizing axis orthogonal to `workouts.program_id` (unchanged).

**Tech Stack:** SwiftUI (iOS 17+), Swift Concurrency, `@Observable` MVVM, Supabase (PostgREST), XCTest. Project generated via XcodeGen (`project.yml`); source folders are globbed. **New `.swift` files require `xcodegen generate` before they compile in the project** — each task that adds a file includes that step.

**Source spec:** `docs/superpowers/specs/2026-06-11-library-folders-and-builder-fixes-design.md` (Part A).

**Test command (unit gate):**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseTests test
```
`-only-testing:PulseTests` is mandatory (the PulseUITests runner crashes on the current Xcode/iOS — known defect). If the `iPhone 17` simulator is unavailable, run `xcrun simctl list devices available` and use the closest available iPhone.

**Guardrails for every task:** The working tree has an unrelated uncommitted change to `Pulse/App/AppShell.swift` and an untracked `.claude/` directory — NEVER stage them (`git add -A`/`.` forbidden; no stashing). Stage only the files each task names.

---

## File Structure

**Created:**
- `supabase/migrations/0007_folders.sql` — folders table, `folder_id` columns, RLS.
- `Pulse/Core/Models/Folder.swift` — `Folder`, `FolderContents` domain models + `FolderColor` (moved here from Builders).
- `Pulse/Core/Data/Supabase/SupabaseFolderRepository.swift` — live folder repository.
- `Pulse/Features/Library/FolderDetailView.swift` — pushed folder screen (View + `FolderDetailModel`).
- `Pulse/Features/Library/FolderContentsSection.swift` — shared rendering of a folder's three child groups (used by root + detail).
- `Pulse/Features/Library/MoveToFolderSheet.swift` — the "Move to folder" picker.
- `PulseTests/Core/Data/InMemoryFolderRepositoryTests.swift` — repository unit tests.
- `PulseTests/Features/Library/LibraryModelTests.swift` — model unit tests (if not already present; extend if it is).

**Modified:**
- `Pulse/Features/Builders/BuilderModels.swift` — remove `FolderColor` (moved to Core/Models).
- `Pulse/Core/Data/Repositories/FolderRepository.swift` — expand the protocol.
- `Pulse/Core/Data/Mock/MockStore.swift` — add folder storage + membership maps.
- `Pulse/Core/Data/Mock/InMemoryFolderRepository.swift` — implement the expanded protocol.
- `Pulse/Core/Data/Supabase/Rows/Rows.swift` — add `FolderRow`.
- `Pulse/Core/Data/Supabase/Rows/WriteRows.swift` — add `FolderWriteRow`, `FolderIDUpdate`.
- `Pulse/App/AppEnvironment.swift` — wire `folders` per mock/live.
- `Pulse/Features/Builders/FolderBuilderModel.swift` — use `createFolder(…, parentID:)`.
- `PulseTests/Features/Builders/FolderBuilderModelTests.swift` — update to the new API.
- `Pulse/Features/Library/LibraryModel.swift` — compose `folders`/`sessions`/`workouts`/`exercises`/`prs`; load contents + recent.
- `Pulse/Features/Library/LibraryModels.swift` — drop `isProgram` from `LibraryFolder`; add a `FolderColor` tint.
- `Pulse/Features/Library/LibraryComponents.swift` / `LibraryRowViews.swift` — `FolderIcon`/`FolderRow` use `FolderColor`; add workout/program rows.
- `Pulse/Features/Library/LibraryView.swift` — stop constructing `MockLibraryRepository`; render contents; create-with-parent; nav.

**Deleted:**
- `Pulse/Features/Library/LibraryRepository.swift` — `LibraryRepository` + `MockLibraryRepository` (responsibilities move to `FolderRepository` + `SessionRepository`).

---

## Task 1: Database migration

**Files:**
- Create: `supabase/migrations/0007_folders.sql`

No automated test (schema). Migrations are applied to Supabase manually via the dashboard SQL editor (no local psql/docker in this project).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/0007_folders.sql`:

```sql
-- Pulse folders (BAK-27): a generic container tree for the Library. Folders hold
-- workouts, programs, and sub-folders to arbitrary depth (adjacency list).
-- Deleting a folder cascade-deletes its sub-folders, workouts, and programs.

create table folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_folder_id uuid references folders(id) on delete cascade,  -- null = top level
  name text not null,
  color_token text not null,           -- FolderColor raw value: blue|orange|teal|yellow|pink|purple
  "order" int not null default 0,
  created_at timestamptz not null default now()
);

-- Organizing axis, orthogonal to workouts.program_id (which stays NOT NULL).
alter table workouts add column folder_id uuid references folders(id) on delete cascade;
alter table programs add column folder_id uuid references folders(id) on delete cascade;

-- RLS: owner-scoped, same pattern as programs/sessions/plan_entries.
alter table folders enable row level security;
create policy "own_folders" on folders
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/0007_folders.sql
git commit -m "feat(data): folders table + folder_id columns + RLS [BAK-27]"
```

- [ ] **Step 3: Flag for manual application**

Report to the controller (who relays to the human) that `0007_folders.sql` must be applied to the Supabase project via the dashboard SQL editor before the live path will work. The mock path needs no migration.

---

## Task 2: Domain models (`Folder`, `FolderContents`) + relocate `FolderColor`

**Files:**
- Create: `Pulse/Core/Models/Folder.swift`
- Modify: `Pulse/Features/Builders/BuilderModels.swift`
- Test: `PulseTests/Core/Models/FolderTests.swift` (create)

`FolderColor` currently lives in `Pulse/Features/Builders/BuilderModels.swift`. The new `Folder` domain model needs it, and a domain model must not depend on a feature folder, so move the enum to `Core/Models`. Everything is one Swift module, so references elsewhere keep compiling unchanged.

- [ ] **Step 1: Write the failing test**

Create `PulseTests/Core/Models/FolderTests.swift`:

```swift
import XCTest
@testable import Pulse

final class FolderTests: XCTestCase {
    func testFolderColorRawValuesAreTheStoredTokens() {
        // color_token in the DB stores these exact raw values.
        XCTAssertEqual(FolderColor.blue.rawValue, "blue")
        XCTAssertEqual(FolderColor(rawValue: "purple"), .purple)
        XCTAssertEqual(Set(FolderColor.allCases.map(\.rawValue)),
                       ["blue", "orange", "teal", "yellow", "pink", "purple"])
    }

    func testFolderContentsEmptyHelper() {
        let empty = FolderContents(folders: [], workouts: [], programs: [])
        XCTAssertTrue(empty.isEmpty)
        let nonEmpty = FolderContents(
            folders: [Folder(id: UUID(), name: "A", color: .blue, parentID: nil)],
            workouts: [], programs: [])
        XCTAssertFalse(nonEmpty.isEmpty)
    }
}
```

- [ ] **Step 2: Move `FolderColor` and create the models**

In `Pulse/Features/Builders/BuilderModels.swift`, DELETE the entire `enum FolderColor { … }` block (the one with `case blue, orange, teal, yellow, pink, purple`, `static let default`, and `var hex`).

Create `Pulse/Core/Models/Folder.swift`:

```swift
import Foundation

/// The six fixed brand swatches a folder can take. Hex is the source value;
/// `Theme` exposes the matching `Color` so views never read hex directly. The
/// raw value is what the `folders.color_token` column stores.
enum FolderColor: String, CaseIterable, Equatable {
    case blue, orange, teal, yellow, pink, purple

    static let `default`: FolderColor = .blue

    var hex: String {
        switch self {
        case .blue:   return "#26B6F6"
        case .orange: return "#FF6A1F"
        case .teal:   return "#00D9B8"
        case .yellow: return "#FFCC33"
        case .pink:   return "#FF4D6D"
        case .purple: return "#9B6BFF"
        }
    }
}

/// A Library folder. Tree membership is the parent pointer (`parentID == nil` =
/// top level). Folders hold workouts, programs, and sub-folders.
struct Folder: Identifiable, Equatable {
    let id: UUID
    var name: String
    var color: FolderColor
    var parentID: UUID?
}

/// A folder's direct children — the three child types the Library renders.
struct FolderContents: Equatable {
    var folders: [Folder]
    var workouts: [Workout]
    var programs: [Program]

    var isEmpty: Bool { folders.isEmpty && workouts.isEmpty && programs.isEmpty }
}
```

- [ ] **Step 3: Regenerate the project (new files) and run the test**

```
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/FolderTests test
```
Expected: BUILD SUCCEEDED, `FolderTests` pass. (If `FolderColor` move caused a duplicate-definition error, ensure it was removed from `BuilderModels.swift`.)

- [ ] **Step 4: Commit**

```bash
git add Pulse/Core/Models/Folder.swift Pulse/Features/Builders/BuilderModels.swift PulseTests/Core/Models/FolderTests.swift Pulse.xcodeproj
git commit -m "feat(data): Folder/FolderContents models; move FolderColor to Core [BAK-27]"
```

---

## Task 3: Expand `FolderRepository` protocol + `MockStore` folder storage

**Files:**
- Modify: `Pulse/Core/Data/Repositories/FolderRepository.swift`
- Modify: `Pulse/Core/Data/Mock/MockStore.swift`

This task only changes the protocol surface and the mock backing store; the in-memory implementation lands in Task 4. It temporarily breaks compilation of `InMemoryFolderRepository`/`FolderBuilderModel` until Tasks 4–5, so **this task does not build or commit on its own** — its files are staged here and committed together with Task 4 (which restores a green build).

- [ ] **Step 1: Replace the protocol**

Replace the entire contents of `Pulse/Core/Data/Repositories/FolderRepository.swift`:

```swift
import Foundation

/// Library folders — a generic container tree (workouts, programs, sub-folders).
/// `contents(of:)` returns the direct children of a folder (`nil` = Library root).
/// Reads/writes are owner-scoped (RLS on the live path).
protocol FolderRepository {
    func contents(of parentID: Folder.ID?) async throws -> FolderContents
    func createFolder(name: String, color: FolderColor, parentID: Folder.ID?) async throws -> Folder
    func renameFolder(id: Folder.ID, name: String, color: FolderColor) async throws
    /// Reparent a folder. Throws if `newParent` is the folder itself or a descendant (cycle).
    func moveFolder(id: Folder.ID, toParent newParent: Folder.ID?) async throws
    func moveWorkout(id: Workout.ID, toFolder: Folder.ID?) async throws
    func moveProgram(id: Program.ID, toFolder: Folder.ID?) async throws
    /// Delete a folder; its sub-folders, workouts, and programs cascade-delete.
    func deleteFolder(id: Folder.ID) async throws
}
```

- [ ] **Step 2: Add folder storage to `MockStore`**

In `Pulse/Core/Data/Mock/MockStore.swift`, add stored properties after `var schedule: [Date: DayPlan]`:

```swift
    /// Library folders (in-memory). Membership of workouts/programs in a folder is
    /// tracked by id-maps rather than on the domain models (which don't carry folder_id).
    var folders: [Folder] = []
    var workoutFolderID: [Workout.ID: Folder.ID] = [:]
    var programFolderID: [Program.ID: Folder.ID] = [:]
```

(These default to empty; the `init` does not need changes — folders start empty on both the seeded and unseeded paths.)

- [ ] **Step 3: Commit** (compilation of the in-memory repo is fixed in Task 4; we commit the protocol + store together with Task 4's implementation. So: do NOT build here — proceed directly to Task 4 and commit at the end of Task 4.)

Stage these two files now but defer the commit to Task 4:
```bash
git add Pulse/Core/Data/Repositories/FolderRepository.swift Pulse/Core/Data/Mock/MockStore.swift
```

---

## Task 4: `InMemoryFolderRepository` (the heart of the mock path)

**Files:**
- Modify: `Pulse/Core/Data/Mock/InMemoryFolderRepository.swift`
- Test: `PulseTests/Core/Data/InMemoryFolderRepositoryTests.swift` (create)

- [ ] **Step 1: Write the failing tests**

Create `PulseTests/Core/Data/InMemoryFolderRepositoryTests.swift`:

```swift
import XCTest
@testable import Pulse

@MainActor
final class InMemoryFolderRepositoryTests: XCTestCase {
    private func makeRepo() -> (InMemoryFolderRepository, MockStore) {
        let store = MockStore(seeded: false)
        return (InMemoryFolderRepository(store: store), store)
    }

    func testCreateFolderAppearsInRootContents() async throws {
        let (repo, _) = makeRepo()
        let f = try await repo.createFolder(name: "Cardio", color: .pink, parentID: nil)
        let root = try await repo.contents(of: nil)
        XCTAssertEqual(root.folders.map(\.id), [f.id])
        XCTAssertEqual(f.name, "Cardio")
        XCTAssertEqual(f.color, .pink)
        XCTAssertNil(f.parentID)
    }

    func testNestedFolderShowsUnderItsParentNotRoot() async throws {
        let (repo, _) = makeRepo()
        let parent = try await repo.createFolder(name: "Strength", color: .blue, parentID: nil)
        let child = try await repo.createFolder(name: "Push", color: .teal, parentID: parent.id)
        let root = try await repo.contents(of: nil)
        XCTAssertEqual(root.folders.map(\.id), [parent.id])     // child not at root
        let inParent = try await repo.contents(of: parent.id)
        XCTAssertEqual(inParent.folders.map(\.id), [child.id])
    }

    func testMoveWorkoutIntoAndOutOfFolder() async throws {
        let store = MockStore(seeded: true)                     // seeded program has workouts
        let repo = InMemoryFolderRepository(store: store)
        let folder = try await repo.createFolder(name: "A", color: .blue, parentID: nil)
        let w = store.allWorkouts.first!
        try await repo.moveWorkout(id: w.id, toFolder: folder.id)
        XCTAssertEqual(try await repo.contents(of: folder.id).workouts.map(\.id), [w.id])
        try await repo.moveWorkout(id: w.id, toFolder: nil)      // back to root
        XCTAssertTrue(try await repo.contents(of: folder.id).workouts.isEmpty)
        XCTAssertTrue(try await repo.contents(of: nil).workouts.contains { $0.id == w.id })
    }

    func testMoveFolderIntoOwnDescendantThrows() async throws {
        let (repo, _) = makeRepo()
        let a = try await repo.createFolder(name: "A", color: .blue, parentID: nil)
        let b = try await repo.createFolder(name: "B", color: .blue, parentID: a.id)
        do {
            try await repo.moveFolder(id: a.id, toParent: b.id)  // a into its own child
            XCTFail("expected cycle rejection")
        } catch { /* expected */ }
        // a stays at root
        XCTAssertEqual(try await repo.contents(of: nil).folders.map(\.id), [a.id])
    }

    func testDeleteFolderCascadesSubtree() async throws {
        let store = MockStore(seeded: true)
        let repo = InMemoryFolderRepository(store: store)
        let parent = try await repo.createFolder(name: "P", color: .blue, parentID: nil)
        let child = try await repo.createFolder(name: "C", color: .blue, parentID: parent.id)
        let w = store.allWorkouts.first!
        try await repo.moveWorkout(id: w.id, toFolder: child.id)
        let programCountBefore = store.programs.count

        try await repo.deleteFolder(id: parent.id)

        // Folder subtree gone.
        XCTAssertTrue(try await repo.contents(of: nil).folders.isEmpty)
        XCTAssertFalse(store.folders.contains { $0.id == child.id })
        // The workout that lived in the subtree was cascade-deleted.
        XCTAssertFalse(store.allWorkouts.contains { $0.id == w.id })
        // Programs not in the subtree are untouched.
        XCTAssertEqual(store.programs.count, programCountBefore)
    }

    func testShouldThrowMakesCreateThrow() async {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store, shouldThrow: true)
        do { _ = try await repo.createFolder(name: "x", color: .blue, parentID: nil); XCTFail() }
        catch { /* expected */ }
    }
}
```

- [ ] **Step 2: Run to confirm failure (compile error — old API)**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/InMemoryFolderRepositoryTests test
```
Expected: FAIL to compile (`InMemoryFolderRepository` still has the old single method).

- [ ] **Step 3: Implement**

Replace the entire contents of `Pulse/Core/Data/Mock/InMemoryFolderRepository.swift`:

```swift
import Foundation

/// In-memory `FolderRepository` over a shared `MockStore`. Mirrors the live
/// repository's semantics: arbitrary-depth tree, cycle-guarded moves, and
/// cascade delete of a folder's sub-folders/workouts/programs. `shouldThrow`
/// drives the builder's save-failure path.
@MainActor
final class InMemoryFolderRepository: FolderRepository {
    let store: MockStore
    var shouldThrow: Bool

    init(store: MockStore = MockStore(seeded: false), shouldThrow: Bool = false) {
        self.store = store
        self.shouldThrow = shouldThrow
    }

    private func gate() throws { if shouldThrow { throw RepositoryError.forced } }

    func contents(of parentID: Folder.ID?) async throws -> FolderContents {
        try gate()
        let folders = store.folders.filter { $0.parentID == parentID }
        let workouts = store.allWorkouts.filter { store.workoutFolderID[$0.id] == parentID }
        let programs = store.programs.filter { store.programFolderID[$0.id] == parentID }
        return FolderContents(folders: folders, workouts: workouts, programs: programs)
    }

    func createFolder(name: String, color: FolderColor, parentID: Folder.ID?) async throws -> Folder {
        try gate()
        let folder = Folder(id: UUID(), name: name, color: color, parentID: parentID)
        store.folders.append(folder)
        return folder
    }

    func renameFolder(id: Folder.ID, name: String, color: FolderColor) async throws {
        try gate()
        guard let i = store.folders.firstIndex(where: { $0.id == id }) else { throw RepositoryError.notFound }
        store.folders[i].name = name
        store.folders[i].color = color
    }

    func moveFolder(id: Folder.ID, toParent newParent: Folder.ID?) async throws {
        try gate()
        guard let i = store.folders.firstIndex(where: { $0.id == id }) else { throw RepositoryError.notFound }
        if let newParent, isDescendant(newParent, of: id) || newParent == id {
            throw RepositoryError.forced   // cycle
        }
        store.folders[i].parentID = newParent
    }

    func moveWorkout(id: Workout.ID, toFolder: Folder.ID?) async throws {
        try gate()
        if let toFolder { store.workoutFolderID[id] = toFolder }
        else { store.workoutFolderID[id] = nil }
    }

    func moveProgram(id: Program.ID, toFolder: Folder.ID?) async throws {
        try gate()
        if let toFolder { store.programFolderID[id] = toFolder }
        else { store.programFolderID[id] = nil }
    }

    func deleteFolder(id: Folder.ID) async throws {
        try gate()
        let subtree = subtreeIDs(of: id)                 // includes `id`
        // Cascade-delete workouts/programs that lived anywhere in the subtree.
        let doomedWorkouts = Set(store.workoutFolderID.filter { subtree.contains($0.value) }.keys)
        let doomedPrograms = Set(store.programFolderID.filter { subtree.contains($0.value) }.keys)
        for pIdx in store.programs.indices {
            store.programs[pIdx].workouts.removeAll { doomedWorkouts.contains($0.id) }
        }
        store.programs.removeAll { doomedPrograms.contains($0.id) }
        store.workoutFolderID = store.workoutFolderID.filter { !subtree.contains($0.value) }
        store.programFolderID = store.programFolderID.filter { !subtree.contains($0.value) }
        store.folders.removeAll { subtree.contains($0.id) }
    }

    // MARK: - Tree helpers

    /// All folder ids in the subtree rooted at `root` (inclusive).
    private func subtreeIDs(of root: Folder.ID) -> Set<Folder.ID> {
        var result: Set<Folder.ID> = [root]
        var frontier = [root]
        while let current = frontier.popLast() {
            for child in store.folders where child.parentID == current {
                if result.insert(child.id).inserted { frontier.append(child.id) }
            }
        }
        return result
    }

    /// Is `candidate` inside the subtree of `ancestor` (walking up parents)?
    private func isDescendant(_ candidate: Folder.ID, of ancestor: Folder.ID) -> Bool {
        var current: Folder.ID? = candidate
        while let id = current {
            if id == ancestor { return true }
            current = store.folders.first { $0.id == id }?.parentID
        }
        return false
    }
}
```

- [ ] **Step 4: Run the tests**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/InMemoryFolderRepositoryTests test
```
Expected: BUILD SUCCEEDED, all `InMemoryFolderRepositoryTests` pass.

> Note: `FolderBuilderModel` may still reference the old `saveFolder`; it is fixed in Task 5. If the build fails ONLY in `FolderBuilderModel`/its test, proceed to Task 5 and run the build there. If you prefer a green build at every task boundary, do Task 5 before building.

- [ ] **Step 5: Commit** (includes Task 3's staged files)
```bash
git add Pulse/Core/Data/Mock/InMemoryFolderRepository.swift PulseTests/Core/Data/InMemoryFolderRepositoryTests.swift Pulse.xcodeproj
git commit -m "feat(data): expand FolderRepository; in-memory tree with cascade + cycle guard [BAK-27]"
```

---

## Task 5: Update `FolderBuilderModel` + its tests to the new API

**Files:**
- Modify: `Pulse/Features/Builders/FolderBuilderModel.swift`
- Modify: `PulseTests/Features/Builders/FolderBuilderModelTests.swift`

- [ ] **Step 1: Update the model**

In `Pulse/Features/Builders/FolderBuilderModel.swift`, add a `parentID` (set by the view to file the new folder into the folder being browsed) and switch `save()` to `createFolder`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class FolderBuilderModel {
    var name: String = "New folder"
    var colorToken: FolderColor = .default
    var parentID: Folder.ID? = nil
    var saveState: SaveState = .idle

    private let folderRepo: any FolderRepository

    init(folders: any FolderRepository, parentID: Folder.ID? = nil) {
        self.folderRepo = folders
        self.parentID = parentID
    }

    func select(color: FolderColor) { colorToken = color }

    func save() async {
        saveState = .saving
        do {
            _ = try await folderRepo.createFolder(name: name, color: colorToken, parentID: parentID)
            saveState = .saved
        } catch {
            saveState = .error("Couldn't create folder.")
        }
    }
}
```

- [ ] **Step 2: Update the tests**

In `PulseTests/Features/Builders/FolderBuilderModelTests.swift`, replace `testSaveCallsRepositoryWithNameAndColor` (which asserted on the removed `repo.saved`) with a version that checks the created folder via the repo's store:

```swift
    func testSaveCreatesFolderWithNameAndColor() async {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store)
        let model = FolderBuilderModel(folders: repo)
        model.name = "Cardio"
        model.select(color: .pink)
        await model.save()
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(store.folders.first?.name, "Cardio")
        XCTAssertEqual(store.folders.first?.color, .pink)
        XCTAssertNil(store.folders.first?.parentID)
    }
```

Leave `testDefaults`, `testSelectColorUpdatesToken`, and `testSaveErrorWhenRepositoryThrows` as they are (the `shouldThrow` init still exists).

- [ ] **Step 3: Build + run the builder tests**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/FolderBuilderModelTests test
```
Expected: BUILD SUCCEEDED, `FolderBuilderModelTests` pass.

- [ ] **Step 4: Commit**
```bash
git add Pulse/Features/Builders/FolderBuilderModel.swift PulseTests/Features/Builders/FolderBuilderModelTests.swift
git commit -m "feat(builder): folder builder creates via createFolder(parentID:) [BAK-27]"
```

---

## Task 6: `SupabaseFolderRepository` + row DTOs

**Files:**
- Create: `Pulse/Core/Data/Supabase/SupabaseFolderRepository.swift`
- Modify: `Pulse/Core/Data/Supabase/Rows/Rows.swift`
- Modify: `Pulse/Core/Data/Supabase/Rows/WriteRows.swift`

No unit test runs against the live DB; correctness here is by build + matching the established repository pattern. (The behavior is already covered semantically by the in-memory tests in Task 4.)

- [ ] **Step 1: Add the read row**

In `Pulse/Core/Data/Supabase/Rows/Rows.swift`, add after `VariationRow`:

```swift
struct FolderRow: Codable {
    let id: UUID
    let parentFolderId: UUID?   // parent_folder_id
    let name: String
    let colorToken: String      // color_token
    func toModel() -> Folder {
        Folder(id: id, name: name,
               color: FolderColor(rawValue: colorToken) ?? .default,
               parentID: parentFolderId)
    }
}
```

- [ ] **Step 2: Add the write rows**

In `Pulse/Core/Data/Supabase/Rows/WriteRows.swift`, add:

```swift
struct FolderWriteRow: Encodable {
    let id: UUID
    let userId: UUID
    let parentFolderId: UUID?
    let name: String
    let colorToken: String

    enum CodingKeys: String, CodingKey { case id, userId, parentFolderId, name, colorToken }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(userId, forKey: .userId)
        try c.encode(parentFolderId, forKey: .parentFolderId)   // null when nil
        try c.encode(name, forKey: .name)
        try c.encode(colorToken, forKey: .colorToken)
    }
}

/// Updates only the `folder_id` of a workout/program row (explicit null on nil).
struct FolderIDUpdate: Encodable {
    let folderId: Folder.ID?
    enum CodingKeys: String, CodingKey { case folderId }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(folderId, forKey: .folderId)   // null when nil
    }
}
```

- [ ] **Step 3: Implement the repository**

Create `Pulse/Core/Data/Supabase/SupabaseFolderRepository.swift`:

```swift
import Foundation
import Supabase

/// Live folder repository. The folder tree is owner-scoped by RLS (`own_folders`).
/// `contents(of:)` reads the direct children of a folder; lightweight selects
/// (no embeds) are used for workouts/programs since the Library only lists names.
struct SupabaseFolderRepository: FolderRepository {
    let client: SupabaseClient

    func contents(of parentID: Folder.ID?) async throws -> FolderContents {
        let folderRows: [FolderRow] = try await childQuery("folders", column: "parent_folder_id", parentID)
            .order("order").execute().value
        let workoutRows: [WorkoutRow] = try await childQuery("workouts", column: "folder_id", parentID)
            .order("order").execute().value
        let programRows: [ProgramRow] = try await childQuery("programs", column: "folder_id", parentID)
            .order("created_at").execute().value
        return FolderContents(
            folders: folderRows.map { $0.toModel() },
            workouts: workoutRows.map { $0.toModel() },
            programs: programRows.map { $0.toModel() })
    }

    /// `select("*")` filtered to children of `parentID` — `is null` at the root.
    private func childQuery(_ table: String, column: String, _ parentID: Folder.ID?)
        -> PostgrestFilterBuilder {
        let base = client.from(table).select("*")
        if let parentID { return base.eq(column, value: parentID.uuidString) }
        return base.is(column, value: nil)
    }

    func createFolder(name: String, color: FolderColor, parentID: Folder.ID?) async throws -> Folder {
        let userID = try await client.auth.session.user.id
        let id = UUID()
        try await client.from("folders").insert(FolderWriteRow(
            id: id, userId: userID, parentFolderId: parentID,
            name: name, colorToken: color.rawValue)).execute()
        return Folder(id: id, name: name, color: color, parentID: parentID)
    }

    func renameFolder(id: Folder.ID, name: String, color: FolderColor) async throws {
        struct Rename: Encodable { let name: String; let colorToken: String }
        try await client.from("folders")
            .update(Rename(name: name, colorToken: color.rawValue))
            .eq("id", value: id.uuidString).execute()
    }

    func moveFolder(id: Folder.ID, toParent newParent: Folder.ID?) async throws {
        if let newParent {
            if newParent == id { throw RepositoryError.forced }
            // Cycle guard: walk the new parent's ancestor chain; reject if `id` is in it.
            let all = try await allFolders()
            let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            var cursor: Folder.ID? = newParent
            while let c = cursor {
                if c == id { throw RepositoryError.forced }
                cursor = byID[c]?.parentID
            }
        }
        struct Reparent: Encodable {
            let parentFolderId: Folder.ID?
            enum CodingKeys: String, CodingKey { case parentFolderId }
            func encode(to e: Encoder) throws {
                var c = e.container(keyedBy: CodingKeys.self)
                try c.encode(parentFolderId, forKey: .parentFolderId)   // null when nil
            }
        }
        try await client.from("folders")
            .update(Reparent(parentFolderId: newParent))
            .eq("id", value: id.uuidString).execute()
    }

    func moveWorkout(id: Workout.ID, toFolder: Folder.ID?) async throws {
        try await client.from("workouts")
            .update(FolderIDUpdate(folderId: toFolder)).eq("id", value: id.uuidString).execute()
    }

    func moveProgram(id: Program.ID, toFolder: Folder.ID?) async throws {
        try await client.from("programs")
            .update(FolderIDUpdate(folderId: toFolder)).eq("id", value: id.uuidString).execute()
    }

    func deleteFolder(id: Folder.ID) async throws {
        // Sub-folders, workouts, and programs cascade via ON DELETE CASCADE.
        try await client.from("folders").delete().eq("id", value: id.uuidString).execute()
    }

    private func allFolders() async throws -> [Folder] {
        let rows: [FolderRow] = try await client.from("folders").select("*").execute().value
        return rows.map { $0.toModel() }
    }
}
```

- [ ] **Step 4: Regenerate + build**
```
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: BUILD SUCCEEDED, all PulseTests pass (no behavior change yet on the mock path).

> If `PostgrestFilterBuilder` is not the correct return type for `client.from(_:).select(_:)` in the installed supabase-swift version, replace the `childQuery` helper's return type with the type the compiler reports, or inline the two branches at each call site. Keep the `is(column, value: nil)` / `eq(column, value:)` logic identical.

- [ ] **Step 5: Commit**
```bash
git add Pulse/Core/Data/Supabase/SupabaseFolderRepository.swift Pulse/Core/Data/Supabase/Rows/Rows.swift Pulse/Core/Data/Supabase/Rows/WriteRows.swift Pulse.xcodeproj
git commit -m "feat(data): SupabaseFolderRepository + folder row DTOs [BAK-27]"
```

---

## Task 7: Wire `folders` in `RepositoryContainer`

**Files:**
- Modify: `Pulse/App/AppEnvironment.swift`

- [ ] **Step 1: Remove the always-mock folder assignment**

In `AppEnvironment.swift`, DELETE these lines near the top of `init` (currently ~35–37):
```swift
        // Folders have no Supabase model yet, so both paths use the in-memory
        // capture repo (see FolderRepository) until the folder data model lands.
        folders = InMemoryFolderRepository()
```

- [ ] **Step 2: Assign `folders` in each branch**

In the `if useMock { … }` branch, right after `let mockStore = MockStore()` (and the other `InMemory*` assignments), add:
```swift
            folders = InMemoryFolderRepository(store: mockStore)
```

In the `else { … }` (live) branch, after `let client = SupabaseClientProvider.make(config)` and alongside the other `Supabase*` assignments, add:
```swift
            folders = SupabaseFolderRepository(client: client)
```

- [ ] **Step 3: Build + full tests**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: BUILD SUCCEEDED, all PulseTests pass. (The mock folder repo now shares `mockStore`, so folders created in the builder are visible to the Library — wired up in later tasks.)

- [ ] **Step 4: Commit**
```bash
git add Pulse/App/AppEnvironment.swift
git commit -m "feat(data): wire folders repo (Supabase live / in-memory mock) [BAK-27]"
```

---

## Task 8: Rewrite `LibraryModel` — real folders + recent workouts

**Files:**
- Modify: `Pulse/Features/Library/LibraryModel.swift`
- Modify: `Pulse/Features/Library/LibraryModels.swift`
- Test: `PulseTests/Features/Library/LibraryModelTests.swift` (create)

`LibraryModel` becomes the Library ROOT. It composes the folder repo (top-level contents), the session repo + workout repo (recent workouts, joined for names), and the exercise/PR repos (catalog, unchanged).

> **Build checkpoint — read first.** Tasks 8–12 are one coupled change: rewriting `LibraryModel` breaks `LibraryView` until the view is rewritten in Task 12, so the project will NOT compile between them. Author each task's code and tests in place, **stage** their files, but do the first green build + test run and a SINGLE combined commit at the END of Task 12. (Tasks 1–7 are independent and each commit green; Task 13 is a green increment after Task 12.) New `LibraryModelTests` are written here in Task 8 but first execute at the Task 12 build.

- [ ] **Step 1: Update `LibraryModels.swift`**

In `Pulse/Features/Library/LibraryModels.swift`:
- DELETE `enum FolderTint { case accent, accent2, neutral }`.
- Replace the `LibraryFolder` struct with one that carries a `FolderColor` and a real `UUID` and no `isProgram`:

```swift
/// A folder row projection for the Library.
struct LibraryFolder: Identifiable, Equatable {
    let id: UUID
    let name: String
    let sub: String
    let color: FolderColor
}
```

Leave `LibraryFilter`, `WorkoutSummary`, `CatalogExercise`, `MuscleGroupCatalog` as they are.

- [ ] **Step 2: Write the failing model tests**

Create `PulseTests/Features/Library/LibraryModelTests.swift`:

```swift
import XCTest
@testable import Pulse

@MainActor
final class LibraryModelTests: XCTestCase {
    private func makeModel(store: MockStore) -> LibraryModel {
        LibraryModel(folders: InMemoryFolderRepository(store: store),
                     sessionRepo: InMemorySessionRepository(store: store),
                     workoutRepo: InMemoryWorkoutRepository(store: store),
                     exerciseRepo: InMemoryExerciseRepository(store: store),
                     prRepo: InMemoryPRRepository(store: store))
    }

    func testLoadSurfacesTopLevelFolders() async {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store)
        _ = try? await repo.createFolder(name: "Cardio", color: .pink, parentID: nil)
        let model = makeModel(store: store)
        await model.load()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.folders.map(\.name), ["Cardio"])
    }

    func testRecentWorkoutsJoinSessionWithWorkoutName() async {
        let store = MockStore(seeded: true)            // has a program with named workouts + sessions
        let model = makeModel(store: store)
        await model.load()
        // Each recent row's name resolves from the workout the session referenced.
        let sessions = try! await InMemorySessionRepository(store: store).fetchSessions(limit: 10)
        XCTAssertEqual(model.recentWorkouts.count, min(sessions.count, 10))
        XCTAssertFalse(model.recentWorkouts.contains { $0.name.isEmpty })
    }

    func testEmptyStoreYieldsEmptyFoldersAndRecents() async {
        let store = MockStore(seeded: false)
        let model = makeModel(store: store)
        await model.load()
        XCTAssertTrue(model.folders.isEmpty)
        XCTAssertTrue(model.recentWorkouts.isEmpty)
    }
}
```

- [ ] **Step 3: Rewrite `LibraryModel`**

Replace `Pulse/Features/Library/LibraryModel.swift`:

```swift
import Foundation
import Observation

enum LibraryLoadState: Equatable { case loading, loaded, error }

@MainActor
@Observable
final class LibraryModel {
    var selectedFilter: LibraryFilter = .all
    private(set) var loadState: LibraryLoadState = .loading
    private(set) var folders: [LibraryFolder] = []
    private(set) var topWorkouts: [Workout] = []
    private(set) var topPrograms: [Program] = []
    private(set) var recentWorkouts: [WorkoutSummary] = []
    private(set) var catalog: [MuscleGroupCatalog] = []
    var isCreateSheetPresented = false

    private let folderRepo: any FolderRepository
    private let sessionRepo: any SessionRepository
    private let workoutRepo: any WorkoutRepository
    private let exerciseRepo: any ExerciseRepository
    private let prRepo: any PRRepository

    init(folders: any FolderRepository,
         sessionRepo: any SessionRepository,
         workoutRepo: any WorkoutRepository,
         exerciseRepo: any ExerciseRepository,
         prRepo: any PRRepository) {
        self.folderRepo = folders
        self.sessionRepo = sessionRepo
        self.workoutRepo = workoutRepo
        self.exerciseRepo = exerciseRepo
        self.prRepo = prRepo
    }

    var isAllEmpty: Bool {
        folders.isEmpty && topWorkouts.isEmpty && topPrograms.isEmpty && recentWorkouts.isEmpty
    }
    var isCatalogEmpty: Bool { catalog.allSatisfy(\.items.isEmpty) }

    func load() async {
        loadState = .loading
        do {
            let contents = try await folderRepo.contents(of: nil)
            let sessions = try await sessionRepo.fetchSessions(limit: 10)
            let workouts = try await workoutRepo.fetchWorkouts()
            let exercises = try await exerciseRepo.fetchCatalog()
            let prIDs = Set(try await prRepo.allPRs().map(\.exerciseID))

            self.folders = contents.folders.map(Self.project)
            self.topWorkouts = contents.workouts
            self.topPrograms = contents.programs
            self.recentWorkouts = Self.recent(sessions, workouts: workouts)
            self.catalog = Self.group(exercises, prIDs: prIDs)
            self.loadState = .loaded
        } catch {
            self.folders = []; self.topWorkouts = []; self.topPrograms = []
            self.recentWorkouts = []; self.catalog = []
            self.loadState = .error
        }
    }

    func retry() async { await load() }
    func select(_ filter: LibraryFilter) { selectedFilter = filter }
    func presentCreate() { isCreateSheetPresented = true }
    func dismissCreate() { isCreateSheetPresented = false }

    // MARK: - Projections

    static func project(_ folder: Folder) -> LibraryFolder {
        LibraryFolder(id: folder.id, name: folder.name, sub: "", color: folder.color)
    }

    /// Join logged sessions to their workout names, newest first.
    static func recent(_ sessions: [WorkoutSession], workouts: [Workout]) -> [WorkoutSummary] {
        let nameByID = Dictionary(workouts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return sessions.map { s in
            WorkoutSummary(id: s.id.uuidString,
                           name: nameByID[s.workoutID] ?? "Workout",
                           sub: "\(s.sets.count) set\(s.sets.count == 1 ? "" : "s")")
        }
    }

    /// Group catalog exercises by muscle, preserving first-appearance order.
    static func group(_ exercises: [Exercise], prIDs: Set<Exercise.ID>) -> [MuscleGroupCatalog] {
        var order: [String] = []
        var byMuscle: [String: [CatalogExercise]] = [:]
        for ex in exercises {
            if !order.contains(ex.muscleGroup) { order.append(ex.muscleGroup) }
            byMuscle[ex.muscleGroup, default: []].append(
                CatalogExercise(id: ex.id.uuidString,
                                name: ex.name,
                                equipment: ex.variations.first?.equipment ?? "",
                                variationCount: ex.variations.count,
                                hasPR: prIDs.contains(ex.id)))
        }
        return order.map { MuscleGroupCatalog(muscle: $0, items: byMuscle[$0] ?? []) }
    }
}
```

- [ ] **Step 4: Stage (no build/commit yet — see the build checkpoint above)**

Do NOT build here (the project won't compile until Task 12). Stage the files; the tests run at the Task 12 build.
```bash
git add Pulse/Features/Library/LibraryModel.swift Pulse/Features/Library/LibraryModels.swift PulseTests/Features/Library/LibraryModelTests.swift Pulse.xcodeproj
```

---

## Task 9: Folder + workout + program rows; `FolderIcon` uses `FolderColor`

**Files:**
- Modify: `Pulse/Features/Library/LibraryComponents.swift`
- Modify: `Pulse/Features/Library/LibraryRowViews.swift`
- Modify: `Pulse/Core/DesignSystem/Theme+Folders.swift` (only if `folderColor(_:)` is not already public to the Library — verify; it already exists in Builders and is module-internal, so it is usable as-is)

- [ ] **Step 1: `FolderIcon` takes a `FolderColor`**

In `Pulse/Features/Library/LibraryComponents.swift`, replace the `FolderIcon` struct:

```swift
/// Tinted folder glyph using the folder's brand color.
struct FolderIcon: View {
    let color: FolderColor
    @Environment(Theme.self) private var theme
    private var tint: Color { theme.folderColor(color) }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(tint.opacity(0.18))
            Image(systemName: "folder.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 38, height: 38)
    }
}
```

- [ ] **Step 2: Update `FolderRow` and add workout/program rows**

In `Pulse/Features/Library/LibraryRowViews.swift`, replace `FolderRow` and add two rows:

```swift
/// One folder row.
struct FolderRow: View {
    let folder: LibraryFolder
    let onTap: () -> Void
    var body: some View {
        LibraryRow(
            onTap: onTap,
            leading: { FolderIcon(color: folder.color) },
            content: { RowNameBlock(name: folder.name, sub: folder.sub) })
        .accessibilityIdentifier("folder.\(folder.id)")
    }
}

/// One workout row inside the Library (a workout that lives in this folder / at root).
struct LibraryWorkoutRow: View {
    let workout: Workout
    let onTap: () -> Void
    var body: some View {
        LibraryRow(
            onTap: onTap,
            content: { RowNameBlock(
                name: workout.name,
                sub: "\(workout.exercises.count) exercise\(workout.exercises.count == 1 ? "" : "s")") })
        .accessibilityIdentifier("workout.\(workout.id)")
    }
}

/// One program row inside the Library.
struct LibraryProgramRow: View {
    let program: Program
    let onTap: () -> Void
    var body: some View {
        LibraryRow(
            onTap: onTap,
            content: { RowNameBlock(name: program.name, sub: "\(program.weeks)-week program") })
        .accessibilityIdentifier("program.\(program.id)")
    }
}
```

Leave `RecentRow` and `CatalogRow` unchanged.

- [ ] **Step 3: Stage (no build/commit yet — coupled to Task 12, see the build checkpoint in Task 8)**
```bash
git add Pulse/Features/Library/LibraryComponents.swift Pulse/Features/Library/LibraryRowViews.swift
```

---

## Task 10: Shared `FolderContentsSection` + `FolderDetailView`

**Files:**
- Create: `Pulse/Features/Library/FolderContentsSection.swift`
- Create: `Pulse/Features/Library/FolderDetailView.swift`

A folder's three child groups render the same way at the root and inside a folder. Extract one section view; the folder-detail screen reuses it.

- [ ] **Step 1: Create the shared section**

Create `Pulse/Features/Library/FolderContentsSection.swift`:

```swift
import SwiftUI

/// Renders a folder's three child groups (folders, workouts, programs) with the
/// per-row Move/Delete actions. Used by both the Library root and folder detail.
struct FolderContentsSection: View {
    let folders: [LibraryFolder]
    let workouts: [Workout]
    let programs: [Program]
    let onOpenFolder: (UUID) -> Void
    let onOpenWorkout: (Workout) -> Void
    let onOpenProgram: (Program) -> Void
    let onMove: (LibraryItemRef) -> Void
    let onDelete: (LibraryFolder) -> Void
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !folders.isEmpty {
                StatLabel("FOLDERS · \(folders.count)")
                ForEach(folders) { folder in
                    FolderRow(folder: folder) { onOpenFolder(folder.id) }
                        .contextMenu {
                            Button("Move to folder…") { onMove(.folder(folder.id)) }
                            Button("Delete", role: .destructive) { onDelete(folder) }
                        }
                }
            }
            if !programs.isEmpty {
                StatLabel("PROGRAMS · \(programs.count)").padding(.top, 8)
                ForEach(programs) { program in
                    LibraryProgramRow(program: program) { onOpenProgram(program) }
                        .contextMenu {
                            Button("Move to folder…") { onMove(.program(program.id)) }
                        }
                }
            }
            if !workouts.isEmpty {
                StatLabel("WORKOUTS · \(workouts.count)").padding(.top, 8)
                ForEach(workouts) { workout in
                    LibraryWorkoutRow(workout: workout) { onOpenWorkout(workout) }
                        .contextMenu {
                            Button("Move to folder…") { onMove(.workout(workout.id)) }
                        }
                }
            }
        }
    }
}

/// Identifies an item the user is moving, for the Move sheet.
enum LibraryItemRef: Equatable {
    case folder(UUID)
    case workout(UUID)
    case program(UUID)
}
```

- [ ] **Step 2: Create the folder detail screen + model**

Create `Pulse/Features/Library/FolderDetailView.swift`:

```swift
import SwiftUI

@MainActor
@Observable
final class FolderDetailModel {
    let folderID: UUID
    let title: String
    private(set) var loadState: LibraryLoadState = .loading
    private(set) var folders: [LibraryFolder] = []
    private(set) var workouts: [Workout] = []
    private(set) var programs: [Program] = []

    private let folderRepo: any FolderRepository

    init(folderID: UUID, title: String, folders: any FolderRepository) {
        self.folderID = folderID
        self.title = title
        self.folderRepo = folders
    }

    func load() async {
        loadState = .loading
        do {
            let c = try await folderRepo.contents(of: folderID)
            folders = c.folders.map(LibraryModel.project)
            workouts = c.workouts
            programs = c.programs
            loadState = .loaded
        } catch {
            folders = []; workouts = []; programs = []
            loadState = .error
        }
    }

    func delete(_ folder: LibraryFolder) async {
        try? await folderRepo.deleteFolder(id: folder.id)
        await load()
    }
}

struct FolderDetailView: View {
    @State private var model: FolderDetailModel
    let onOpenFolder: (UUID, String) -> Void
    let onOpenWorkout: (Workout) -> Void
    let onOpenProgram: (Program) -> Void
    let onMove: (LibraryItemRef) -> Void
    @Environment(Theme.self) private var theme

    init(model: FolderDetailModel,
         onOpenFolder: @escaping (UUID, String) -> Void,
         onOpenWorkout: @escaping (Workout) -> Void,
         onOpenProgram: @escaping (Program) -> Void,
         onMove: @escaping (LibraryItemRef) -> Void) {
        _model = State(initialValue: model)
        self.onOpenFolder = onOpenFolder
        self.onOpenWorkout = onOpenWorkout
        self.onOpenProgram = onOpenProgram
        self.onMove = onMove
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("folderDetail.title")
                Group {
                    switch model.loadState {
                    case .loading:
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    case .error:
                        Text("Couldn't load this folder.")
                            .foregroundStyle(theme.inkSoft).padding(.top, 40)
                    case .loaded:
                        FolderContentsSection(
                            folders: model.folders, workouts: model.workouts, programs: model.programs,
                            onOpenFolder: { id in
                                let name = model.folders.first { $0.id == id }?.name ?? "Folder"
                                onOpenFolder(id, name)
                            },
                            onOpenWorkout: onOpenWorkout, onOpenProgram: onOpenProgram,
                            onMove: onMove,
                            onDelete: { folder in Task { await model.delete(folder) } })
                            .padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .background(theme.bg.ignoresSafeArea())
        .task { await model.load() }
        .accessibilityIdentifier("folderDetail.\(model.folderID)")
    }
}
```

- [ ] **Step 3: Regenerate + build** (project still won't fully compile until Task 11/12 wire `LibraryView`; if only `LibraryView.swift` errors remain, continue)
```
xcodegen generate
```

- [ ] **Step 4: Stage (commit at end of Task 12, once the project builds)**
```bash
git add Pulse/Features/Library/FolderContentsSection.swift Pulse/Features/Library/FolderDetailView.swift Pulse.xcodeproj
```

---

## Task 11: `MoveToFolderSheet` — the move picker

**Files:**
- Create: `Pulse/Features/Library/MoveToFolderSheet.swift`

A flat, indented list of all the user's folders plus a "Library root" option. Excludes the folder being moved and its descendants (can't move a folder into itself/its subtree).

- [ ] **Step 1: Create the sheet + its model**

Create `Pulse/Features/Library/MoveToFolderSheet.swift`:

```swift
import SwiftUI

@MainActor
@Observable
final class MoveToFolderModel {
    let moving: LibraryItemRef
    private(set) var options: [Indented] = []     // selectable destinations
    private let folderRepo: any FolderRepository

    struct Indented: Identifiable, Equatable {
        let id: UUID?        // nil = Library root
        let name: String
        let depth: Int
    }

    init(moving: LibraryItemRef, folders: any FolderRepository) {
        self.moving = moving
        self.folderRepo = folders
    }

    func load() async {
        // 1. Collect every folder by walking the tree from root.
        var all: [Folder] = []
        func gather(parent: UUID?) async {
            let c = try? await folderRepo.contents(of: parent)
            for f in (c?.folders ?? []) {
                all.append(f)
                await gather(parent: f.id)
            }
        }
        await gather(parent: nil)

        // 2. When moving a folder, exclude itself + its descendants (can't nest into own subtree).
        var excluded: Set<UUID> = []
        if case let .folder(movingID) = moving {
            excluded = descendants(of: movingID, in: all).union([movingID])
        }

        // 3. Build the indented option list (root + every allowed folder).
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        func depth(of id: UUID) -> Int {
            var d = 0; var cur = byID[id]?.parentID
            while let c = cur { d += 1; cur = byID[c]?.parentID }
            return d
        }
        var opts: [Indented] = [Indented(id: nil, name: "Library root", depth: 0)]
        for f in all where !excluded.contains(f.id) {
            opts.append(Indented(id: f.id, name: f.name, depth: depth(of: f.id) + 1))
        }
        options = opts
    }

    func confirm(destination: UUID?) async {
        switch moving {
        case .folder(let id):  try? await folderRepo.moveFolder(id: id, toParent: destination)
        case .workout(let id): try? await folderRepo.moveWorkout(id: id, toFolder: destination)
        case .program(let id): try? await folderRepo.moveProgram(id: id, toFolder: destination)
        }
    }

    private func descendants(of root: UUID, in all: [Folder]) -> Set<UUID> {
        var result: Set<UUID> = []
        var frontier = [root]
        while let cur = frontier.popLast() {
            for f in all where f.parentID == cur {
                if result.insert(f.id).inserted { frontier.append(f.id) }
            }
        }
        return result
    }
}

struct MoveToFolderSheet: View {
    @State private var model: MoveToFolderModel
    let onDone: () -> Void
    @Environment(Theme.self) private var theme

    init(model: MoveToFolderModel, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            StatLabel("MOVE TO")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.options) { opt in
                        Button {
                            Task { await model.confirm(destination: opt.id); onDone() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: opt.id == nil ? "tray.full" : "folder")
                                    .foregroundStyle(theme.inkSoft)
                                Text(opt.name).foregroundStyle(theme.ink)
                                Spacer()
                            }
                            .padding(.leading, CGFloat(opt.depth) * 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("move.dest.\(opt.id?.uuidString ?? "root")")
                    }
                }
            }
        }
        .padding(theme.spacing[5])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .task { await model.load() }
    }
}
```

- [ ] **Step 2: Regenerate**
```
xcodegen generate
```

- [ ] **Step 3: Stage (commit at end of Task 12)**
```bash
git add Pulse/Features/Library/MoveToFolderSheet.swift Pulse.xcodeproj
```

---

## Task 12: Rewire `LibraryView` (root contents, nav, create-with-parent, move, delete) + delete the old repo

**Files:**
- Modify: `Pulse/Features/Library/LibraryView.swift`
- Modify: `Pulse/Features/Library/LibraryRoute.swift`
- Delete: `Pulse/Features/Library/LibraryRepository.swift`

- [ ] **Step 1: Add nav routes for folder detail with a title + carry parent on create**

In `Pulse/Features/Library/LibraryRoute.swift`, change `folderDetail` to carry a name and add nothing else:

```swift
    case folderDetail(folderID: UUID, name: String)
```
Update its `marker`:
```swift
        case .folderDetail(let id, _): return "folder:\(id)"
```
(Leave `programDetail`, `exerciseDetail`, builder routes as they are. `programDetail`/`exerciseDetail` already take `String`; keep.)

- [ ] **Step 2: Rewrite `LibraryView`**

Replace `Pulse/Features/Library/LibraryView.swift` with the following. Key changes: build `LibraryModel` from the container's real repos (no `MockLibraryRepository`); render `FolderContentsSection` + recent; push `folderDetail`; present the move sheet and delete confirmation; pass the current parent into the create chooser.

```swift
import SwiftUI

struct LibraryView: View {
    @Environment(Theme.self) private var theme
    @Environment(RepositoryContainer.self) private var repos
    @State private var model: LibraryModel?
    @State private var path: [LibraryRoute] = []
    @State private var moving: LibraryItemRef?
    @State private var pendingDelete: LibraryFolder?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model { screen(model) }
                else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("library.loading")
                }
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationDestination(for: LibraryRoute.self) { route in destination(route) }
        }
        .task {
            guard model == nil else { return }
            let m = LibraryModel(folders: repos.folders, sessionRepo: repos.sessions,
                                 workoutRepo: repos.workouts, exerciseRepo: repos.exercises,
                                 prRepo: repos.prs)
            model = m
            await m.load()
        }
    }

    private func screen(_ model: LibraryModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar(model)
                Text("Library.").font(.system(size: 34, weight: .bold))
                    .foregroundStyle(theme.ink).accessibilityIdentifier("library.h1").padding(.top, 4)
                searchField.padding(.top, 10)
                filterRow(model).padding(.top, 12)
                bodyContent(model).padding(.top, 14)
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .sheet(isPresented: Binding(get: { model.isCreateSheetPresented },
                                    set: { model.isCreateSheetPresented = $0 })) {
            CreateChooserSheet(
                onPick: { route in model.dismissCreate(); path.append(route) },
                onClose: { model.dismissCreate() })
                .presentationDetents([.height(360)]).environment(theme)
        }
        .sheet(item: $moving) { ref in
            MoveToFolderSheet(model: MoveToFolderModel(moving: ref, folders: repos.folders),
                              onDone: { moving = nil; Task { await model.load() } })
                .presentationDetents([.medium, .large]).environment(theme)
        }
        .alert("Delete folder?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let folder = pendingDelete {
                    Task { try? await repos.folders.deleteFolder(id: folder.id); await model.load() }
                }
                pendingDelete = nil
            }
        } message: {
            Text("Deleting “\(pendingDelete?.name ?? "")” also deletes everything inside it. This can’t be undone.")
        }
    }

    private func topBar(_ model: LibraryModel) -> some View {
        HStack {
            StatLabel("LIBRARY")
            Spacer()
            Button { model.presentCreate() } label: {
                Image(systemName: "plus").font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.ink).frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(theme.inkFaint, lineWidth: 1.5))
            }
            .buttonStyle(.plain).accessibilityIdentifier("library.create")
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.inkSoft)
            Text("Search workouts, exercises…").font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.inkSoft)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.inkFaint, lineWidth: 1.5))
        .accessibilityIdentifier("library.search")
    }

    private func filterRow(_ model: LibraryModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LibraryFilter.allCases, id: \.self) { f in
                    FilterChip(label: f.label, isOn: model.selectedFilter == f) { model.select(f) }
                        .accessibilityIdentifier("chip.\(f.rawValue)")
                }
            }
        }
    }

    @ViewBuilder private func bodyContent(_ model: LibraryModel) -> some View {
        switch model.loadState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                .accessibilityIdentifier("library.loading")
        case .error:
            VStack(spacing: 12) {
                Text("Couldn't load your library.").font(.system(size: 15)).foregroundStyle(theme.inkSoft)
                Button("Retry") { Task { await model.retry() } }
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.accent)
                    .accessibilityIdentifier("library.retry")
            }
            .frame(maxWidth: .infinity).padding(.top, 40).accessibilityIdentifier("library.error")
        case .loaded:
            if model.selectedFilter == .exercises { exercisesBody(model) }
            else { defaultBody(model) }
        }
    }

    @ViewBuilder private func defaultBody(_ model: LibraryModel) -> some View {
        if model.isAllEmpty {
            emptyState("Nothing here yet. Tap + to build your first workout.")
                .accessibilityIdentifier("library.empty")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                FolderContentsSection(
                    folders: model.folders, workouts: model.topWorkouts, programs: model.topPrograms,
                    onOpenFolder: { id in
                        let name = model.folders.first { $0.id == id }?.name ?? "Folder"
                        path.append(.folderDetail(folderID: id, name: name))
                    },
                    onOpenWorkout: { _ in /* workout detail route lands with that feature */ },
                    onOpenProgram: { program in path.append(.programDetail(folderID: program.id.uuidString)) },
                    onMove: { moving = $0 },
                    onDelete: { pendingDelete = $0 })

                HStack {
                    StatLabel("RECENT")
                    Spacer()
                    StatLabel("BROWSE EXERCISES →")
                        .contentShape(Rectangle())
                        .onTapGesture { model.select(.exercises) }
                        .accessibilityIdentifier("library.browseExercises")
                }
                .padding(.top, 8)
                ForEach(model.recentWorkouts) { RecentRow(workout: $0) }
            }
        }
    }

    @ViewBuilder private func exercisesBody(_ model: LibraryModel) -> some View {
        if model.isCatalogEmpty {
            emptyState("No exercises in your catalog yet.").accessibilityIdentifier("catalog.empty")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.catalog) { group in
                    StatLabel("\(group.muscle) · \(group.items.count)").padding(.top, 8)
                    ForEach(group.items) { ex in
                        CatalogRow(exercise: ex) { path.append(.exerciseDetail(id: ex.id)) }
                    }
                }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text).font(.system(size: 15)).foregroundStyle(theme.inkSoft)
            .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 40)
    }

    @ViewBuilder private func destination(_ route: LibraryRoute) -> some View {
        switch route {
        case .workoutBuilder:
            WorkoutBuilderView(model: WorkoutBuilderModel(
                catalog: repos.exercises, workouts: repos.workouts))
        case .routineBuilder:
            RoutineBuilderView(model: RoutineBuilderModel(
                routines: repos.programs, workouts: repos.workouts))
        case .folderCreate:
            FolderBuilderView(model: FolderBuilderModel(folders: repos.folders))
        case .folderDetail(let id, let name):
            FolderDetailView(
                model: FolderDetailModel(folderID: id, title: name, folders: repos.folders),
                onOpenFolder: { childID, childName in path.append(.folderDetail(folderID: childID, name: childName)) },
                onOpenWorkout: { _ in },
                onOpenProgram: { program in path.append(.programDetail(folderID: program.id.uuidString)) },
                onMove: { moving = $0 })
        case .exerciseDetail(let id):
            if let uuid = UUID(uuidString: id) {
                ExerciseDetailView(exerciseID: uuid, exerciseRepo: repos.exercises,
                                   sessionRepo: repos.sessions, prRepo: repos.prs)
            } else { routeStub(route) }
        default:
            routeStub(route)
        }
    }

    private func routeStub(_ route: LibraryRoute) -> some View {
        Text(route.marker).font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.ink).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg.ignoresSafeArea()).accessibilityIdentifier("route.\(route.marker)")
    }
}

#Preview {
    LibraryView().environment(Theme()).environment(RepositoryContainer(useMock: true))
}
```

Add `Identifiable` conformance for `LibraryItemRef` so `.sheet(item:)` works — in `FolderContentsSection.swift`, extend the enum:

```swift
extension LibraryItemRef: Identifiable {
    var id: String {
        switch self {
        case .folder(let id):  return "folder-\(id)"
        case .workout(let id): return "workout-\(id)"
        case .program(let id): return "program-\(id)"
        }
    }
}
```

- [ ] **Step 3: Delete the obsolete repository**

```bash
git rm Pulse/Features/Library/LibraryRepository.swift
```
(This removes `LibraryRepository` + `MockLibraryRepository`. Confirm no other references remain: `grep -rn "MockLibraryRepository\|LibraryRepository" Pulse/` should return nothing except the protocol's prior usages, which are now gone.)

- [ ] **Step 4: Regenerate, build, full tests**
```
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: BUILD SUCCEEDED, all PulseTests pass (including `LibraryModelTests`, `InMemoryFolderRepositoryTests`, `FolderBuilderModelTests`, `FolderTests`).

- [ ] **Step 5: Commit everything staged across Tasks 8–12**

This is the first green build of the UI rewrite — confirm Step 4 passed before committing.
```bash
git add Pulse/Features/Library PulseTests/Features/Library Pulse.xcodeproj
git commit -m "feat(library): live folder tree, navigation, move & delete, recent workouts [BAK-27]"
```

---

## Task 13: Pass the current folder into the create flow (file new items into the folder you're viewing)

**Files:**
- Modify: `Pulse/Features/Library/FolderDetailView.swift`
- Modify: `Pulse/Features/Library/LibraryView.swift`

The spec requires that creating a folder/workout while viewing a folder files the new item into that folder. The simplest correct slice for this PR: when the create chooser is opened from a folder-detail screen, pass that folder's id as the new folder's `parentID`.

- [ ] **Step 1: Give folder detail its own create entry**

In `FolderDetailView`, add a `+` toolbar/button that opens the create chooser with the folder's id, and route `.folderCreate` to a `FolderBuilderModel(folders:parentID:)`. Concretely, add to `FolderDetailView`'s `body` a create button in the title row:

```swift
HStack {
    Text(model.title).font(.system(size: 28, weight: .bold)).foregroundStyle(theme.ink)
        .accessibilityIdentifier("folderDetail.title")
    Spacer()
    Button { onCreateHere() } label: {
        Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(theme.ink)
            .frame(width: 34, height: 34).overlay(Circle().strokeBorder(theme.inkFaint, lineWidth: 1.5))
    }
    .buttonStyle(.plain).accessibilityIdentifier("folderDetail.create")
}
```

Add `let onCreateHere: () -> Void` to `FolderDetailView`'s stored properties + initializer.

- [ ] **Step 2: Handle create-here in `LibraryView`**

In `LibraryView`, track the folder to create into and present the chooser; when the pick is `.folderCreate`, construct `FolderBuilderModel(folders: repos.folders, parentID: createParentID)`. Add `@State private var createParentID: UUID?`. In the `destination` for `.folderDetail`, pass `onCreateHere: { createParentID = id; model?.isCreateSheetPresented = true }` (hoist the create chooser to the root sheet, which already exists). Update the root `CreateChooserSheet`'s `.folderCreate` route handling so the `FolderBuilderView` is built with `parentID: createParentID`; reset `createParentID = nil` after the sheet dismisses.

> Because the create chooser currently always routes through the nav `path` and builds `FolderBuilderModel` in `destination(.folderCreate)`, the minimal change is: store `createParentID` and use it in `destination(.folderCreate)` → `FolderBuilderView(model: FolderBuilderModel(folders: repos.folders, parentID: createParentID))`. Reset `createParentID` to `nil` in the root chooser's `onClose`/after workout/routine picks so root creation stays unparented.

- [ ] **Step 3: Regenerate, build, full tests, manual check**
```
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: BUILD SUCCEEDED, all PulseTests pass. Manually: open a folder, tap +, create a sub-folder → it appears inside that folder, not at root.

- [ ] **Step 4: Commit**
```bash
git add Pulse/Features/Library Pulse.xcodeproj
git commit -m "feat(library): create files items into the folder being viewed [BAK-27]"
```

---

## Task 14: Final verification

- [ ] **Step 1: Full unit gate**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: TEST SUCCEEDED — all PulseTests pass, including the new `FolderTests`, `InMemoryFolderRepositoryTests`, and `LibraryModelTests`.

- [ ] **Step 2: Confirm the mock is gone**
```
grep -rn "MockLibraryRepository\|protocol LibraryRepository\|FolderTint\|isProgram" Pulse/
```
Expected: no matches (all removed).

- [ ] **Step 3: Manual acceptance pass (running app, mock path)**
- Create a folder at root and inside another folder; nest several levels and navigate in/out.
- Move a workout, a program, and a folder into another folder and back to root via "Move to folder…".
- Attempt to move a folder into its own descendant — it is not offered as a destination.
- Delete a non-empty folder; confirm the warning, then confirm its contents are gone.
- Confirm Recent Workouts shows real logged sessions with their workout names.

- [ ] **Step 4: Flag the live migration**
Remind the human that `supabase/migrations/0007_folders.sql` must be applied via the Supabase dashboard before the live (non-`-uiMock`) path will work.
