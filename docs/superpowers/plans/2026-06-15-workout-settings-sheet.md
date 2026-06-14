# Per-workout Settings Sheet Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One per-workout **Settings sheet** (opened from the editor `⋯` + a Workout-Detail gear) that consolidates Schedule, Targets, Rest timer (new), Notes (new), Folder, and Delete (new) — with the rest override wired into the live session.

**Architecture:** `Workout` gains `restSeconds: Int?` + `notes: String` (migration `0010`). A new `WorkoutSettingsModel`/`WorkoutSettingsSheet` holds the **full hydrated workout** and persists each setting in place (BAK-60-safe `saveWorkout` / `moveWorkout` / `setPlan`). Schedule moves off `WorkoutDetailView`; Targets move off the editor. `ActiveWorkoutModel.restTotal` becomes `workout.restSeconds ?? defaultRestSeconds`, with the global default synced into the model by `AppShell`.

**Tech Stack:** SwiftUI, iOS 17+, `@Observable` MVVM, Supabase (PostgREST), XcodeGen, XCTest + XCUITest.

**Spec:** `docs/superpowers/specs/2026-06-15-workout-settings-sheet-design.md` · **Linear:** [BAK-63](https://linear.app/bakinglions/issue/BAK-63)

---

## File structure

**Create:**
- `Pulse/Features/Library/WorkoutSettings/WorkoutSettingsModel.swift` — `@Observable` model; holds the full workout, persists each setting.
- `Pulse/Features/Library/WorkoutSettings/WorkoutSettingsSheet.swift` — `SheetChrome` view with the 6 sections.
- `supabase/migrations/0010_workout_settings.sql`
- `PulseTests/Features/Library/WorkoutSettingsModelTests.swift`
- `PulseTests/Features/Library/WorkoutSettingsAcceptanceTests.swift`
- `PulseUITests/WorkoutSettingsUITests.swift`

**Modify:**
- `Pulse/Core/Models/WorkoutModels.swift` — `Workout.restSeconds` + `.notes`.
- `Pulse/Core/Data/Supabase/Rows/Rows.swift` — `WorkoutRow` reads the two columns.
- `Pulse/Core/Data/Supabase/Rows/WriteRows.swift` — `WorkoutWriteRow` writes them.
- `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` — `defaultRestSeconds` + computed `restTotal`.
- `Pulse/App/AppShell.swift` — load settings → `session.defaultRestSeconds`.
- `Pulse/Features/Builders/BuilderUI.swift` — `BuilderScaffold` overflow becomes a tappable button (`onOverflow`).
- `Pulse/Features/Builders/WorkoutBuilderView.swift` — drop `targetRow`; wire `⋯` → settings sheet; re-hydrate on dismiss.
- `Pulse/Features/Library/WorkoutDetailView.swift` — drop the schedule block; add a gear → settings sheet.
- `Pulse/Features/Library/WorkoutDetailModel.swift` — shed `weekdays`/`toggleWeekday`/`scheduleOnDate`.
- Tests retargeted: `PulseUITests/WorkoutScheduleUITests.swift`, `PulseTests/Features/Library/WorkoutDetailScheduleTests.swift`, `PulseTests/Features/Library/WorkoutDetailModelTests.swift`, `PulseTests/Features/Builders/TargetsPickerAcceptanceTests.swift`, `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift` (targets assertions).

---

## Task 1: Data model + migration + row threading

**Files:**
- Modify: `Pulse/Core/Models/WorkoutModels.swift`
- Create: `supabase/migrations/0010_workout_settings.sql`
- Modify: `Pulse/Core/Data/Supabase/Rows/Rows.swift` (`WorkoutRow`), `Pulse/Core/Data/Supabase/Rows/WriteRows.swift` (`WorkoutWriteRow`)
- Modify: `Pulse/Core/Data/Supabase/SupabaseWorkoutRepository.swift` (the `saveWorkout` write row)
- Test: `PulseTests/Core/Models/WorkoutWeekdaysTests.swift` (add a round-trip case) — or a new `WorkoutSettingsRoundTripTests`.

- [ ] **Step 1: Write the failing test**

Create `PulseTests/Core/Models/WorkoutSettingsRoundTripTests.swift`:

```swift
import XCTest
@testable import Pulse

@MainActor
final class WorkoutSettingsRoundTripTests: XCTestCase {
    func testRestSecondsAndNotesRoundTripThroughInMemoryRepo() async throws {
        let store = MockStore(seeded: true)
        let repo = InMemoryWorkoutRepository(store: store)
        var w = Workout(name: "Cfg", order: 0, exercises: [], targets: [])
        w.restSeconds = 120
        w.notes = "Heavy day — belt on top sets."
        _ = try await repo.saveWorkout(w)
        let fetched = try await repo.fetchWorkout(id: w.id)
        XCTAssertEqual(fetched?.restSeconds, 120)
        XCTAssertEqual(fetched?.notes, "Heavy day — belt on top sets.")
    }

    func testDefaultsAreNilRestAndEmptyNotes() {
        let w = Workout(name: "Plain", order: 0, exercises: [], targets: [])
        XCTAssertNil(w.restSeconds)
        XCTAssertEqual(w.notes, "")
    }
}
```

- [ ] **Step 2: Run it — expect FAIL (no `restSeconds`/`notes`)**

Run: `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutSettingsRoundTripTests 2>&1 | tail -15`
Expected: compile failure — `value of type 'Workout' has no member 'restSeconds'`.

- [ ] **Step 3: Add fields to `Workout`**

In `WorkoutModels.swift`, the `Workout` struct becomes:

```swift
struct Workout: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var weekdays: [Int] = []     // 1...7 (Mon…Sun), empty = unscheduled
    var order: Int
    var exercises: [WorkoutExercise]
    var targets: [MuscleGroup] = []
    var restSeconds: Int? = nil   // per-workout rest override; nil = global default
    var notes: String = ""
}
```

- [ ] **Step 4: Create the migration**

`supabase/migrations/0010_workout_settings.sql`:

```sql
-- BAK-63: per-workout settings — a rest-timer override and freeform notes.
alter table workouts add column rest_seconds int
  check (rest_seconds is null or rest_seconds between 15 and 600);
alter table workouts add column notes text not null default '';
```

(Apply via the Supabase dashboard — no local psql.)

- [ ] **Step 5: Thread the read row**

In `Rows.swift`, `WorkoutRow` gains the two columns + maps them:

```swift
struct WorkoutRow: Codable {
    let id: UUID
    let name: String
    let weekdays: [Int]?
    let order: Int
    let targets: [String]?
    let restSeconds: Int?     // rest_seconds
    let notes: String?        // notes
    let workoutExercises: [WorkoutExerciseRow]?   // embed: workout_exercises(...)
    func toModel() -> Workout {
        Workout(id: id, name: name, weekdays: weekdays ?? [], order: order,
                exercises: (workoutExercises ?? [])
                    .sorted { $0.order < $1.order }
                    .compactMap { $0.toModel() },
                targets: (targets ?? []).map(MuscleGroup.from(catalog:)),
                restSeconds: restSeconds,
                notes: notes ?? "")
    }
}
```

- [ ] **Step 6: Thread the write row**

In `WriteRows.swift`, `WorkoutWriteRow` carries the two columns (explicit-null for `restSeconds`):

```swift
struct WorkoutWriteRow: Encodable {
    let id: UUID
    let programId: UUID
    let name: String
    let weekdays: [Int]
    let order: Int
    let targets: [String]
    let restSeconds: Int?
    let notes: String

    enum CodingKeys: String, CodingKey { case id, programId, name, weekdays, order, targets, restSeconds, notes }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(programId, forKey: .programId)
        try c.encode(name, forKey: .name)
        try c.encode(weekdays, forKey: .weekdays)
        try c.encode(order, forKey: .order)
        try c.encode(targets, forKey: .targets)
        try c.encode(restSeconds, forKey: .restSeconds)   // null when nil
        try c.encode(notes, forKey: .notes)
    }
}
```

Update the two `WorkoutWriteRow(...)` construction sites to pass the new fields:
- `WorkoutGraphWriter.insert(_:programID:)` (in `WriteRows.swift`): add `restSeconds: $0.restSeconds, notes: $0.notes`.
- `SupabaseWorkoutRepository.saveWorkout` (the `let row = WorkoutWriteRow(...)`): add `restSeconds: workout.restSeconds, notes: workout.notes`.

- [ ] **Step 7: Run the test — expect PASS**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutSettingsRoundTripTests 2>&1 | tail -15`
Expected: PASS. (InMemory repo stores the struct, so the round-trip works without a live DB.)

- [ ] **Step 8: Commit**

```bash
git add Pulse/Core/Models/WorkoutModels.swift supabase/migrations/0010_workout_settings.sql Pulse/Core/Data/Supabase/Rows/Rows.swift Pulse/Core/Data/Supabase/Rows/WriteRows.swift Pulse/Core/Data/Supabase/SupabaseWorkoutRepository.swift PulseTests/Core/Models/WorkoutSettingsRoundTripTests.swift project.yml
git commit -m "feat(workouts): Workout.restSeconds + notes (0010) + row threading [BAK-63]"
```

---

## Task 2: Wire rest into `ActiveWorkoutModel`

**Files:**
- Modify: `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift:41` (`restTotal`) + add `defaultRestSeconds`
- Test: `PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift`

- [ ] **Step 1: Write the failing test (append to `ActiveWorkoutModelTests`)**

```swift
    func testEffectiveRestUsesPerWorkoutOverride() {
        let m = makeModel()
        var w = ActiveWorkoutSample.workout
        w.restSeconds = 120
        m.startWorkout(w)
        XCTAssertEqual(m.restTotal, 120, accuracy: 0.001)
    }

    func testEffectiveRestFallsBackToGlobalDefault() {
        let m = makeModel()
        m.defaultRestSeconds = 75
        var w = ActiveWorkoutSample.workout
        w.restSeconds = nil
        m.startWorkout(w)
        XCTAssertEqual(m.restTotal, 75, accuracy: 0.001)
    }
```

(`makeModel()` is the existing test helper in this file.)

- [ ] **Step 2: Run it — expect FAIL**

Run: `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/ActiveWorkoutModelTests/testEffectiveRestUsesPerWorkoutOverride 2>&1 | tail -15`
Expected: FAIL — `restTotal` is a constant 90 / `defaultRestSeconds` undefined.

- [ ] **Step 3: Replace the hardcoded `restTotal`**

In `ActiveWorkoutModel.swift`, replace line 41 (`let restTotal: TimeInterval = 90`) with:

```swift
    // rest state (absolute end is Live-Activity-friendly). The effective rest is the
    // workout's own override, else the user's global default (synced by AppShell).
    var defaultRestSeconds: Int = 90
    var restTotal: TimeInterval { TimeInterval(workout.restSeconds ?? defaultRestSeconds) }
```

(`restTotal` stays a public read — `startRest()` line 186 already reads it, now computed. `defaultRestSeconds` is a settable `var`, mirroring `soundOnRestEnd`.)

- [ ] **Step 4: Run the tests — expect PASS**

Run: `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/ActiveWorkoutModelTests 2>&1 | tail -15`
Expected: PASS (incl. the existing `testMinusStepperDecrementsWeight`-style tests — `ActiveWorkoutSample.workout.restSeconds` is nil and `defaultRestSeconds` defaults 90, so behavior is unchanged).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift
git commit -m "feat(active): effective rest = workout override ?? global default [BAK-63]"
```

---

## Task 3: Sync the global default into the session (`AppShell`)

**Files:**
- Modify: `Pulse/App/AppShell.swift`

No new unit test (wiring); verified by build + the rest unit tests above + on-device. UI tests stay green (mock default = 90).

- [ ] **Step 1: Load settings on appear and set `session.defaultRestSeconds`**

In `AppShell.swift`, find the `tabs`/`shell` body's root container (the `TabView`/takeover `Group`). Add a `.task` that loads settings once and syncs the default rest into the session. Place it on the top-level view returned by `body` (alongside existing modifiers):

```swift
        .task {
            // Sync the user's global default rest into the active-session engine
            // (per-workout overrides come from the workout itself). Settings load is
            // async; the session is built synchronously, so resolve it here on appear.
            if let settings = try? await container.settings.load() {
                session.defaultRestSeconds = settings.defaultRestSeconds
            }
        }
```

(If `body` has no single obvious anchor, attach it to the `shell` computed property's top view. `session` is the `ActiveWorkoutModel` already held by `AppShell`; `container.settings` is the `SettingsRepository`.)

- [ ] **Step 2: Build + confirm the active-flow UI tests still pass**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseUITests/ActiveWorkoutFlowTests 2>&1 | tail -15`
Expected: PASS (mock settings default to 90s; SampleData workouts have `restSeconds: nil`, so the live timer stays 90s and `testMinusStepperDecrementsWeight` etc. are unaffected).

- [ ] **Step 3: Commit**

```bash
git add Pulse/App/AppShell.swift
git commit -m "feat(active): sync global default rest from settings into the session [BAK-63]"
```

---

## Task 4: `WorkoutSettingsModel`

**Files:**
- Create: `Pulse/Features/Library/WorkoutSettings/WorkoutSettingsModel.swift`
- Test: `PulseTests/Features/Library/WorkoutSettingsModelTests.swift`

- [ ] **Step 1: Write the failing tests**

`PulseTests/Features/Library/WorkoutSettingsModelTests.swift`:

```swift
import XCTest
@testable import Pulse

@MainActor
final class WorkoutSettingsModelTests: XCTestCase {
    private func seededWorkout(_ store: MockStore) async throws -> Workout {
        let repo = InMemoryWorkoutRepository(store: store)
        var w = Workout(name: "Push", weekdays: [1], order: 0,
                        exercises: BuilderSampleData.defaultWorkoutItems.map {
                            WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                                            supersetGroup: $0.supersetGroup, sets: $0.sets) },
                        targets: [.chest])
        _ = try await repo.saveWorkout(w)
        return w
    }

    private func make(_ store: MockStore) -> WorkoutSettingsModel {
        WorkoutSettingsModel(workoutID: store.allWorkouts.first!.id,
                             workoutRepo: InMemoryWorkoutRepository(store: store),
                             scheduleRepo: InMemoryScheduleRepository(store: store),
                             folderRepo: InMemoryFolderRepository(store: store))
    }

    func testLoadHydratesAllSettings() async throws {
        let store = MockStore(seeded: false)
        let w = try await seededWorkout(store)
        let m = WorkoutSettingsModel(workoutID: w.id,
                                     workoutRepo: InMemoryWorkoutRepository(store: store),
                                     scheduleRepo: InMemoryScheduleRepository(store: store),
                                     folderRepo: InMemoryFolderRepository(store: store))
        await m.load()
        XCTAssertEqual(m.weekdays, [1])
        XCTAssertEqual(m.targets, [.chest])
        XCTAssertNil(m.restSeconds)
        XCTAssertEqual(m.notes, "")
    }

    func testSettingRestNotesPersistsAndKeepsExercises() async throws {
        let store = MockStore(seeded: false)
        let w = try await seededWorkout(store)
        let repo = InMemoryWorkoutRepository(store: store)
        let m = WorkoutSettingsModel(workoutID: w.id, workoutRepo: repo,
                                     scheduleRepo: InMemoryScheduleRepository(store: store),
                                     folderRepo: InMemoryFolderRepository(store: store))
        await m.load()
        await m.setRestSeconds(120)
        await m.setNotes("Belt on top sets")
        let saved = try await repo.fetchWorkout(id: w.id)
        XCTAssertEqual(saved?.restSeconds, 120)
        XCTAssertEqual(saved?.notes, "Belt on top sets")
        XCTAssertEqual(saved?.exercises.count, BuilderSampleData.defaultWorkoutItems.count)  // exercises preserved
        XCTAssertEqual(saved?.weekdays, [1])                                                 // schedule preserved
    }

    func testToggleWeekdayAndTargetPersist() async throws {
        let store = MockStore(seeded: false)
        let w = try await seededWorkout(store)
        let repo = InMemoryWorkoutRepository(store: store)
        let m = WorkoutSettingsModel(workoutID: w.id, workoutRepo: repo,
                                     scheduleRepo: InMemoryScheduleRepository(store: store),
                                     folderRepo: InMemoryFolderRepository(store: store))
        await m.load()
        await m.toggleWeekday(5)         // add Friday
        await m.toggleTarget(.back)
        let saved = try await repo.fetchWorkout(id: w.id)
        XCTAssertEqual(saved?.weekdays, [1, 5])
        XCTAssertEqual(Set(saved?.targets ?? []), [.chest, .back])
    }

    func testUseDefaultRestClearsOverride() async throws {
        let store = MockStore(seeded: false)
        let w = try await seededWorkout(store)
        let repo = InMemoryWorkoutRepository(store: store)
        let m = WorkoutSettingsModel(workoutID: w.id, workoutRepo: repo,
                                     scheduleRepo: InMemoryScheduleRepository(store: store),
                                     folderRepo: InMemoryFolderRepository(store: store))
        await m.load()
        await m.setRestSeconds(120)
        await m.useDefaultRest()
        let saved = try await repo.fetchWorkout(id: w.id)
        XCTAssertNil(saved?.restSeconds)
    }

    func testDeleteRemovesWorkout() async throws {
        let store = MockStore(seeded: false)
        let w = try await seededWorkout(store)
        let repo = InMemoryWorkoutRepository(store: store)
        let m = WorkoutSettingsModel(workoutID: w.id, workoutRepo: repo,
                                     scheduleRepo: InMemoryScheduleRepository(store: store),
                                     folderRepo: InMemoryFolderRepository(store: store))
        await m.load()
        await m.delete()
        let fetched = try await repo.fetchWorkout(id: w.id)
        XCTAssertNil(fetched)
    }
}
```

> **Verify during build:** the exact name of the in-memory schedule repo (`InMemoryScheduleRepository`) + its `init(store:)`, and that `ScheduleRepository.setPlan(_:on:)` is the persist API (used by the old `WorkoutDetailModel.scheduleOnDate`). Adjust constructors to match.

- [ ] **Step 2: Run — expect FAIL (`WorkoutSettingsModel` undefined)**

Run: `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutSettingsModelTests 2>&1 | tail -15`
Expected: `cannot find 'WorkoutSettingsModel' in scope`.

- [ ] **Step 3: Create `WorkoutSettingsModel`**

```swift
import Foundation

@MainActor
@Observable
final class WorkoutSettingsModel {
    private(set) var loadState: LibraryLoadState = .loading
    var weekdays: Set<Int> = []
    var targets: Set<MuscleGroup> = []
    var restSeconds: Int?
    var notes: String = ""
    var folderID: Folder.ID?
    var folderOptions: [FolderOption] = []
    private(set) var deleted = false

    let workoutID: Workout.ID
    /// The full hydrated workout (incl. exercises). Every persist overrides ONE field
    /// on this and re-saves it, so a settings change never drops exercises/identity.
    private var workout: Workout?
    private let workoutRepo: any WorkoutRepository
    private let scheduleRepo: any ScheduleRepository
    private let folderRepo: any FolderRepository

    init(workoutID: Workout.ID,
         workoutRepo: any WorkoutRepository,
         scheduleRepo: any ScheduleRepository,
         folderRepo: any FolderRepository) {
        self.workoutID = workoutID
        self.workoutRepo = workoutRepo
        self.scheduleRepo = scheduleRepo
        self.folderRepo = folderRepo
    }

    func load() async {
        loadState = .loading
        guard let w = try? await workoutRepo.fetchWorkout(id: workoutID) else {
            loadState = .error; return
        }
        workout = w
        weekdays = Set(w.weekdays)
        targets = Set(w.targets)
        restSeconds = w.restSeconds
        notes = w.notes
        folderOptions = await FolderOptions.load(from: folderRepo)
        loadState = .loaded
    }

    private func persist(_ mutate: (inout Workout) -> Void) async {
        guard var w = workout else { return }
        mutate(&w)
        do { _ = try await workoutRepo.saveWorkout(w); workout = w } catch { }
    }

    func toggleWeekday(_ day: Int) async {
        if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
        let canonical = [1, 2, 3, 4, 5, 6, 7].filter { weekdays.contains($0) }
        await persist { $0.weekdays = canonical }
    }

    func scheduleOnDate(_ date: Date) async {
        try? await scheduleRepo.setPlan(.workout(workoutID), on: date)
    }

    func toggleTarget(_ m: MuscleGroup) async {
        if targets.contains(m) { targets.remove(m) } else { targets.insert(m) }
        let canonical = MuscleGroup.allCases.filter { targets.contains($0) }
        await persist { $0.targets = canonical }
    }

    func setRestSeconds(_ seconds: Int) async {
        let clamped = min(600, max(15, seconds))
        restSeconds = clamped
        await persist { $0.restSeconds = clamped }
    }

    func useDefaultRest() async {
        restSeconds = nil
        await persist { $0.restSeconds = nil }
    }

    func setNotes(_ text: String) async {
        notes = text
        await persist { $0.notes = text }
    }

    func setFolder(_ id: Folder.ID?) async {
        folderID = id
        try? await folderRepo.moveWorkout(id: workoutID, toFolder: id)
    }

    func delete() async {
        do { try await workoutRepo.deleteWorkout(id: workoutID); deleted = true } catch { }
    }
}
```

- [ ] **Step 4: Run the tests — expect PASS**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutSettingsModelTests 2>&1 | tail -15`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Library/WorkoutSettings/WorkoutSettingsModel.swift PulseTests/Features/Library/WorkoutSettingsModelTests.swift project.yml
git commit -m "feat(settings): WorkoutSettingsModel — full-workout-preserving setting persists [BAK-63]"
```

---

## Task 5: `WorkoutSettingsSheet` view

**Files:**
- Create: `Pulse/Features/Library/WorkoutSettings/WorkoutSettingsSheet.swift`

Build-only (covered by the UI test in Task 8).

- [ ] **Step 1: Create the sheet**

```swift
import SwiftUI

/// Per-workout Settings — Schedule, Targets, Rest, Notes, Folder, Delete in one sheet.
/// Opened from the editor `⋯` and the Workout-Detail gear. Each edit persists live.
struct WorkoutSettingsSheet: View {
    @State private var model: WorkoutSettingsModel
    let title: String
    let onDeleted: () -> Void
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showScheduleSheet = false
    @State private var schedulePicked = Date()
    @State private var confirmDelete = false

    init(model: WorkoutSettingsModel, title: String, onDeleted: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.title = title
        self.onDeleted = onDeleted
    }

    var body: some View {
        SheetChrome(eyebrow: "WORKOUT", title: "\(title).", onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: theme.spacing[4]) {
                scheduleSection
                targetsSection
                restSection
                notesSection
                folderSection
                deleteSection
            }
            .padding(.bottom, theme.spacing[6])
            .task { await model.load() }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("REPEATS ON")
            let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(zip(1...7, dayLabels)), id: \.0) { day, label in
                        PillChip(label: label, selected: model.weekdays.contains(day),
                                 fill: theme.accent, onFill: theme.onAccent) {
                            Task { await model.toggleWeekday(day) }
                        }
                        .accessibilityIdentifier("settings.repeat-day-\(day)")
                    }
                }
            }
            Button { schedulePicked = Date(); showScheduleSheet = true } label: {
                Text("Schedule on a date")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.scheduleDate")
            .sheet(isPresented: $showScheduleSheet) {
                NavigationStack {
                    DatePicker("Pick a date", selection: $schedulePicked, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .navigationTitle("Schedule Workout").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showScheduleSheet = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") { showScheduleSheet = false; Task { await model.scheduleOnDate(schedulePicked) } }.fontWeight(.semibold)
                            }
                        }
                }
                .presentationDetents([.medium, .large]).environment(theme)
            }
        }
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("TARGETS")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing[1]) {
                    ForEach(MuscleGroup.allCases) { m in
                        PillChip(label: m.rawValue, selected: model.targets.contains(m),
                                 fill: theme.accent, onFill: theme.onAccent) {
                            Task { await model.toggleTarget(m) }
                        }
                        .accessibilityIdentifier("settings.target-\(m.rawValue)")
                    }
                }
            }
        }
    }

    private var restSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("REST TIMER")
            HStack(spacing: theme.spacing[3]) {
                Button { Task { await model.setRestSeconds((model.restSeconds ?? 90) - 15) } } label: {
                    Image(systemName: "minus.circle").font(.system(size: 22)).foregroundStyle(theme.accent)
                }.accessibilityIdentifier("settings.rest.stepper.dec")
                Text(model.restSeconds.map { "\($0)s" } ?? "Default")
                    .font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(theme.ink)
                    .frame(minWidth: 80)
                    .accessibilityIdentifier("settings.rest.value")
                Button { Task { await model.setRestSeconds((model.restSeconds ?? 90) + 15) } } label: {
                    Image(systemName: "plus.circle").font(.system(size: 22)).foregroundStyle(theme.accent)
                }.accessibilityIdentifier("settings.rest.stepper.inc")
                Spacer()
                if model.restSeconds != nil {
                    Button { Task { await model.useDefaultRest() } } label: {
                        Text("USE DEFAULT").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(theme.inkSoft)
                    }.accessibilityIdentifier("settings.rest.useDefault")
                }
            }
            Text(model.restSeconds == nil ? "Uses your global default rest timer." : "Overrides the global default for this workout.")
                .font(.system(size: 12)).foregroundStyle(theme.inkSoft)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("NOTES")
            TextField("Type anything…", text: Binding(get: { model.notes }, set: { model.notes = $0 }), axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 15)).foregroundStyle(theme.ink)
                .padding(theme.spacing[3])
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.inkFaint, lineWidth: 1.5))
                .onSubmit { Task { await model.setNotes(model.notes) } }
                .accessibilityIdentifier("settings.notes")
            Button { Task { await model.setNotes(model.notes) } } label: {
                Text("Save notes").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.accent)
            }.buttonStyle(.plain).accessibilityIdentifier("settings.notes.save")
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("FOLDER")
            ForEach(model.folderOptions) { opt in
                Button { Task { await model.setFolder(opt.id) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: opt.id == nil ? "tray.full" : "folder").foregroundStyle(theme.inkSoft)
                        Text(opt.name).foregroundStyle(theme.ink)
                        Spacer()
                        if model.folderID == opt.id { Image(systemName: "checkmark").foregroundStyle(theme.accent) }
                    }
                    .padding(.leading, CGFloat(opt.depth) * 16).padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.folder.\(opt.id?.uuidString ?? "root")")
            }
        }
    }

    private var deleteSection: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            HStack(spacing: 8) { Image(systemName: "trash"); Text("Delete workout").font(.system(size: 15, weight: .semibold)) }
                .foregroundStyle(theme.accent2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.delete")
        .alert("Delete this workout?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await model.delete(); dismiss(); onDeleted() } }
        } message: { Text("This can't be undone.") }
    }
}
```

> **Verify during build:** `SheetChrome`'s exact init label order (`eyebrow:title:onClose:` per `BottomSheet.swift`), `StatLabel`/`PillChip` signatures, and that `TextField(..., axis: .vertical)` + `.lineLimit(_:)` range compile on the iOS 17 baseline (fall back to a fixed `lineLimit` if not).

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Library/WorkoutSettings/WorkoutSettingsSheet.swift project.yml
git commit -m "feat(settings): WorkoutSettingsSheet — schedule/targets/rest/notes/folder/delete [BAK-63]"
```

---

## Task 6: Relocate Schedule off Workout Detail + add the gear

**Files:**
- Modify: `Pulse/Features/Library/WorkoutDetailView.swift`, `Pulse/Features/Library/WorkoutDetailModel.swift`
- Modify: `Pulse/App/AppShell.swift` or `Pulse/Features/Library/LibraryView.swift` (construct the settings model where `WorkoutDetailView` is built)
- Retarget: `PulseUITests/WorkoutScheduleUITests.swift`, `PulseTests/Features/Library/WorkoutDetailScheduleTests.swift`, `PulseTests/Features/Library/WorkoutDetailModelTests.swift`

- [ ] **Step 1: Strip schedule from `WorkoutDetailModel`**

Remove `weekdays`, `toggleWeekday(_:)`, `scheduleOnDate(_:)` and the `scheduleRepo` dependency from `WorkoutDetailModel` (they now live in `WorkoutSettingsModel`). Keep `load()` (drop the `weekdays = Set(w.weekdays)` line), `start()`, `canStart`, `rows`, `workout`, `workoutID`, `title`. The init loses `scheduleRepo`:

```swift
    init(workoutID: Workout.ID,
         title: String,
         workoutRepo: any WorkoutRepository,
         onStart: @escaping (Workout) -> Void) {
        self.workoutID = workoutID
        self.title = title
        self.workoutRepo = workoutRepo
        self.onStart = onStart
    }
```

- [ ] **Step 2: Strip the schedule block from `WorkoutDetailView` + add the gear**

Remove the `StatLabel("REPEATS ON")` … `.padding(.bottom, 8)` block (the weekday chips + "Schedule on a date" sheet) from `content`'s `.loaded` case — leaving `StatLabel("EXERCISES · …")` + the rows. Add a gear toolbar item that presents the settings sheet, and an `onSettings` closure:

```swift
struct WorkoutDetailView: View {
    @State private var model: WorkoutDetailModel
    private let onEdit: (Workout.ID) -> Void
    private let settingsModel: () -> WorkoutSettingsModel
    @State private var showSettings = false
    @Environment(Theme.self) private var theme

    init(model: WorkoutDetailModel,
         onEdit: @escaping (Workout.ID) -> Void = { _ in },
         settingsModel: @escaping () -> WorkoutSettingsModel) {
        _model = State(initialValue: model)
        self.onEdit = onEdit
        self.settingsModel = settingsModel
    }
```

Toolbar (replace the existing `.toolbar`):

```swift
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityIdentifier("workoutDetail.settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { onEdit(model.workoutID) }.accessibilityIdentifier("workoutDetail.edit")
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await model.load() } }) {
            WorkoutSettingsSheet(model: settingsModel(), title: model.title,
                                 onDeleted: { dismiss() })
                .environment(theme).presentationDetents([.large])
        }
```

Add `@Environment(\.dismiss) private var dismiss` to the view.

- [ ] **Step 3: Construct the settings model at the call site**

In `LibraryView.destination(.workoutDetail)`, pass both closures:

```swift
        case .workoutDetail(let id, let name):
            WorkoutDetailView(
                model: WorkoutDetailModel(
                    workoutID: id, title: name,
                    workoutRepo: repos.workouts,
                    onStart: onStartWorkout),
                onEdit: { editID in path.append(.workoutEditor(id: editID)) },
                settingsModel: { WorkoutSettingsModel(
                    workoutID: id, workoutRepo: repos.workouts,
                    scheduleRepo: repos.schedule, folderRepo: repos.folders) })
```

- [ ] **Step 4: Retarget the schedule tests**

- `WorkoutDetailModelTests` / `WorkoutDetailScheduleTests`: move the `toggleWeekday`/`scheduleOnDate`/`weekdays` assertions to `WorkoutSettingsModelTests` (already covered in Task 4). Delete those cases from the WorkoutDetail tests and drop the `scheduleRepo:` argument from the `WorkoutDetailModel(...)` constructions there. Keep load/start/rows tests.
- `WorkoutScheduleUITests`: the weekday chips moved into the settings sheet. Update the flow to open the gear first: after `workout.Push` tap, `app.buttons["workoutDetail.settings"].tap()`, then assert/toggle `settings.repeat-day-<n>` (was `repeat-day-<n>`), and `settings.scheduleDate` (was `workoutDetail.scheduleDate`).

- [ ] **Step 5: Generate, build, run the affected suites**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutDetailModelTests -only-testing:PulseTests/WorkoutDetailScheduleTests -only-testing:PulseUITests/WorkoutScheduleUITests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Features/Library/WorkoutDetailView.swift Pulse/Features/Library/WorkoutDetailModel.swift Pulse/Features/Library/LibraryView.swift PulseTests/Features/Library/WorkoutDetailModelTests.swift PulseTests/Features/Library/WorkoutDetailScheduleTests.swift PulseUITests/WorkoutScheduleUITests.swift
git commit -m "refactor(detail): move Schedule into the Settings sheet; add gear entry [BAK-63]"
```

---

## Task 7: Relocate Targets off the editor + wire the `⋯` overflow

**Files:**
- Modify: `Pulse/Features/Builders/BuilderUI.swift` (`BuilderScaffold`)
- Modify: `Pulse/Features/Builders/WorkoutBuilderView.swift`
- Modify: `Pulse/Features/Library/LibraryView.swift` (editor route may need the settings-model factory)
- Retarget: `PulseTests/Features/Builders/TargetsPickerAcceptanceTests.swift`, `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift`

- [ ] **Step 1: Make `BuilderScaffold`'s overflow tappable**

In `BuilderUI.swift`, give `BuilderScaffold` an `onOverflow: (() -> Void)?` (default nil = inert) and render the ellipsis as a Button when set:

```swift
struct BuilderScaffold<Content: View>: View {
    let eyebrow: String
    let primaryLabel: String
    let saving: Bool
    var onOverflow: (() -> Void)? = nil
    let onCancel: () -> Void
    let onPrimary: () -> Void
    @ViewBuilder var content: Content
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                StatLabel(eyebrow).accessibilityIdentifier("eyebrow-\(eyebrow)")
                Spacer()
                Button { onOverflow?() } label: {
                    Image(systemName: "ellipsis").foregroundStyle(theme.inkSoft)
                }
                .disabled(onOverflow == nil)
                .accessibilityIdentifier("builder-overflow")
            }
            .padding(.horizontal, theme.spacing[5]).padding(.vertical, theme.spacing[3])
            ScrollView { content.padding(.horizontal, theme.spacing[5]) }
            HStack(spacing: theme.spacing[2]) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
                    .accessibilityIdentifier("builder-cancel")
                Button(action: onPrimary) { Text(primaryLabel) }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
                    .disabled(saving).accessibilityIdentifier("builder-primary")
            }
            .padding(theme.spacing[5])
        }
        .background(theme.bg.ignoresSafeArea())
    }
}
```

- [ ] **Step 2: Drop `targetRow`; present the settings sheet from `⋯`**

In `WorkoutBuilderView.swift`:
- Remove the `targetRow` view + its call inside `loadedContent` (the `StatLabel("TARGETS")` block). The editor body becomes name + exercises + add.
- Add settings state + factory + the sheet:

```swift
struct WorkoutBuilderView: View {
    @State private var model: WorkoutBuilderModel
    private let settingsModel: () -> WorkoutSettingsModel
    @State private var showSettings = false
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric private var reorderRowHeight: CGFloat = 48

    init(model: WorkoutBuilderModel, settingsModel: @escaping () -> WorkoutSettingsModel) {
        _model = State(initialValue: model)
        self.settingsModel = settingsModel
    }
```

Pass `onOverflow` to the scaffold + present the sheet (re-hydrate the editor on dismiss so a settings change to targets is picked up before the next save):

```swift
        BuilderScaffold(
            eyebrow: "EDIT WORKOUT", primaryLabel: "Save workout →",
            saving: model.saveState == .saving,
            onOverflow: { showSettings = true },
            onCancel: { dismiss() },
            onPrimary: { Task { await model.save() } }
        ) { /* unchanged loadedContent switch */ }
        .task { await model.load() }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await model.load() } }) {
            WorkoutSettingsSheet(model: settingsModel(), title: model.name,
                                 onDeleted: { dismiss() })
                .environment(theme).presentationDetents([.large])
        }
        // ...existing .sheet(item:)/.sheet(isPresented: picker)/.onChange...
```

Update the `#Preview` to pass `settingsModel:` (a factory over the same mock store).

- [ ] **Step 3: Construct the editor's settings model at the route**

In `LibraryView.destination(.workoutEditor)`:

```swift
        case .workoutEditor(let id):
            WorkoutBuilderView(
                model: WorkoutBuilderModel(workoutID: id, catalog: repos.exercises, workouts: repos.workouts),
                settingsModel: { WorkoutSettingsModel(
                    workoutID: id, workoutRepo: repos.workouts,
                    scheduleRepo: repos.schedule, folderRepo: repos.folders) })
```

- [ ] **Step 4: Retarget the targets tests**

`WorkoutBuilderModel` keeps `targets` as hydrated state it still round-trips in `makeDraft` (so an editor save preserves targets). The model's `toggleTarget` stays (harmless) — but the **editor view** no longer shows the chips. So:
- `WorkoutBuilderModelTests`: keep `testToggleTargetAddsAndRemoves` + `testMakeDraftIncludesTargetsInCanonicalOrder` (they test the model, still valid). No change needed beyond what compiles.
- `TargetsPickerAcceptanceTests`: targets are now set via the settings sheet, but this test exercises `WorkoutBuilderModel` + `ExercisePickerLogic` directly (not the editor UI), so it still holds. Confirm it compiles against the model (no view dependency). If it constructed the editor view, repoint to the model.
- Update the two `#Preview`/test sites that construct `WorkoutBuilderView` to pass `settingsModel:`.

- [ ] **Step 5: Generate, build, run affected suites**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutBuilderModelTests -only-testing:PulseTests/TargetsPickerAcceptanceTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Features/Builders/BuilderUI.swift Pulse/Features/Builders/WorkoutBuilderView.swift Pulse/Features/Library/LibraryView.swift PulseTests/Features/Builders/WorkoutBuilderModelTests.swift PulseTests/Features/Builders/TargetsPickerAcceptanceTests.swift
git commit -m "refactor(editor): move Targets into the Settings sheet; wire the ⋯ overflow [BAK-63]"
```

---

## Task 8: Acceptance + UI coverage; full suite

**Files:**
- Create: `PulseTests/Features/Library/WorkoutSettingsAcceptanceTests.swift`
- Create: `PulseUITests/WorkoutSettingsUITests.swift`

- [ ] **Step 1: Acceptance test (full settings flow + rest resolution)**

`PulseTests/Features/Library/WorkoutSettingsAcceptanceTests.swift`:

```swift
import XCTest
@testable import Pulse

@MainActor
final class WorkoutSettingsAcceptanceTests: XCTestCase {
    func testEditAllSettingsPersistOnTheSameWorkout() async throws {
        let store = MockStore(seeded: false)
        let workouts = InMemoryWorkoutRepository(store: store)
        let folders = InMemoryFolderRepository(store: store)
        let folder = try await folders.createFolder(name: "Push days", color: .default, parentID: nil)
        var w = Workout(name: "Push", weekdays: [1], order: 0,
                        exercises: BuilderSampleData.defaultWorkoutItems.map {
                            WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                                            supersetGroup: $0.supersetGroup, sets: $0.sets) },
                        targets: [.chest])
        _ = try await workouts.saveWorkout(w)

        let m = WorkoutSettingsModel(workoutID: w.id, workoutRepo: workouts,
                                     scheduleRepo: InMemoryScheduleRepository(store: store),
                                     folderRepo: folders)
        await m.load()
        await m.setRestSeconds(120)
        await m.setNotes("belt on")
        await m.toggleWeekday(5)
        await m.toggleTarget(.back)
        await m.setFolder(folder.id)

        let saved = try await workouts.fetchWorkout(id: w.id)
        XCTAssertEqual(saved?.restSeconds, 120)
        XCTAssertEqual(saved?.notes, "belt on")
        XCTAssertEqual(saved?.weekdays, [1, 5])
        XCTAssertEqual(Set(saved?.targets ?? []), [.chest, .back])
        XCTAssertEqual(saved?.exercises.count, BuilderSampleData.defaultWorkoutItems.count)  // never dropped
        let inFolder = try await folders.contents(of: folder.id)
        XCTAssertTrue(inFolder.workouts.contains { $0.id == w.id })
    }

    func testActiveSessionUsesPerWorkoutRestOverride() {
        let session = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MockHistoryRepository(),
            sessionWriter: NoopSessionWriter())
        session.defaultRestSeconds = 90
        var w = ActiveWorkoutSample.workout
        w.restSeconds = 150
        session.startWorkout(w)
        XCTAssertEqual(session.restTotal, 150, accuracy: 0.001)
    }
}
```

> **Verify during build:** the exact zero-dependency `ActiveWorkoutModel` construction used in `ActiveWorkoutModelTests` (the `sessionWriter` mock name — e.g. `NoopSessionWriter` / a test double). Reuse that file's `makeModel()` helper instead if simpler.

- [ ] **Step 2: UI test (open from gear + ⋯; change rest; delete)**

`PulseUITests/WorkoutSettingsUITests.swift`:

```swift
import XCTest

final class WorkoutSettingsUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
        return app
    }

    func testOpenSettingsFromDetailGearAndChangeRest() {
        let app = launch()
        let push = app.buttons["workout.Push"]
        XCTAssertTrue(push.waitForExistence(timeout: 5))
        push.tap()
        app.buttons["workoutDetail.settings"].tap()
        let rest = app.staticTexts["settings.rest.value"]
        XCTAssertTrue(rest.waitForExistence(timeout: 5))
        XCTAssertEqual(rest.label, "Default")
        app.buttons["settings.rest.stepper.inc"].tap()      // Default → 105s (90+15)
        XCTAssertEqual(rest.label, "105s")
        app.buttons["settings.repeat-day-3"].tap()          // toggle Wednesday
    }

    func testOpenSettingsFromEditorOverflow() {
        let app = launch()
        let push = app.buttons["workout.Push"]
        XCTAssertTrue(push.waitForExistence(timeout: 5))
        push.tap()
        app.buttons["workoutDetail.edit"].tap()             // → editor
        XCTAssertTrue(app.buttons["builder-overflow"].waitForExistence(timeout: 5))
        app.buttons["builder-overflow"].tap()               // → settings sheet
        XCTAssertTrue(app.staticTexts["settings.rest.value"].waitForExistence(timeout: 5))
    }
}
```

> **Verify during build:** the first `settings.rest.stepper.inc` from "Default" sets `(nil ?? 90) + 15 = 105`. If the mock "Push" already has an override, adjust the expected label.

- [ ] **Step 3: Generate + run the FULL suite**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -30`
Expected: all `PulseTests` + `PulseUITests` pass.

- [ ] **Step 4: Commit**

```bash
git add PulseTests/Features/Library/WorkoutSettingsAcceptanceTests.swift PulseUITests/WorkoutSettingsUITests.swift project.yml
git commit -m "test(settings): acceptance + UI for the per-workout Settings sheet [BAK-63]"
```

---

## Self-review notes (spec coverage)

- **Consolidation hub** (Schedule, Targets, Rest, Notes, Folder, Delete) → Task 5 sheet sections; Schedule/Targets relocated in Tasks 6/7.
- **Move not mirror** → Task 6 strips Schedule from Detail; Task 7 strips Targets from the editor.
- **Rest wired end-to-end** → Task 1 (`restSeconds`), Task 2 (`restTotal = override ?? default`), Task 3 (AppShell syncs the global default).
- **Open from both** → Task 6 gear (Detail), Task 7 `⋯` (editor).
- **Never drop exercises** → `WorkoutSettingsModel` holds the full hydrated `Workout`; `persist` overrides one field (Task 4 + the acceptance assertion on `exercises.count`).
- **Edge cases:** editor re-hydrates on settings-sheet dismiss (Task 7 `onDismiss: load()`); rest clamped 15–600 (Task 4 `setRestSeconds`); notes commit on submit/Save (Task 5).
- **Out of scope:** Share/Layout/Pattern/per-exercise equipment/units — not in any task.
