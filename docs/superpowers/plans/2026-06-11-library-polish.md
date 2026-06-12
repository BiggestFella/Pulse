# Library Polish (#39 Follow-ups) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the new Library folder feature — relative-date Recent sublines, a delete confirmation that shows the item count and skips the dialog for empty folders, an edit-folder flow (rename + recolor), and a reload-on-return fix so created/edited folders appear immediately.

**Architecture:** SwiftUI + `@Observable` MVVM. Delete and edit decisions live in the models (`LibraryModel`, `FolderDetailModel`, `FolderBuilderModel`) so they're unit-testable; views bind to model state. Reuses the existing `renameFolder` repo method and `FolderBuilderView`.

**Tech Stack:** SwiftUI (iOS 17+), Swift Concurrency, XCTest. Project generated via XcodeGen — **run `xcodegen generate` after adding any new file (especially under `PulseTests/`)**.

**Source spec:** `docs/superpowers/specs/2026-06-11-library-polish-design.md`.

**Branch:** continues `feature/bak-27-library-folders` (PR #39).

**Test command (unit gate):**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseTests test
```
`-only-testing:PulseTests` is mandatory (PulseUITests runner defect). If `iPhone 17` is unavailable, use the closest available iPhone (`xcrun simctl list devices available`).

**Guardrails for every task:** the working tree has an unrelated uncommitted change to `Pulse/App/AppShell.swift` and an untracked `.claude/` directory — NEVER stage them (no `git add -A`/`.`, no stashing). `Pulse.xcodeproj` is gitignored — do NOT force-add it. Stage only the files each task names.

---

## File Structure

- Modify `Pulse/Features/Library/LibraryModel.swift` — `relativeDay` helper; `recent(…, now:)`; `requestDelete`/`confirmDelete`/`cancelDelete`/`pendingDelete`.
- Modify `Pulse/Features/Library/LibraryModels.swift` — add `PendingFolderDelete`.
- Modify `Pulse/Features/Library/FolderDetailView.swift` — model gains the same delete flow; view binds to it.
- Modify `Pulse/Features/Library/LibraryView.swift` — delete alert binds to model; edit route; reload-on-return.
- Modify `Pulse/Features/Library/FolderContentsSection.swift` — add an "Edit" context action (`onEdit`).
- Modify `Pulse/Features/Library/LibraryRoute.swift` — add `.folderEdit`.
- Modify `Pulse/Features/Builders/FolderBuilderModel.swift` — edit mode.
- Modify `Pulse/Features/Builders/FolderBuilderView.swift` — edit labels.
- Modify `PulseTests/Features/Library/LibraryModelTests.swift` — relative-date + delete tests.
- Modify `PulseTests/Features/Builders/FolderBuilderModelTests.swift` — edit-mode test.

---

## Task 1: Recent Workouts — relative-date subline

**Files:**
- Modify: `Pulse/Features/Library/LibraryModel.swift`
- Test: `PulseTests/Features/Library/LibraryModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `LibraryModelTests`:

```swift
func testRelativeDayBoundaries() {
    let cal = SampleData.calendar
    let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12))!
    func day(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: now)! }
    XCTAssertEqual(LibraryModel.relativeDay(day(0), now: now), "Today")
    XCTAssertEqual(LibraryModel.relativeDay(day(1), now: now), "Yesterday")
    XCTAssertEqual(LibraryModel.relativeDay(day(3), now: now), "3 days ago")
    // 7+ days falls back to a "d MMM" date string — just assert it's not a relative phrase.
    let old = LibraryModel.relativeDay(day(40), now: now)
    XCTAssertFalse(old.isEmpty)
    XCTAssertFalse(old.hasSuffix("ago"))
}

func testRecentSublineHasSetCountAndRelativeDay() {
    let cal = SampleData.calendar
    let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 11, hour: 12))!
    let wid = UUID()
    let workout = Workout(id: wid, name: "Leg day", weekday: nil, order: 0, exercises: [])
    let session = WorkoutSession(
        id: UUID(), workoutID: wid,
        startedAt: cal.date(byAdding: .day, value: -1, to: now)!, endedAt: nil,
        sets: [SessionSet(exerciseID: UUID(), order: 0, reps: 5, weight: 100, type: .working)])
    let rows = LibraryModel.recent([session], workouts: [workout], now: now)
    XCTAssertEqual(rows.first?.name, "Leg day")
    XCTAssertEqual(rows.first?.sub, "1 set · Yesterday")
}
```

- [ ] **Step 2: Run to verify failure**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/LibraryModelTests test
```
Expected: FAIL to compile (`relativeDay` missing; `recent` has no `now:`).

- [ ] **Step 3: Implement**

In `LibraryModel.swift`, replace the `recent(_:workouts:)` function with:

```swift
/// Join logged sessions to their workout names, newest first.
static func recent(_ sessions: [WorkoutSession], workouts: [Workout], now: Date = Date()) -> [WorkoutSummary] {
    let nameByID = Dictionary(workouts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    return sessions.map { s in
        let setCount = s.sets.count
        return WorkoutSummary(
            id: s.id.uuidString,
            name: nameByID[s.workoutID] ?? "Workout",
            sub: "\(setCount) set\(setCount == 1 ? "" : "s") · \(relativeDay(s.startedAt, now: now))")
    }
}

/// Relative day label: Today / Yesterday / "N days ago" (2–6) / "d MMM" (7+).
static func relativeDay(_ date: Date, now: Date) -> String {
    let cal = SampleData.calendar
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                  to: cal.startOfDay(for: now)).day ?? 0
    switch days {
    case ..<1:   return "Today"
    case 1:      return "Yesterday"
    case 2...6:  return "\(days) days ago"
    default:
        let f = DateFormatter()
        f.calendar = cal
        f.dateFormat = "d MMM"
        return f.string(from: date)
    }
}
```

(The `load()` call site `Self.recent(sessions, workouts: workouts)` is unchanged — `now` defaults to `Date()`.)

- [ ] **Step 4: Run to verify pass**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/LibraryModelTests test
```
Expected: PASS (all `LibraryModelTests`, including the existing ones).

- [ ] **Step 5: Commit**
```bash
git add Pulse/Features/Library/LibraryModel.swift PulseTests/Features/Library/LibraryModelTests.swift
git commit -m "feat(library): relative-date subline on recent workouts [BAK-27]"
```

---

## Task 2: Delete confirmation — item count + non-empty-only (models + views)

**Files:**
- Modify: `Pulse/Features/Library/LibraryModels.swift`
- Modify: `Pulse/Features/Library/LibraryModel.swift`
- Modify: `Pulse/Features/Library/FolderDetailView.swift`
- Modify: `Pulse/Features/Library/LibraryView.swift`
- Test: `PulseTests/Features/Library/LibraryModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `LibraryModelTests`:

```swift
func testRequestDeleteEmptyFolderDeletesImmediately() async {
    let store = MockStore(seeded: false)
    let repo = InMemoryFolderRepository(store: store)
    let folder = try! await repo.createFolder(name: "Empty", color: .blue, parentID: nil)
    let model = makeModel(store: store)
    await model.load()
    await model.requestDelete(LibraryModel.project(folder))
    XCTAssertNil(model.pendingDelete)                 // no dialog for empty
    XCTAssertFalse(store.folders.contains { $0.id == folder.id })  // gone
}

func testRequestDeleteNonEmptyFolderPromptsWithCount() async {
    let store = MockStore(seeded: false)
    let repo = InMemoryFolderRepository(store: store)
    let parent = try! await repo.createFolder(name: "Parent", color: .blue, parentID: nil)
    _ = try! await repo.createFolder(name: "Child", color: .teal, parentID: parent.id)
    let model = makeModel(store: store)
    await model.load()
    await model.requestDelete(LibraryModel.project(parent))
    XCTAssertEqual(model.pendingDelete?.itemCount, 1)              // one direct child
    XCTAssertTrue(store.folders.contains { $0.id == parent.id })  // not deleted yet
    await model.confirmDelete()
    XCTAssertNil(model.pendingDelete)
    XCTAssertFalse(store.folders.contains { $0.id == parent.id }) // now gone
}
```

- [ ] **Step 2: Run to verify failure**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/LibraryModelTests test
```
Expected: FAIL to compile (`pendingDelete`/`requestDelete`/`confirmDelete` missing).

- [ ] **Step 3: Add the shared value type**

In `Pulse/Features/Library/LibraryModels.swift`, add:

```swift
/// A folder pending deletion confirmation, with the count of items directly inside it.
struct PendingFolderDelete: Equatable {
    let folder: LibraryFolder
    let itemCount: Int
}
```

- [ ] **Step 4: Add the delete flow to `LibraryModel`**

In `LibraryModel.swift`, add a property next to the other `private(set) var`s:
```swift
    private(set) var pendingDelete: PendingFolderDelete?
```
And add these methods (after `dismissCreate()`):
```swift
    /// Empty folder → delete immediately; non-empty → stage a confirmation with the
    /// count of items directly inside.
    func requestDelete(_ folder: LibraryFolder) async {
        let count = (try? await folderRepo.contents(of: folder.id)).map {
            $0.folders.count + $0.workouts.count + $0.programs.count
        } ?? 0
        if count == 0 {
            try? await folderRepo.deleteFolder(id: folder.id)
            await load()
        } else {
            pendingDelete = PendingFolderDelete(folder: folder, itemCount: count)
        }
    }

    func confirmDelete() async {
        guard let pending = pendingDelete else { return }
        pendingDelete = nil
        try? await folderRepo.deleteFolder(id: pending.folder.id)
        await load()
    }

    func cancelDelete() { pendingDelete = nil }
```

- [ ] **Step 5: Mirror the flow in `FolderDetailModel`**

In `FolderDetailView.swift`, in `FolderDetailModel`, add `private(set) var pendingDelete: PendingFolderDelete?` next to the other state, and REPLACE the existing `delete(_:)` method with:
```swift
    func requestDelete(_ folder: LibraryFolder) async {
        let count = (try? await folderRepo.contents(of: folder.id)).map {
            $0.folders.count + $0.workouts.count + $0.programs.count
        } ?? 0
        if count == 0 {
            try? await folderRepo.deleteFolder(id: folder.id)
            await load()
        } else {
            pendingDelete = PendingFolderDelete(folder: folder, itemCount: count)
        }
    }

    func confirmDelete() async {
        guard let pending = pendingDelete else { return }
        pendingDelete = nil
        try? await folderRepo.deleteFolder(id: pending.folder.id)
        await load()
    }

    func cancelDelete() { pendingDelete = nil }
```

- [ ] **Step 6: Bind the `FolderDetailView` alert to the model**

In `FolderDetailView.swift`:
- DELETE the `@State private var pendingDelete: LibraryFolder?` line.
- Change the `FolderContentsSection`'s `onDelete:` from `{ folder in pendingDelete = folder }` to `{ folder in Task { await model.requestDelete(folder) } }`.
- Replace the `.alert(...)` modifier with one bound to the model:
```swift
        .alert("Delete folder?", isPresented: Binding(
            get: { model.pendingDelete != nil }, set: { if !$0 { model.cancelDelete() } })) {
            Button("Cancel", role: .cancel) { model.cancelDelete() }
            Button("Delete", role: .destructive) { Task { await model.confirmDelete() } }
        } message: {
            Text(deleteMessage(model.pendingDelete))
        }
```
- Add this free helper at file scope (below the `FolderDetailView` struct), shared with `LibraryView`:
```swift
/// Confirmation copy for deleting a non-empty folder.
func deleteMessage(_ pending: PendingFolderDelete?) -> String {
    guard let pending else { return "" }
    let n = pending.itemCount
    return "Delete \"\(pending.folder.name)\" and the \(n) item\(n == 1 ? "" : "s") inside it? This can't be undone."
}
```

- [ ] **Step 7: Bind the `LibraryView` alert to the model**

In `LibraryView.swift`:
- DELETE the `@State private var pendingDelete: LibraryFolder?` line.
- In `defaultBody`, change `onDelete: { pendingDelete = $0 }` to `onDelete: { folder in Task { await model.requestDelete(folder) } }`.
- Replace the `.alert(...)` modifier in `screen(_:)` with:
```swift
        .alert("Delete folder?", isPresented: Binding(
            get: { model.pendingDelete != nil }, set: { if !$0 { model.cancelDelete() } })) {
            Button("Cancel", role: .cancel) { model.cancelDelete() }
            Button("Delete", role: .destructive) { Task { await model.confirmDelete() } }
        } message: {
            Text(deleteMessage(model.pendingDelete))
        }
```

- [ ] **Step 8: Run the full gate**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: BUILD SUCCEEDED, all PulseTests pass (including the two new delete tests).

- [ ] **Step 9: Commit**
```bash
git add Pulse/Features/Library/LibraryModels.swift Pulse/Features/Library/LibraryModel.swift Pulse/Features/Library/FolderDetailView.swift Pulse/Features/Library/LibraryView.swift PulseTests/Features/Library/LibraryModelTests.swift
git commit -m "feat(library): delete confirmation shows item count; skip dialog for empty folders [BAK-27]"
```

---

## Task 3: Edit-folder — `FolderBuilderModel` edit mode

**Files:**
- Modify: `Pulse/Features/Builders/FolderBuilderModel.swift`
- Test: `PulseTests/Features/Builders/FolderBuilderModelTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `FolderBuilderModelTests`:

```swift
func testEditModeSavesViaRenameNotCreate() async {
    let store = MockStore(seeded: false)
    let repo = InMemoryFolderRepository(store: store)
    let folder = try! await repo.createFolder(name: "Old", color: .blue, parentID: nil)
    let model = FolderBuilderModel(folders: repo, editing: folder)
    XCTAssertEqual(model.name, "Old")
    XCTAssertEqual(model.colorToken, .blue)
    model.name = "New"
    model.select(color: .pink)
    await model.save()
    XCTAssertEqual(model.saveState, .saved)
    XCTAssertEqual(store.folders.count, 1)                    // renamed, not created
    XCTAssertEqual(store.folders.first?.name, "New")
    XCTAssertEqual(store.folders.first?.color, .pink)
}
```

- [ ] **Step 2: Run to verify failure**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/FolderBuilderModelTests test
```
Expected: FAIL to compile (`init(folders:editing:)` missing).

- [ ] **Step 3: Implement edit mode**

Replace `Pulse/Features/Builders/FolderBuilderModel.swift` with:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class FolderBuilderModel {
    var name: String = "New folder"
    var colorToken: FolderColor = .default
    var parentID: Folder.ID? = nil
    private(set) var editingFolderID: Folder.ID? = nil
    var saveState: SaveState = .idle

    private let folderRepo: any FolderRepository

    /// Create mode — a new folder parented at `parentID`.
    init(folders: any FolderRepository, parentID: Folder.ID? = nil) {
        self.folderRepo = folders
        self.parentID = parentID
    }

    /// Edit mode — seeded from an existing folder; `save()` renames it.
    init(folders: any FolderRepository, editing folder: Folder) {
        self.folderRepo = folders
        self.name = folder.name
        self.colorToken = folder.color
        self.editingFolderID = folder.id
    }

    var isEditing: Bool { editingFolderID != nil }

    func select(color: FolderColor) { colorToken = color }

    func save() async {
        saveState = .saving
        do {
            if let editingFolderID {
                try await folderRepo.renameFolder(id: editingFolderID, name: name, color: colorToken)
            } else {
                _ = try await folderRepo.createFolder(name: name, color: colorToken, parentID: parentID)
            }
            saveState = .saved
        } catch {
            saveState = .error(isEditing ? "Couldn't save changes." : "Couldn't create folder.")
        }
    }
}
```

- [ ] **Step 4: Run to verify pass**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/FolderBuilderModelTests test
```
Expected: PASS (the new test + the existing create-mode tests).

- [ ] **Step 5: Commit**
```bash
git add Pulse/Features/Builders/FolderBuilderModel.swift PulseTests/Features/Builders/FolderBuilderModelTests.swift
git commit -m "feat(builder): folder builder edit mode (rename via renameFolder) [BAK-27]"
```

---

## Task 4: Edit-folder — view labels, route, context action, wiring

**Files:**
- Modify: `Pulse/Features/Builders/FolderBuilderView.swift`
- Modify: `Pulse/Features/Library/LibraryRoute.swift`
- Modify: `Pulse/Features/Library/FolderContentsSection.swift`
- Modify: `Pulse/Features/Library/LibraryView.swift`
- Modify: `Pulse/Features/Library/FolderDetailView.swift`

View wiring (verified by build). Steps:

- [ ] **Step 1: Edit-aware labels in `FolderBuilderView`**

In `FolderBuilderView.swift`, change the `BuilderScaffold` call's `eyebrow`/`primaryLabel` to depend on the model:
```swift
        BuilderScaffold(
            eyebrow: model.isEditing ? "EDIT FOLDER" : "NEW FOLDER",
            primaryLabel: model.isEditing ? "Save changes →" : "Create folder →",
            saving: model.saveState == .saving,
            onCancel: { dismiss() },
            onPrimary: { Task { await model.save() } }
        ) {
```
(Leave the rest of the view unchanged.)

- [ ] **Step 2: Add the edit route**

In `Pulse/Features/Library/LibraryRoute.swift`, add a case and its marker:
```swift
    case folderEdit(folderID: UUID, name: String, colorToken: String)
```
In `marker`:
```swift
        case .folderEdit(let id, _, _): return "folderEdit:\(id)"
```

- [ ] **Step 3: Add an "Edit" action to the folder context menu**

In `Pulse/Features/Library/FolderContentsSection.swift`:
- Add a closure property `let onEdit: (LibraryFolder) -> Void` (place it after `onMove`).
- In the folders `ForEach` context menu, add an Edit button before Move:
```swift
                        .contextMenu {
                            Button("Edit") { onEdit(folder) }
                            Button("Move to folder…") { onMove(.folder(folder.id)) }
                            Button("Delete", role: .destructive) { onDelete(folder) }
                        }
```

- [ ] **Step 4: Provide `onEdit` from both callers + render the edit route**

In `LibraryView.swift`:
- In `defaultBody`'s `FolderContentsSection(...)`, add:
```swift
                    onEdit: { folder in path.append(.folderEdit(folderID: folder.id, name: folder.name, colorToken: folder.color.rawValue)) },
```
  (place it alongside `onMove`/`onDelete`).
- In `destination(_:)`, add a case:
```swift
        case .folderEdit(let id, let name, let colorToken):
            FolderBuilderView(model: FolderBuilderModel(
                folders: repos.folders,
                editing: Folder(id: id, name: name,
                                color: FolderColor(rawValue: colorToken) ?? .default, parentID: nil)))
```

In `FolderDetailView.swift`:
- Add a stored property `let onEdit: (LibraryFolder) -> Void` and matching `init` parameter (store `self.onEdit = onEdit`).
- Pass `onEdit: onEdit` into the `FolderContentsSection(...)` call (alongside `onMove`).
- In `LibraryView.destination(.folderDetail)`, pass `onEdit: { folder in path.append(.folderEdit(folderID: folder.id, name: folder.name, colorToken: folder.color.rawValue)) }` to `FolderDetailView(...)`.

- [ ] **Step 5: Build + full gate**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: BUILD SUCCEEDED, all PulseTests pass.

- [ ] **Step 6: Commit**
```bash
git add Pulse/Features/Builders/FolderBuilderView.swift Pulse/Features/Library/LibraryRoute.swift Pulse/Features/Library/FolderContentsSection.swift Pulse/Features/Library/LibraryView.swift Pulse/Features/Library/FolderDetailView.swift
git commit -m "feat(library): edit-folder flow (rename + recolor) via builder edit mode [BAK-27]"
```

---

## Task 5: Reload-on-return after create/edit

**Files:**
- Modify: `Pulse/Features/Library/LibraryView.swift`

Creating or editing a folder pushes the builder, which pops on save. The Library root's `.task` runs once, so the new/edited folder isn't shown until a reload. Reload when the nav stack pops.

- [ ] **Step 1: Reload the originating list on pop**

In `LibraryView.swift`, add an `.onChange(of: path)` modifier to the `NavigationStack` (e.g. right after `.navigationDestination(...)` inside the `NavigationStack`'s content group, alongside `.background`):
```swift
            .onChange(of: path) { old, new in
                // A pop (returning from a builder or a folder) — refresh the now-visible list.
                if new.count < old.count {
                    refreshID += 1
                    Task { await model?.load() }
                }
            }
```

- [ ] **Step 2: Build + full gate**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: BUILD SUCCEEDED, all PulseTests pass.

- [ ] **Step 3: Manual check (running app, mock path)**
Create a folder from the Library root → it appears on return. Open a folder, tap +, create a sub-folder → it appears in that folder on return. Edit a folder's name/color → the change shows on return.

- [ ] **Step 4: Commit**
```bash
git add Pulse/Features/Library/LibraryView.swift
git commit -m "fix(library): reload list on return from create/edit [BAK-27]"
```

---

## Task 6: Final verification

- [ ] **Step 1: Full unit gate**
```
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests test
```
Expected: TEST SUCCEEDED — all PulseTests pass, including the new relative-date, delete-confirmation, and edit-mode tests.

- [ ] **Step 2: Manual acceptance (running app, mock path)**
- Recent rows show "N sets · <relative date>" (Today / Yesterday / N days ago / date).
- Deleting an empty folder happens with no dialog; deleting a non-empty folder shows "…and the N item(s) inside it?" and removes it on confirm.
- Editing a folder (context menu → Edit) opens the builder pre-filled; saving renames/recolors it and the change shows on return.
- Newly created folders (root and inside a folder) appear immediately on return.
