# Guided Create Wizard + Workout Editor — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-screen workout builder with a guided multi-step **create wizard** (Name → Targets → Schedule → Folder → Create) that lands in a **workout editor** (the restructured builder, hydrated by id) which is also reused for **editing** a saved workout.

**Architecture:** A new `CreateWizardModel`/`CreateWizardView` collects the draft, persists it (`saveWorkout` + folder placement), and routes to the editor by id. `WorkoutBuilderModel` is restructured from build-from-scratch to **hydrate-from-`Workout.ID`** + **save-in-place**. Routing: `CreateChooserSheet`'s "Workout" launches the wizard; the wizard hands off to a new `.workoutEditor(id:)` route; `WorkoutDetailView` gains an **Edit** entry to the same editor. A foundation fix (BAK-60) makes `saveWorkout` preserve `folder_id` + specific-date `plan_entries` across an in-place save.

**Tech Stack:** SwiftUI, iOS 17+, `@Observable` MVVM, Swift Concurrency, Supabase (PostgREST), XcodeGen, XCTest + XCUITest.

**Linear:** [BAK-59](https://linear.app/bakinglions/issue/BAK-59) (subsumes [BAK-54](https://linear.app/bakinglions/issue/BAK-54) folder-on-create + [BAK-56](https://linear.app/bakinglions/issue/BAK-56) edit) · foundation fix [BAK-60](https://linear.app/bakinglions/issue/BAK-60) · builds on [BAK-57](https://linear.app/bakinglions/issue/BAK-57).

**Spec:** `docs/superpowers/specs/2026-06-14-create-wizard-design.md`

---

## File structure

**Create:**
- `Pulse/Features/Builders/CreateWizard/CreateWizardModel.swift` — wizard draft state, step navigation, `create()`.
- `Pulse/Features/Builders/CreateWizard/CreateWizardView.swift` — stepped container (progress bar, Back/Continue) + the four step subviews.
- `Pulse/Features/Library/FolderOptions.swift` — shared indented folder-destination loader (reused by the wizard's Folder step + `MoveToFolderModel`).
- `PulseTests/Features/Builders/CreateWizard/CreateWizardModelTests.swift`
- `PulseTests/Features/Library/FolderOptionsTests.swift`
- `PulseTests/Features/Builders/CreateWizardAcceptanceTests.swift`
- `PulseUITests/CreateWizardUITests.swift`

**Modify:**
- `Pulse/Core/Data/Supabase/SupabaseWorkoutRepository.swift` — `saveWorkout` upsert-row + replace-children (BAK-60).
- `Pulse/Core/Data/Supabase/Rows/WriteRows.swift` — add `WorkoutGraphWriter.insertChildren(of:)`; DRY `insert`.
- `Pulse/Features/Library/MoveToFolderSheet.swift` — adopt `FolderOption`.
- `Pulse/Features/Builders/WorkoutBuilderModel.swift` — hydrate-from-id + save-in-place.
- `Pulse/Features/Builders/WorkoutBuilderView.swift` — load state + eyebrow + previews.
- `Pulse/Features/Builders/SetEditorSheet.swift` — preview uses new init.
- `Pulse/Features/Library/LibraryRoute.swift` — `+.createWizard`, `+.workoutEditor(id:)`, `−.workoutBuilder`.
- `Pulse/Features/Library/CreateChooserSheet.swift` — Workout → `.createWizard`.
- `Pulse/Features/Library/LibraryView.swift` — wizard + editor destinations; remove `.workoutBuilder`/`BuilderSampleData`; thread `onEdit`.
- `Pulse/Features/Library/WorkoutDetailView.swift` — Edit toolbar entry.
- `Pulse/Features/Library/WorkoutDetailModel.swift` — expose `workoutID`.
- `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift`, `PulseTests/Features/Builders/TargetsPickerAcceptanceTests.swift` — new init.
- `project.yml` is glob-based; run `xcodegen generate` after adding files.

---

## Task 1: Foundation — `saveWorkout` preserves folder + schedule (BAK-60)

**Why first:** the editor calls `saveWorkout` in place repeatedly. Today `SupabaseWorkoutRepository.saveWorkout` **deletes the `workouts` row and reinserts** it; `WorkoutWriteRow` carries no `folder_id`, and `plan_entries.workout_id` is `on delete set null` — so every save un-folders the workout and nulls its specific-date schedule. (Mock is unaffected: it tracks folder membership in a separate `MockStore.workoutFolderID` map and replaces the `Workout` in place. So this is a real-path-only bug, **not** unit-catchable — it is verified by reasoning + on-device, like SP2's real-path Start.)

**Files:**
- Modify: `Pulse/Core/Data/Supabase/Rows/WriteRows.swift` (`WorkoutGraphWriter`)
- Modify: `Pulse/Core/Data/Supabase/SupabaseWorkoutRepository.swift:38-44`
- Test: `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift` (mock contract guard — added in Task 6) + manual device check.

- [ ] **Step 1: Add `insertChildren(of:)` to `WorkoutGraphWriter` and DRY `insert`**

In `WriteRows.swift`, replace the body of `WorkoutGraphWriter` (lines 102-136) with:

```swift
struct WorkoutGraphWriter {
    let client: SupabaseClient

    func insert(_ workouts: [Workout], programID: Program.ID) async throws {
        guard !workouts.isEmpty else { return }
        let workoutRows = workouts.map {
            WorkoutWriteRow(id: $0.id, programId: programID, name: $0.name,
                            weekdays: $0.weekdays, order: $0.order,
                            targets: $0.targets.map(\.rawValue))
        }
        try await client.from("workouts").insert(workoutRows).execute()
        for workout in workouts { try await insertChildren(of: workout) }
    }

    /// Inserts just the exercise/set children for one already-persisted workout row
    /// (FK order: workout_exercises → set_specs). Used by `saveWorkout`, which
    /// upserts the parent row itself and replaces only the children.
    func insertChildren(of workout: Workout) async throws {
        var exerciseRows: [WorkoutExerciseWriteRow] = []
        var setRows: [SetSpecWriteRow] = []
        for (exIndex, we) in workout.exercises.enumerated() {
            exerciseRows.append(WorkoutExerciseWriteRow(
                id: we.id, workoutId: workout.id, exerciseId: we.exercise.id,
                variationId: we.variationID, supersetGroup: we.supersetGroup, order: exIndex))
            for (setIndex, spec) in we.sets.enumerated() {
                setRows.append(SetSpecWriteRow(
                    id: spec.id, workoutExerciseId: we.id, reps: spec.reps,
                    rir: spec.rir, type: spec.type.rawValue, order: setIndex))
            }
        }
        if !exerciseRows.isEmpty {
            try await client.from("workout_exercises").insert(exerciseRows).execute()
        }
        if !setRows.isEmpty {
            try await client.from("set_specs").insert(setRows).execute()
        }
    }
}
```

- [ ] **Step 2: Rewrite `saveWorkout` to upsert the row + replace only children**

In `SupabaseWorkoutRepository.swift`, replace `saveWorkout` (lines 38-44):

```swift
func saveWorkout(_ workout: Workout) async throws -> Workout {
    guard let programID = try await targetProgramID() else { throw RepositoryError.notFound }
    // Upsert the workout's OWN row in place. A delete+reinsert (the previous
    // approach) reset folder_id (not carried by WorkoutWriteRow) and tripped
    // plan_entries.workout_id's `on delete set null`, silently un-foldering the
    // workout and wiping its specific-date schedule (BAK-60). Upsert touches only
    // name/weekdays/order/targets; folder_id + plan_entries are left intact.
    let row = WorkoutWriteRow(
        id: workout.id, programId: programID, name: workout.name,
        weekdays: workout.weekdays, order: workout.order,
        targets: workout.targets.map(\.rawValue))
    try await client.from("workouts").upsert(row).execute()
    // Replace only the children: delete this workout's exercises (cascades
    // set_specs) then re-insert the exercise/set graph.
    try await client.from("workout_exercises")
        .delete().eq("workout_id", value: workout.id.uuidString).execute()
    try await WorkoutGraphWriter(client: client).insertChildren(of: workout)
    return try await fetchWorkout(id: workout.id) ?? workout
}
```

> **Verify during build:** confirm the installed Supabase Swift SDK exposes `from(_:).upsert(_:)` (PostgREST upsert, conflicts on PK by default). If the method name/signature differs in this SDK version, use that SDK's upsert form (the semantics required: insert-or-update the `workouts` row by `id`, never delete it).

- [ ] **Step 3: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Pulse/Core/Data/Supabase/Rows/WriteRows.swift Pulse/Core/Data/Supabase/SupabaseWorkoutRepository.swift
git commit -m "fix(workouts): saveWorkout upserts row + replaces children, preserving folder_id + plan_entries [BAK-60]"
```

---

## Task 2: Shared `FolderOptions` loader

**Files:**
- Create: `Pulse/Features/Library/FolderOptions.swift`
- Modify: `Pulse/Features/Library/MoveToFolderSheet.swift`
- Test: `PulseTests/Features/Library/FolderOptionsTests.swift`

- [ ] **Step 1: Write the failing test**

`PulseTests/Features/Library/FolderOptionsTests.swift`:

```swift
import XCTest
@testable import Pulse

@MainActor
final class FolderOptionsTests: XCTestCase {
    func testRootFirstIndentedListWithDepths() async throws {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store)
        let a = try await repo.createFolder(name: "A", color: .default, parentID: nil)
        let b = try await repo.createFolder(name: "B", color: .default, parentID: a.id)

        let opts = await FolderOptions.load(from: repo)

        XCTAssertEqual(opts.first?.id, nil)                  // Library root first
        XCTAssertEqual(opts.first?.depth, 0)
        let aOpt = try XCTUnwrap(opts.first { $0.id == a.id })
        let bOpt = try XCTUnwrap(opts.first { $0.id == b.id })
        XCTAssertEqual(aOpt.depth, 1)
        XCTAssertEqual(bOpt.depth, 2)
    }

    func testExcludingDropsTheGivenIDs() async throws {
        let store = MockStore(seeded: false)
        let repo = InMemoryFolderRepository(store: store)
        let a = try await repo.createFolder(name: "A", color: .default, parentID: nil)
        let b = try await repo.createFolder(name: "B", color: .default, parentID: a.id)

        let opts = await FolderOptions.load(from: repo, excluding: [a.id, b.id])

        XCTAssertEqual(opts.map(\.id), [nil])                // only Library root remains
    }
}
```

- [ ] **Step 2: Run it — expect FAIL (`FolderOptions` undefined)**

Run: `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/FolderOptionsTests 2>&1 | tail -15`
Expected: compile failure — `cannot find 'FolderOptions' in scope`.

- [ ] **Step 3: Create `FolderOptions.swift`**

```swift
import Foundation

/// A selectable folder destination in an indented (root-first) tree list.
/// `id == nil` is the Library root.
struct FolderOption: Identifiable, Equatable {
    let id: UUID?
    let name: String
    let depth: Int
}

enum FolderOptions {
    /// Walks the folder tree from root and returns an indented, root-first list of
    /// destinations. `excluding` drops the given folder ids (used when moving a
    /// folder, so it can't nest into itself or its subtree); pass `[]` when picking
    /// a destination for a brand-new item.
    @MainActor
    static func load(from folders: any FolderRepository,
                     excluding: Set<UUID> = []) async -> [FolderOption] {
        var all: [Folder] = []
        func gather(parent: UUID?) async {
            let c = try? await folders.contents(of: parent)
            for f in (c?.folders ?? []) { all.append(f); await gather(parent: f.id) }
        }
        await gather(parent: nil)

        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        func depth(of id: UUID) -> Int {
            var d = 0; var cur = byID[id]?.parentID
            while let c = cur { d += 1; cur = byID[c]?.parentID }
            return d
        }
        var opts: [FolderOption] = [FolderOption(id: nil, name: "Library root", depth: 0)]
        for f in all where !excluding.contains(f.id) {
            opts.append(FolderOption(id: f.id, name: f.name, depth: depth(of: f.id) + 1))
        }
        return opts
    }
}
```

- [ ] **Step 4: Adopt in `MoveToFolderModel`**

In `MoveToFolderSheet.swift`, delete the nested `struct Indented` and change `options`'s type + `load()` to reuse `FolderOptions`, keeping the move-specific subtree exclusion:

```swift
    private(set) var options: [FolderOption] = []     // selectable destinations
    private let folderRepo: any FolderRepository

    init(moving: LibraryItemRef, folders: any FolderRepository) {
        self.moving = moving
        self.folderRepo = folders
    }

    func load() async {
        // When moving a folder, exclude itself + its descendants (can't nest into
        // its own subtree). Gathering the tree + indenting is shared with the wizard.
        var excluded: Set<UUID> = []
        if case let .folder(movingID) = moving {
            let all = await allFolders()
            excluded = descendants(of: movingID, in: all).union([movingID])
        }
        options = await FolderOptions.load(from: folderRepo, excluding: excluded)
    }

    private func allFolders() async -> [Folder] {
        var all: [Folder] = []
        func gather(parent: UUID?) async {
            let c = try? await folderRepo.contents(of: parent)
            for f in (c?.folders ?? []) { all.append(f); await gather(parent: f.id) }
        }
        await gather(parent: nil)
        return all
    }
```

Keep `confirm(destination:)` and `descendants(of:in:)` as-is. The view (`MoveToFolderSheet`) references `model.options` with `.id`/`.name`/`.depth` — those are identical on `FolderOption`, so the `ForEach`/`accessibilityIdentifier("move.dest.\(opt.id?.uuidString ?? "root")")` block is unchanged.

- [ ] **Step 5: Run the test + the existing move tests — expect PASS**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/FolderOptionsTests 2>&1 | tail -15`
Expected: PASS. Then a quick full-suite build to confirm `MoveToFolderSheet` still compiles (Step 3 of Task 8 runs the whole suite).

- [ ] **Step 6: Commit**

```bash
git add Pulse/Features/Library/FolderOptions.swift Pulse/Features/Library/MoveToFolderSheet.swift PulseTests/Features/Library/FolderOptionsTests.swift
git commit -m "refactor(library): shared FolderOptions loader for folder-destination pickers [BAK-59]"
```

---

## Task 3: `CreateWizardModel` — state + step navigation

**Files:**
- Create: `Pulse/Features/Builders/CreateWizard/CreateWizardModel.swift`
- Test: `PulseTests/Features/Builders/CreateWizard/CreateWizardModelTests.swift`

- [ ] **Step 1: Write the failing test**

`PulseTests/Features/Builders/CreateWizard/CreateWizardModelTests.swift`:

```swift
import XCTest
@testable import Pulse

@MainActor
final class CreateWizardModelTests: XCTestCase {
    private func make() -> CreateWizardModel {
        let store = MockStore(seeded: true)
        return CreateWizardModel(workouts: InMemoryWorkoutRepository(store: store),
                                 folders: InMemoryFolderRepository(store: store))
    }

    func testStartsAtNameAndAdvancesThroughSteps() {
        let m = make()
        XCTAssertEqual(m.step, .name)
        XCTAssertTrue(m.isFirstStep)
        m.next(); XCTAssertEqual(m.step, .targets)
        m.next(); XCTAssertEqual(m.step, .schedule)
        m.next(); XCTAssertEqual(m.step, .folder)
        XCTAssertTrue(m.isLastStep)
        m.next(); XCTAssertEqual(m.step, .folder)   // no-op past the last step
    }

    func testBackRetreatsAndClampsAtFirst() {
        let m = make()
        m.next(); m.next()
        m.back(); XCTAssertEqual(m.step, .targets)
        m.back(); XCTAssertEqual(m.step, .name)
        m.back(); XCTAssertEqual(m.step, .name)     // no-op before the first step
    }

    func testCanAdvanceRequiresNonEmptyNameOnNameStep() {
        let m = make()
        XCTAssertFalse(m.canAdvance)                // empty name
        m.name = "   "
        XCTAssertFalse(m.canAdvance)                // whitespace only
        m.name = "Push"
        XCTAssertTrue(m.canAdvance)
        m.next()                                    // targets — optional
        XCTAssertTrue(m.canAdvance)
    }

    func testToggleTargetAndWeekday() {
        let m = make()
        m.toggleTarget(.chest); XCTAssertEqual(m.targets, [.chest])
        m.toggleTarget(.chest); XCTAssertTrue(m.targets.isEmpty)
        m.toggleWeekday(3); XCTAssertEqual(m.weekdays, [3])
        m.toggleWeekday(3); XCTAssertTrue(m.weekdays.isEmpty)
    }
}
```

- [ ] **Step 2: Run it — expect FAIL (`CreateWizardModel` undefined)**

Run: `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/CreateWizardModelTests 2>&1 | tail -15`
Expected: `cannot find 'CreateWizardModel' in scope`.

- [ ] **Step 3: Create `CreateWizardModel.swift` (state + nav; `create()` added in Task 4)**

```swift
import Foundation

@MainActor
@Observable
final class CreateWizardModel {
    enum Step: Int, CaseIterable { case name, targets, schedule, folder }

    var step: Step = .name
    var name: String = ""
    var targets: Set<MuscleGroup> = []
    var weekdays: Set<Int> = []
    var folderID: Folder.ID?

    var folderOptions: [FolderOption] = []
    var creating = false

    private let workoutRepo: any WorkoutRepository
    private let folderRepo: any FolderRepository

    init(workouts: any WorkoutRepository,
         folders: any FolderRepository,
         folderID: Folder.ID? = nil) {
        self.workoutRepo = workouts
        self.folderRepo = folders
        self.folderID = folderID
    }

    var isFirstStep: Bool { step == .name }
    var isLastStep: Bool { step == Step.allCases.last }
    var stepNumber: Int { step.rawValue + 1 }          // 1-based, for the progress bar
    var stepCount: Int { Step.allCases.count }

    /// Name is required; Targets/Schedule/Folder are optional.
    var canAdvance: Bool {
        switch step {
        case .name: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    func next() { if let n = Step(rawValue: step.rawValue + 1) { step = n } }
    func back() { if let p = Step(rawValue: step.rawValue - 1) { step = p } }

    func toggleTarget(_ m: MuscleGroup) {
        if targets.contains(m) { targets.remove(m) } else { targets.insert(m) }
    }
    func toggleWeekday(_ day: Int) {
        if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
    }

    func loadFolders() async {
        folderOptions = await FolderOptions.load(from: folderRepo)
    }
}
```

- [ ] **Step 4: Run the test — expect PASS**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/CreateWizardModelTests 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Builders/CreateWizard/CreateWizardModel.swift PulseTests/Features/Builders/CreateWizard/CreateWizardModelTests.swift
git commit -m "feat(wizard): CreateWizardModel draft state + step navigation [BAK-59]"
```

---

## Task 4: `CreateWizardModel.create()` — persist + folder placement

**Files:**
- Modify: `Pulse/Features/Builders/CreateWizard/CreateWizardModel.swift`
- Test: `PulseTests/Features/Builders/CreateWizard/CreateWizardModelTests.swift`

- [ ] **Step 1: Write the failing test (append to `CreateWizardModelTests`)**

```swift
    func testCreatePersistsNameTargetsWeekdaysAndReturnsID() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let m = CreateWizardModel(workouts: workouts,
                                  folders: InMemoryFolderRepository(store: store))
        m.name = "Heavy Push"
        m.toggleTarget(.chest); m.toggleWeekday(5); m.toggleWeekday(1)

        let id = try XCTUnwrap(await m.create())
        let saved = try await workouts.fetchWorkout(id: id)
        XCTAssertEqual(saved?.name, "Heavy Push")
        XCTAssertEqual(saved?.targets, [.chest])
        XCTAssertEqual(saved?.weekdays, [1, 5])             // canonical order
        XCTAssertEqual(saved?.exercises.count, 0)           // empty until the editor
    }

    func testCreatePlacesWorkoutInChosenFolder() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let folders = InMemoryFolderRepository(store: store)
        let folder = try await folders.createFolder(name: "Push days", color: .default, parentID: nil)
        let m = CreateWizardModel(workouts: workouts, folders: folders, folderID: folder.id)
        m.name = "In A Folder"

        let id = try XCTUnwrap(await m.create())
        let contents = try await folders.contents(of: folder.id)
        XCTAssertTrue(contents.workouts.contains { $0.id == id })
    }

    func testCreateAtRootDoesNotPlaceInAnyFolder() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let folders = InMemoryFolderRepository(store: store)
        let m = CreateWizardModel(workouts: workouts, folders: folders, folderID: nil)
        m.name = "At Root"

        let id = try XCTUnwrap(await m.create())
        let root = try await folders.contents(of: nil)
        XCTAssertTrue(root.workouts.contains { $0.id == id })
    }
```

- [ ] **Step 2: Run it — expect FAIL (`create()` undefined)**

Run: `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/CreateWizardModelTests 2>&1 | tail -15`
Expected: `value of type 'CreateWizardModel' has no member 'create'`.

- [ ] **Step 3: Add `create()` to `CreateWizardModel`**

```swift
    /// Persists the draft workout (name + targets + weekdays, zero exercises) and
    /// places it in the chosen folder. Returns the new workout id, or nil on failure.
    func create() async -> Workout.ID? {
        creating = true
        defer { creating = false }
        let draft = Workout(
            name: name.trimmingCharacters(in: .whitespaces),
            weekdays: [1, 2, 3, 4, 5, 6, 7].filter { weekdays.contains($0) },   // canonical order
            order: 0,
            exercises: [],
            targets: MuscleGroup.allCases.filter { targets.contains($0) })
        do {
            let saved = try await workoutRepo.saveWorkout(draft)
            if let folderID { try await folderRepo.moveWorkout(id: saved.id, toFolder: folderID) }
            return saved.id
        } catch {
            return nil
        }
    }
```

- [ ] **Step 4: Run the test — expect PASS**

Run: `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/CreateWizardModelTests 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Builders/CreateWizard/CreateWizardModel.swift PulseTests/Features/Builders/CreateWizard/CreateWizardModelTests.swift
git commit -m "feat(wizard): CreateWizardModel.create persists draft + places in folder [BAK-59]"
```

---

## Task 5: `CreateWizardView` — stepped container + step subviews

**Files:**
- Create: `Pulse/Features/Builders/CreateWizard/CreateWizardView.swift`

No new unit test (SwiftUI view; covered by the UI test in Task 8). Build-only verification.

- [ ] **Step 1: Create `CreateWizardView.swift`**

```swift
import SwiftUI

/// Guided multi-step create flow. Collects name/targets/schedule/folder, then
/// `Create` persists the draft and hands the new workout id to `onCreated` (the
/// caller routes to the editor). Reuses SP1 target chips, SP2 weekday chips, and
/// the shared FolderOptions tree.
struct CreateWizardView: View {
    @State private var model: CreateWizardModel
    private let onCreated: (Workout.ID) -> Void
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    init(model: CreateWizardModel, onCreated: @escaping (Workout.ID) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onCreated = onCreated
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                stepBody
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.spacing[5])
                    .padding(.top, theme.spacing[4])
            }
            footer
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .task { await model.loadFolders() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("NEW WORKOUT · STEP \(model.stepNumber)/\(model.stepCount)")
                .accessibilityIdentifier("wizard.progress")
            HStack(spacing: 4) {
                ForEach(0..<model.stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i < model.stepNumber ? theme.accent : theme.inkFaint)
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, theme.spacing[5]).padding(.top, theme.spacing[3])
    }

    @ViewBuilder private var stepBody: some View {
        switch model.step {
        case .name:     nameStep
        case .targets:  targetsStep
        case .schedule: scheduleStep
        case .folder:   folderStep
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("Name your workout")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(theme.ink)
            TextField("Workout name", text: $model.name)
                .font(.system(size: 28, weight: .bold)).foregroundStyle(theme.ink)
                .accessibilityIdentifier("wizard.name")
        }
    }

    private var targetsStep: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("What does it target?")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(theme.ink)
            Text("Optional — the muscle groups this workout hits.")
                .font(.system(size: 14)).foregroundStyle(theme.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing[1]) {
                    ForEach(MuscleGroup.allCases) { m in
                        PillChip(label: m.rawValue, selected: model.targets.contains(m),
                                 fill: theme.accent, onFill: theme.onAccent) { model.toggleTarget(m) }
                            .accessibilityIdentifier("wizard.target-\(m.rawValue)")
                    }
                }
            }
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("When do you train it?")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(theme.ink)
            Text("Optional — pick recurring weekdays. You can also schedule specific dates later.")
                .font(.system(size: 14)).foregroundStyle(theme.inkSoft)
            let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(zip(1...7, dayLabels)), id: \.0) { day, label in
                        PillChip(label: label, selected: model.weekdays.contains(day),
                                 fill: theme.accent, onFill: theme.onAccent) { model.toggleWeekday(day) }
                            .accessibilityIdentifier("wizard.repeat-day-\(day)")
                    }
                }
            }
        }
    }

    private var folderStep: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("Where should it live?")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.folderOptions) { opt in
                    Button { model.folderID = opt.id } label: {
                        HStack(spacing: 8) {
                            Image(systemName: opt.id == nil ? "tray.full" : "folder")
                                .foregroundStyle(theme.inkSoft)
                            Text(opt.name).foregroundStyle(theme.ink)
                            Spacer()
                            if model.folderID == opt.id {
                                Image(systemName: "checkmark").foregroundStyle(theme.accent)
                            }
                        }
                        .padding(.leading, CGFloat(opt.depth) * 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wizard.folder.\(opt.id?.uuidString ?? "root")")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: theme.spacing[2]) {
            Button(model.isFirstStep ? "Cancel" : "Back") {
                if model.isFirstStep { dismiss() } else { model.back() }
            }
            .buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
            .accessibilityIdentifier("wizard.back")

            Button {
                if model.isLastStep {
                    Task { if let id = await model.create() { onCreated(id) } }
                } else {
                    model.next()
                }
            } label: {
                Text(model.isLastStep ? "Create workout →" : "Continue")
            }
            .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
            .disabled(!model.canAdvance || model.creating)
            .accessibilityIdentifier("wizard.continue")
        }
        .padding(theme.spacing[5])
    }
}

#Preview {
    let store = MockStore(seeded: true)
    return NavigationStack {
        CreateWizardView(model: CreateWizardModel(
            workouts: InMemoryWorkoutRepository(store: store),
            folders: InMemoryFolderRepository(store: store)))
    }
    .environment(Theme())
}
```

- [ ] **Step 2: Generate + build**

Run: `xcodegen generate && xcodebuild -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add project.yml Pulse/Features/Builders/CreateWizard/CreateWizardView.swift
git commit -m "feat(wizard): CreateWizardView stepped container + Name/Targets/Schedule/Folder steps [BAK-59]"
```

---

## Task 6: Restructure builder → editor (hydrate-by-id + save-in-place) + routing swap

**This is one atomic task** — the model init change, all its call sites, and the routing swap must land together to keep the build green.

**Files:**
- Modify: `Pulse/Features/Builders/WorkoutBuilderModel.swift`
- Modify: `Pulse/Features/Builders/WorkoutBuilderView.swift`
- Modify: `Pulse/Features/Builders/SetEditorSheet.swift` (preview)
- Modify: `Pulse/Features/Library/LibraryRoute.swift`
- Modify: `Pulse/Features/Library/CreateChooserSheet.swift`
- Modify: `Pulse/Features/Library/LibraryView.swift`
- Test: `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift`, `PulseTests/Features/Builders/TargetsPickerAcceptanceTests.swift`

- [ ] **Step 1: Write the failing hydration tests**

Rewrite `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift`'s setup to hydrate from a saved workout. Replace the model-construction helper (around lines 9-15) and add hydration assertions. The helper seeds a workout built from `BuilderSampleData.defaultWorkoutItems`, persists it, then hydrates:

```swift
    /// Builds a model hydrated from a saved workout whose exercises are the sample
    /// items, so the existing add/replace/reorder/superset assertions still apply.
    private func makeModel() async -> WorkoutBuilderModel {
        let store = MockStore(seeded: true)
        let exercises = BuilderSampleData.defaultWorkoutItems.map {
            WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                            supersetGroup: $0.supersetGroup, sets: $0.sets)
        }
        let workout = Workout(name: "Editor Test", order: 0, exercises: exercises, targets: [])
        let workouts = InMemoryWorkoutRepository(store: store)
        _ = try! await workouts.saveWorkout(workout)
        let m = WorkoutBuilderModel(workoutID: workout.id,
                                    catalog: InMemoryExerciseRepository(store: store),
                                    workouts: workouts)
        await m.loadCatalog()
        await m.load()
        return m
    }

    func testLoadHydratesNameTargetsAndExercises() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let w = Workout(name: "Leg Day", weekdays: [2, 4], order: 3,
                        exercises: BuilderSampleData.defaultWorkoutItems.map {
                            WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                                            supersetGroup: $0.supersetGroup, sets: $0.sets) },
                        targets: [.legs])
        _ = try await workouts.saveWorkout(w)
        let m = WorkoutBuilderModel(workoutID: w.id,
                                    catalog: InMemoryExerciseRepository(store: store),
                                    workouts: workouts)
        await m.load()
        XCTAssertEqual(m.loadState, .loaded)
        XCTAssertEqual(m.name, "Leg Day")
        XCTAssertEqual(m.targets, [.legs])
        XCTAssertEqual(m.items.count, BuilderSampleData.defaultWorkoutItems.count)
    }

    func testSavePreservesIDWeekdaysAndOrder() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let w = Workout(name: "Keep Me", weekdays: [1, 5], order: 7, exercises: [], targets: [])
        _ = try await workouts.saveWorkout(w)
        let m = WorkoutBuilderModel(workoutID: w.id,
                                    catalog: InMemoryExerciseRepository(store: store),
                                    workouts: workouts)
        await m.load()
        m.name = "Renamed"
        await m.save()
        let saved = try await workouts.fetchWorkout(id: w.id)
        XCTAssertEqual(saved?.id, w.id)              // same id (in-place)
        XCTAssertEqual(saved?.name, "Renamed")
        XCTAssertEqual(saved?.weekdays, [1, 5])      // preserved (edited on WorkoutDetail, not here)
        XCTAssertEqual(saved?.order, 7)
    }
```

Update the other test bodies (lines ~19, 40, 145, 157) to `let model = await makeModel()` (they currently build with the old `items:` init). Update `TargetsPickerAcceptanceTests.swift:18` the same way (hydrate a saved workout whose targets you then toggle).

- [ ] **Step 2: Run — expect FAIL (old init still in place)**

Run: `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutBuilderModelTests 2>&1 | tail -20`
Expected: compile failure — `WorkoutBuilderModel` has no `init(workoutID:catalog:workouts:)` / no `load()` / no `loadState`.

- [ ] **Step 3: Restructure `WorkoutBuilderModel`**

In `WorkoutBuilderModel.swift`, replace the stored properties + `init` + `makeDraft` (keep `loadCatalog`, `group`, `addExercises`, `toggleTarget`, `replaceExercise`, `updateVariation`, `removeItem`, `move`, `toggleLink`, `save`, and the picker/catalog members exactly as they are):

```swift
    var name: String = ""
    var targets: Set<MuscleGroup> = []
    var items: [BuilderExercise] = []
    var pickerPresented = false
    var isReordering = false
    var editingItemID: BuilderExercise.ID? = nil
    var saveState: SaveState = .idle
    var replacingItemID: BuilderExercise.ID? = nil
    var loadState: LibraryLoadState = .loading

    // Exercise Picker state.
    var catalog: [BuilderCatalogGroup] = []
    var catalogLoading = false
    var catalogError: String? = nil

    let workoutID: Workout.ID
    // Preserved verbatim across an in-place save (these are edited elsewhere — the
    // recurring weekdays on WorkoutDetail, the order by the library). The editor
    // only changes name / targets / exercises.
    private var weekdays: [Int] = []
    private var order: Int = 0
    private let catalogRepo: any ExerciseRepository
    private let workoutRepo: any WorkoutRepository

    init(workoutID: Workout.ID, catalog: any ExerciseRepository, workouts: any WorkoutRepository) {
        self.workoutID = workoutID
        self.catalogRepo = catalog
        self.workoutRepo = workouts
    }

    /// Hydrates the editor from the persisted workout. The wizard creates an empty
    /// workout first, so on first open this loads the wizard's name/targets and an
    /// empty exercise list; for edit it loads the full graph.
    func load() async {
        loadState = .loading
        guard let w = try? await workoutRepo.fetchWorkout(id: workoutID) else {
            loadState = .error; return
        }
        name = w.name
        targets = Set(w.targets)
        weekdays = w.weekdays
        order = w.order
        items = w.exercises.map {
            BuilderExercise(exercise: $0.exercise, variationID: $0.variationID,
                            supersetGroup: $0.supersetGroup, sets: $0.sets)
        }
        loadState = .loaded
    }
```

Replace `makeDraft()` so it rebuilds the **same** workout (preserve id/weekdays/order):

```swift
    func makeDraft() -> Workout {
        let workoutExercises = items.map {
            WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                            supersetGroup: $0.supersetGroup, sets: $0.sets)
        }
        return Workout(id: workoutID, name: name, weekdays: weekdays, order: order,
                       exercises: workoutExercises,
                       targets: MuscleGroup.allCases.filter { targets.contains($0) })
    }
```

(`LibraryLoadState` is the existing enum used by `WorkoutDetailModel` — `.loading/.loaded/.error`.)

- [ ] **Step 4: Update `WorkoutBuilderView` — eyebrow, load, loading gate, preview**

In `WorkoutBuilderView.swift`:
- Change the scaffold eyebrow (line 16): `eyebrow: "EDIT WORKOUT"`.
- Add hydration on appear and gate the content on `loadState`. Wrap the inner `VStack` (lines 21-64) so it only renders when loaded:

```swift
        ) {
            if model.loadState == .loaded {
                VStack(alignment: .leading, spacing: theme.spacing[4]) {
                    // ... existing name field / targetRow / exercises / add / superset hint / error ...
                }
                .padding(.vertical, theme.spacing[3])
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity).padding(.top, theme.spacing[6])
                    .accessibilityIdentifier("editor.loading")
            }
        }
        .task { await model.load() }
```

(Keep the two `.sheet` modifiers and `.onChange(of: model.saveState)` exactly as they are.)
- Update the `#Preview` (lines 266-274) to seed + hydrate:

```swift
#Preview {
    let store = MockStore(seeded: true)
    let workouts = InMemoryWorkoutRepository(store: store)
    let w = Workout(name: "Preview", order: 0,
                    exercises: BuilderSampleData.defaultWorkoutItems.map {
                        WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                                        supersetGroup: $0.supersetGroup, sets: $0.sets) },
                    targets: [])
    return NavigationStack {
        WorkoutBuilderView(model: WorkoutBuilderModel(
            workoutID: w.id,
            catalog: InMemoryExerciseRepository(store: store),
            workouts: workouts))
    }
    .environment(Theme())
    .task { _ = try? await workouts.saveWorkout(w) }
}
```

- [ ] **Step 5: Update `SetEditorSheet.swift` preview (line 207-210)**

Change the preview's model construction to the new init (it currently passes `items: BuilderSampleData.defaultWorkoutItems`). Seed a workout + hydrate, mirroring Step 4's preview, or — simpler for a Set-editor preview — construct with an empty editor:

```swift
    let store = MockStore(seeded: true)
    let model = WorkoutBuilderModel(
        workoutID: UUID(),
        catalog: InMemoryExerciseRepository(store: store),
        workouts: InMemoryWorkoutRepository(store: store))
```

(If the preview needs a populated item to drive the Set editor, seed a workout and `await model.load()` as in Step 4.)

- [ ] **Step 6: Routing — `LibraryRoute`, `CreateChooserSheet`, `LibraryView`**

`LibraryRoute.swift`: replace `case workoutBuilder` with two cases and update `marker`:

```swift
    case createWizard
    case workoutEditor(id: UUID)
```
```swift
        case .createWizard:           return "wizard:workout"
        case .workoutEditor(let id):  return "editor:\(id)"
```
(Remove the `.workoutBuilder` case + its `marker` line.)

`CreateChooserSheet.swift` line 28: `id: "create.workout") { onPick(.createWizard) }`.

`LibraryView.swift` `destination(_:)` — replace the `.workoutBuilder` case (lines 186-192) with:

```swift
        case .createWizard:
            CreateWizardView(
                model: CreateWizardModel(workouts: repos.workouts,
                                         folders: repos.folders,
                                         folderID: createParentID),   // BAK-54: seed the current folder
                onCreated: { id in
                    if !path.isEmpty { path.removeLast() }            // pop the wizard…
                    path.append(.workoutEditor(id: id))               // …land in the editor
                })
        case .workoutEditor(let id):
            WorkoutBuilderView(model: WorkoutBuilderModel(
                workoutID: id, catalog: repos.exercises, workouts: repos.workouts))
```

And thread Edit into the existing `.workoutDetail` case (lines 218-223) — add the `onEdit` argument (the property is added in Task 7; add it now so the wiring lands together):

```swift
        case .workoutDetail(let id, let name):
            WorkoutDetailView(
                model: WorkoutDetailModel(
                    workoutID: id, title: name,
                    workoutRepo: repos.workouts,
                    scheduleRepo: repos.schedule,
                    onStart: onStartWorkout),
                onEdit: { editID in path.append(.workoutEditor(id: editID)) })
```

- [ ] **Step 7: Generate, build, run the affected suites**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutBuilderModelTests -only-testing:PulseTests/TargetsPickerAcceptanceTests 2>&1 | tail -20`
Expected: PASS. (Task 7 adds the `onEdit` property to `WorkoutDetailView`; if you build before Task 7, comment the `onEdit:` arg temporarily — but prefer doing Step 6's `onEdit` wiring and Task 7 back-to-back, then build once.)

- [ ] **Step 8: Commit**

```bash
git add Pulse/Features/Builders/WorkoutBuilderModel.swift Pulse/Features/Builders/WorkoutBuilderView.swift Pulse/Features/Builders/SetEditorSheet.swift Pulse/Features/Library/LibraryRoute.swift Pulse/Features/Library/CreateChooserSheet.swift Pulse/Features/Library/LibraryView.swift PulseTests/Features/Builders/WorkoutBuilderModelTests.swift PulseTests/Features/Builders/TargetsPickerAcceptanceTests.swift project.yml
git commit -m "feat(editor): hydrate builder from workout id + save in place; wizard→editor routing [BAK-59][BAK-56]"
```

---

## Task 7: Edit entry on `WorkoutDetailView`

**Files:**
- Modify: `Pulse/Features/Library/WorkoutDetailModel.swift`
- Modify: `Pulse/Features/Library/WorkoutDetailView.swift`

- [ ] **Step 1: Expose the workout id on the model**

In `WorkoutDetailModel.swift`, change `private let workoutID: UUID` to:

```swift
    let workoutID: Workout.ID
```

(Keep the initializer assignment as-is.)

- [ ] **Step 2: Add the `onEdit` entry to `WorkoutDetailView`**

In `WorkoutDetailView.swift`:
- Add the property + initializer parameter:

```swift
struct WorkoutDetailView: View {
    @State private var model: WorkoutDetailModel
    private let onEdit: (Workout.ID) -> Void
    @State private var showScheduleSheet = false
    @State private var schedulePicked = Date()
    @Environment(Theme.self) private var theme

    init(model: WorkoutDetailModel, onEdit: @escaping (Workout.ID) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onEdit = onEdit
    }
```

- Add a toolbar Edit button (attach to the `ScrollView`, after `.task { await model.load() }` on line 29):

```swift
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { onEdit(model.workoutID) }
                    .accessibilityIdentifier("workoutDetail.edit")
            }
        }
```

(The `LibraryView` `.workoutDetail` destination already passes `onEdit:` from Task 6 Step 6.)

- [ ] **Step 3: Generate + build**

Run: `xcodegen generate && xcodebuild -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Pulse/Features/Library/WorkoutDetailModel.swift Pulse/Features/Library/WorkoutDetailView.swift
git commit -m "feat(library): Edit entry on Workout Detail opens the editor [BAK-56]"
```

---

## Task 8: Acceptance + UI coverage; full suite

**Files:**
- Create: `PulseTests/Features/Builders/CreateWizardAcceptanceTests.swift`
- Create: `PulseUITests/CreateWizardUITests.swift`

- [ ] **Step 1: Acceptance test (full create flow + edit-in-place)**

`PulseTests/Features/Builders/CreateWizardAcceptanceTests.swift`:

```swift
import XCTest
@testable import Pulse

@MainActor
final class CreateWizardAcceptanceTests: XCTestCase {
    func testCreateThenEditorAddsExerciseAndKeepsFolderTargetsWeekdays() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let folders = InMemoryFolderRepository(store: store)
        let folder = try await folders.createFolder(name: "Push days", color: .default, parentID: nil)

        // Wizard → Create
        let wiz = CreateWizardModel(workouts: workouts, folders: folders, folderID: folder.id)
        wiz.name = "Heavy Push"
        wiz.toggleTarget(.chest); wiz.toggleWeekday(1); wiz.toggleWeekday(5)
        let newID = try XCTUnwrap(await wiz.create())

        // Editor hydrates the wizard's draft, adds an exercise, saves in place
        let editor = WorkoutBuilderModel(workoutID: newID,
                                         catalog: InMemoryExerciseRepository(store: store),
                                         workouts: workouts)
        await editor.loadCatalog()
        await editor.load()
        XCTAssertEqual(editor.name, "Heavy Push")
        XCTAssertEqual(editor.targets, [.chest])

        // Pick the first catalog exercise via the picker contract.
        let firstGroup = try XCTUnwrap(editor.catalog.first)
        let firstItem = try XCTUnwrap(firstGroup.items.first)
        editor.addExercises([PickedExercise(id: firstItem.id, variationID: nil)])
        await editor.save()

        // Persisted: same id, exercise added, weekdays/targets preserved, still in folder
        let saved = try await workouts.fetchWorkout(id: newID)
        XCTAssertEqual(saved?.id, newID)
        XCTAssertEqual(saved?.exercises.count, 1)
        XCTAssertEqual(saved?.weekdays, [1, 5])
        XCTAssertEqual(saved?.targets, [.chest])
        let contents = try await folders.contents(of: folder.id)
        XCTAssertTrue(contents.workouts.contains { $0.id == newID })
    }

    func testEditExistingWorkoutSavesInPlace() async throws {
        let store = MockStore(seeded: true)
        let workouts = InMemoryWorkoutRepository(store: store)
        let existing = try XCTUnwrap(try await workouts.fetchWorkouts().first)
        let editor = WorkoutBuilderModel(workoutID: existing.id,
                                         catalog: InMemoryExerciseRepository(store: store),
                                         workouts: workouts)
        await editor.load()
        editor.name = "Renamed In Editor"
        await editor.save()
        let saved = try await workouts.fetchWorkout(id: existing.id)
        XCTAssertEqual(saved?.id, existing.id)
        XCTAssertEqual(saved?.name, "Renamed In Editor")
    }
}
```

> **Verify during build:** the exact shape of `PickedExercise` (init label order) and the `BuilderCatalogGroup.items` element type — match them to the SP1 picker definitions. Adjust the `addExercises([...])` line if the initializer differs.

- [ ] **Step 2: UI test (wizard → editor; editor add; Edit entry)**

`PulseUITests/CreateWizardUITests.swift`:

```swift
import XCTest

final class CreateWizardUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]
        app.launch()
        return app
    }

    private func openLibrary(_ app: XCUIApplication) {
        app.buttons["Library"].firstMatch.tap()
    }

    func testWizardToEditorCreatesAndAddsExercise() {
        let app = launch()
        openLibrary(app)

        app.buttons["library.create"].tap()
        app.buttons["create.workout"].tap()

        // Step 1: name
        let name = app.textFields["wizard.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("UI Wizard WO")

        // Steps 2-4: targets → schedule → folder (root), then Create
        app.buttons["wizard.continue"].tap()                       // → targets
        app.buttons["wizard.target-Chest"].tap()
        app.buttons["wizard.continue"].tap()                       // → schedule
        app.buttons["wizard.repeat-day-1"].tap()
        app.buttons["wizard.continue"].tap()                       // → folder
        app.buttons["wizard.folder.root"].tap()
        app.buttons["wizard.continue"].tap()                       // Create

        // Editor opens, hydrated with the name
        let editorName = app.textFields["workout-name"]
        XCTAssertTrue(editorName.waitForExistence(timeout: 5))
        XCTAssertEqual(editorName.value as? String, "UI Wizard WO")

        // Add an exercise via the picker
        app.buttons["add-exercise"].tap()
        let firstPick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'picker.row.'")).firstMatch
        XCTAssertTrue(firstPick.waitForExistence(timeout: 5))
        firstPick.tap()
        app.buttons["picker.confirm"].tap()
        // An exercise row appears in the editor
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'exercise-row-'")).firstMatch.waitForExistence(timeout: 5))
    }

    func testEditEntryOpensHydratedEditor() {
        let app = launch()
        openLibrary(app)

        // Open a seeded workout's detail, then Edit.
        let firstWorkout = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'workout.'")).firstMatch
        XCTAssertTrue(firstWorkout.waitForExistence(timeout: 5))
        firstWorkout.tap()
        let edit = app.buttons["workoutDetail.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()
        XCTAssertTrue(app.textFields["workout-name"].waitForExistence(timeout: 5))
    }
}
```

> **Verify during build:** the picker row + confirm accessibility ids (`picker.row.*` / `picker.confirm`) against the SP1 `ExercisePickerSheet`; substitute the real ids. The workout-row id prefix is `workout.` (`LibraryRowViews.swift`). If the mock library's first row isn't a workout (folders/programs sort first), adjust the selector to a known seeded workout name, e.g. `app.buttons["workout.Push"]`.

- [ ] **Step 3: Generate + run the FULL suite (unit + UI)**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30`
Expected: all `PulseTests` + `PulseUITests` pass (the build stamp/CI parity — full suite, no `-only-testing` gate).

- [ ] **Step 4: Commit**

```bash
git add PulseTests/Features/Builders/CreateWizardAcceptanceTests.swift PulseUITests/CreateWizardUITests.swift project.yml
git commit -m "test(wizard): acceptance + UI coverage for create flow + editor + edit entry [BAK-59]"
```

---

## Self-review notes (spec coverage)

- **Multi-step wizard, progress bar, Custom-only** → Tasks 3-5 (`CreateWizardModel.Step`, header progress capsules, no presets).
- **Steps Name→Targets→Schedule→Folder→Create** → Task 5 step subviews; SP1 chips + SP2 weekday chips reused; Folder via shared `FolderOptions` (Task 2).
- **Land in the editor after Create** → Task 6 routing (`onCreated` → `.workoutEditor`).
- **Editor reused for Edit (BAK-56)** → Tasks 6-7 (hydrate-by-id; Edit toolbar entry).
- **Add sheet launches the wizard** → Task 6 (`CreateChooserSheet` → `.createWizard`).
- **Folder honored on create (BAK-54)** → Task 6 (`createParentID` seeds the wizard).
- **Reuses SP2 weekdays/resolver** → wizard persists `weekdays`; editor preserves them; Today/Plan re-resolve via the existing resolver (no change needed).
- **Edge cases:** name required (`canAdvance`); cancel/back discards (nothing persisted before `create()`); zero-exercise create (editor adds; Start stays disabled per workout-detail spec); in-place save preserves id + (via BAK-60) folder + schedule.
- **Foundation (BAK-60):** Task 1 — real-path folder/schedule preservation; mock contract covered by Task 6/8 tests; live path verified by reasoning + on-device.
- **Out of scope:** Layout/Pattern, presets, SP4 settings sheet, templates/share, frequency/cooldowns — not in any task.
