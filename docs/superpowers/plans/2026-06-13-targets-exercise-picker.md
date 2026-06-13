# Targets + Exercise Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a workout real, persisted muscle **Targets** and rebuild the exercise picker (pre-filtered to targets, A–Z browse, functional search, inline variation choice) plus a per-row `⋯` menu (Replace / Change variation / Remove).

**Architecture:** Targets are the catalog's muscle groups, modelled as a `MuscleGroup` enum and stored on `Workout.targets` (new `workouts.targets text[]` column). The picker's filter/sort/letter-index logic is extracted into pure functions (`ExercisePickerLogic`) so it is unit-testable; the SwiftUI sheet consumes them. The decorative, never-persisted `WorkoutTag` is retired.

**Tech Stack:** SwiftUI, `@Observable` (Observation), Swift Concurrency, Supabase (PostgREST), XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-06-13-targets-exercise-picker-design.md` · **Linear:** [BAK-52](https://linear.app/bakinglions/issue/BAK-52/targets-exercise-picker-rebuild-dropset-inspired-sp1)

---

## Conventions (read once)

- **New files → regenerate the project.** After creating any `.swift` file, run `xcodegen generate` before building; the build can deceptively pass until first reference otherwise. The `.xcodeproj` is gitignored (never commit it) and `project.yml` uses path globs (`sources: [PulseTests]`, `- path: Pulse`), so new files under `Pulse/` or `PulseTests/` need no `project.yml` edit — just regenerate.
- **Test command.** Assume `SIM='platform=iOS Simulator,name=iPhone 16'` (adjust to an installed simulator). Run a single test with:
  `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/<Class>/<method>`
  Run the whole gated suite with: `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests`
- **CI gate.** Only `PulseTests` is the gate (the `PulseUITests` XCUITest target crashes on Xcode/iOS 26.5). All runnable coverage here lives in `PulseTests`.
- **Design system.** Theme tokens only (no hardcoded colors/spacing); fonts via the existing components (`PillChip`, `StatLabel`, `PressableButtonStyle`). On an `accent`-filled control, highlight text uses `onAccent`.
- **Accessibility ids** follow the builder conventions: `picker-filter-<X>`, `picker-row-<Name>`, `exercise-row-<Name>`, `remove-<Name>`, `eyebrow-<TEXT>`, lowercase hyphenated, index-suffixed `-<idx>`.
- **Migrations are files; apply via the Supabase dashboard SQL editor** (no local psql/docker in this project).

---

## Task 1: `MuscleGroup` model + `Workout.targets`

**Files:**
- Create: `Pulse/Core/Models/MuscleGroup.swift`
- Modify: `Pulse/Core/Models/WorkoutModels.swift` (add `targets` to `Workout`)
- Test: `PulseTests/Core/Models/MuscleGroupTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
// PulseTests/Core/Models/MuscleGroupTests.swift
import XCTest
@testable import Pulse

final class MuscleGroupTests: XCTestCase {
    func testRawValuesMatchCatalogStrings() {
        XCTAssertEqual(MuscleGroup.chest.rawValue, "Chest")
        XCTAssertEqual(MuscleGroup.allCases.count, 7)
    }

    func testFromCatalogKnownAndUnknown() {
        XCTAssertEqual(MuscleGroup.from(catalog: "Back"), .back)
        XCTAssertEqual(MuscleGroup.from(catalog: "Glutes"), .other) // unknown → other
    }

    func testWorkoutDefaultsToNoTargets() {
        let w = Workout(name: "x", weekday: nil, order: 0, exercises: [])
        XCTAssertEqual(w.targets, [])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/MuscleGroupTests`
Expected: FAIL — `MuscleGroup` / `from(catalog:)` / `Workout.targets` not found.

- [ ] **Step 3: Create the enum**

```swift
// Pulse/Core/Models/MuscleGroup.swift
import Foundation

/// A workout's muscle Target. Raw values match the catalog's `muscle_group`
/// strings (seeded in 0005/0006) so a workout's targets line up with
/// `Exercise.muscleGroup` for filtering.
enum MuscleGroup: String, Codable, CaseIterable, Identifiable, Equatable {
    case legs = "Legs"
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case other = "Other"

    var id: String { rawValue }

    /// Map a catalog `muscle_group` string to a case; anything outside the set
    /// (future catalog additions) falls back to `.other`.
    static func from(catalog raw: String) -> MuscleGroup {
        MuscleGroup(rawValue: raw) ?? .other
    }
}
```

- [ ] **Step 4: Add the field to `Workout`**

In `Pulse/Core/Models/WorkoutModels.swift`, add `targets` to `Workout` (defaulted so existing call sites compile):

```swift
struct Workout: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var weekday: Int?            // 1...7, nil = unscheduled
    var order: Int
    var exercises: [WorkoutExercise]
    var targets: [MuscleGroup] = []
}
```

- [ ] **Step 5: Regenerate, run the test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/MuscleGroupTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/Models/MuscleGroup.swift Pulse/Core/Models/WorkoutModels.swift PulseTests/Core/Models/MuscleGroupTests.swift
git commit -m "feat(models): add MuscleGroup + Workout.targets [BAK-52]"
```

---

## Task 2: Persist `targets` (migration + Supabase row mapping)

**Files:**
- Create: `supabase/migrations/0008_workout_targets.sql`
- Modify: `Pulse/Core/Data/Supabase/Rows/Rows.swift` (`WorkoutRow`)
- Modify: `Pulse/Core/Data/Supabase/Rows/WriteRows.swift` (`WorkoutWriteRow` + `WorkoutGraphWriter.insert`)
- Test: `PulseTests/Core/Data/WorkoutRowTargetsTests.swift`

- [ ] **Step 1: Write the failing test (read mapping)**

```swift
// PulseTests/Core/Data/WorkoutRowTargetsTests.swift
import XCTest
@testable import Pulse

final class WorkoutRowTargetsTests: XCTestCase {
    func testDecodeMapsTargetStringsToMuscleGroups() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Push","weekday":null,"order":0,
         "targets":["Chest","Triceps","Glutes"],"workoutExercises":[]}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(WorkoutRow.self, from: json)
        XCTAssertEqual(row.toModel().targets, [.chest, .triceps, .other])
    }

    func testDecodeMissingTargetsIsEmpty() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Push","weekday":null,"order":0,
         "workoutExercises":[]}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(WorkoutRow.self, from: json)
        XCTAssertEqual(row.toModel().targets, [])
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/WorkoutRowTargetsTests`
Expected: FAIL — `WorkoutRow` has no `targets`.

- [ ] **Step 3: Add the migration**

```sql
-- supabase/migrations/0008_workout_targets.sql
-- BAK-52: muscle Targets on a workout. Stored as a text[] of MuscleGroup raw
-- values ("Chest","Legs",…). Existing rows default to no targets.
alter table workouts add column targets text[] not null default '{}';
```

(Apply it via the Supabase dashboard SQL editor; there is no local psql/docker. `0007` is the latest applied migration; `0008` is the next free number.)

- [ ] **Step 4: Thread `targets` through the read row**

In `Pulse/Core/Data/Supabase/Rows/Rows.swift`, `WorkoutRow`:

```swift
struct WorkoutRow: Codable {
    let id: UUID
    let name: String
    let weekday: Int?
    let order: Int
    let targets: [String]?
    let workoutExercises: [WorkoutExerciseRow]?   // embed: workout_exercises(...)
    func toModel() -> Workout {
        Workout(id: id, name: name, weekday: weekday, order: order,
                exercises: (workoutExercises ?? [])
                    .sorted { $0.order < $1.order }
                    .compactMap { $0.toModel() },
                targets: (targets ?? []).map(MuscleGroup.from(catalog:)))
    }
}
```

(`SupabaseWorkoutRepository.graphSelect` uses `*`, so the new column is already selected — no change there.)

- [ ] **Step 5: Thread `targets` through the write row**

In `Pulse/Core/Data/Supabase/Rows/WriteRows.swift`, extend `WorkoutWriteRow`:

```swift
struct WorkoutWriteRow: Encodable {
    let id: UUID
    let programId: UUID
    let name: String
    let weekday: Int?
    let order: Int
    let targets: [String]

    enum CodingKeys: String, CodingKey { case id, programId, name, weekday, order, targets }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(programId, forKey: .programId)
        try c.encode(name, forKey: .name)
        try c.encode(weekday, forKey: .weekday)   // null when nil
        try c.encode(order, forKey: .order)
        try c.encode(targets, forKey: .targets)
    }
}
```

And in the same file, `WorkoutGraphWriter.insert`, set `targets` when building the row:

```swift
let workoutRows = workouts.map {
    WorkoutWriteRow(id: $0.id, programId: programID, name: $0.name,
                    weekday: $0.weekday, order: $0.order,
                    targets: $0.targets.map(\.rawValue))
}
```

- [ ] **Step 6: Regenerate, run the read-mapping test to verify it passes**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/WorkoutRowTargetsTests`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add supabase/migrations/0008_workout_targets.sql Pulse/Core/Data/Supabase/Rows/Rows.swift Pulse/Core/Data/Supabase/Rows/WriteRows.swift PulseTests/Core/Data/WorkoutRowTargetsTests.swift
git commit -m "feat(data): persist workout targets (0008 migration + row mapping) [BAK-52]"
```

---

## Task 3: Targets in the builder (model + view), retire `WorkoutTag`

`WorkoutBuilderView.tagRow` reads `model.tag`/`WorkoutTag`, so the model change and view change are done together to keep the target compiling.

**Files:**
- Modify: `Pulse/Features/Builders/WorkoutBuilderModel.swift`
- Modify: `Pulse/Features/Builders/WorkoutBuilderView.swift` (`tagRow` → `targetRow`)
- Modify: `Pulse/Features/Builders/BuilderModels.swift` (delete `WorkoutTag`)
- Test: `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift` (add cases)

- [ ] **Step 1: Write the failing tests**

Add to `WorkoutBuilderModelTests`:

```swift
func testToggleTargetAddsAndRemoves() {
    let model = makeModel()
    model.toggleTarget(.chest)
    model.toggleTarget(.triceps)
    XCTAssertEqual(model.targets, [.chest, .triceps])
    model.toggleTarget(.chest)
    XCTAssertEqual(model.targets, [.triceps])
}

func testMakeDraftIncludesTargetsInCanonicalOrder() {
    let model = makeModel()
    model.toggleTarget(.triceps)
    model.toggleTarget(.chest)            // toggled out of order
    XCTAssertEqual(model.makeDraft().targets, [.chest, .triceps]) // canonical allCases order
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/WorkoutBuilderModelTests/testToggleTargetAddsAndRemoves`
Expected: FAIL — `toggleTarget` / `targets` / `makeDraft` not found.

- [ ] **Step 3: Update the model**

In `WorkoutBuilderModel`, replace the `tag` property and refactor `save()` to build via `makeDraft()`:

```swift
// was: var tag: WorkoutTag = .push
var targets: Set<MuscleGroup> = []

/// Toggle a muscle Target on/off.
func toggleTarget(_ m: MuscleGroup) {
    if targets.contains(m) { targets.remove(m) } else { targets.insert(m) }
}

/// The draft persisted by `save()`. Targets are emitted in canonical
/// `MuscleGroup.allCases` order for deterministic storage/tests.
func makeDraft() -> Workout {
    let workoutExercises = items.map {
        WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                        supersetGroup: $0.supersetGroup, sets: $0.sets)
    }
    return Workout(name: name, weekday: nil, order: 0,
                   exercises: workoutExercises,
                   targets: MuscleGroup.allCases.filter { targets.contains($0) })
}

func save() async {
    saveState = .saving
    do {
        _ = try await workoutRepo.saveWorkout(makeDraft())
        saveState = .saved
    } catch {
        saveState = .error("Couldn't save workout — \(error.localizedDescription)")
    }
}
```

- [ ] **Step 4: Update the view (`tagRow` → `targetRow`)**

In `WorkoutBuilderView`, rename the call site (`tagRow` → `targetRow` in `body`) and replace the implementation:

```swift
private var targetRow: some View {
    VStack(alignment: .leading, spacing: theme.spacing[2]) {
        StatLabel("TARGETS").accessibilityIdentifier("eyebrow-TARGETS")
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing[1]) {
                ForEach(MuscleGroup.allCases) { m in
                    PillChip(label: m.rawValue, selected: model.targets.contains(m),
                             fill: theme.accent, onFill: theme.onAccent) {
                        model.toggleTarget(m)
                    }
                    .accessibilityIdentifier("target-\(m.rawValue)")
                }
            }
        }
    }
}
```

- [ ] **Step 5: Delete `WorkoutTag`**

In `Pulse/Features/Builders/BuilderModels.swift`, delete the `WorkoutTag` enum (no remaining references after Steps 3–4).

- [ ] **Step 6: Fix any existing test referencing `tag`**

Search and update: `grep -rn "\.tag\b\|WorkoutTag" PulseTests` — replace any `model.tag = …` assertions with `toggleTarget`/`targets`. (If none, skip.)

- [ ] **Step 7: Run the target tests + the existing builder suite**

Run: `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/WorkoutBuilderModelTests`
Expected: PASS (new target tests + existing builder tests).

- [ ] **Step 8: Commit**

```bash
git add Pulse/Features/Builders/WorkoutBuilderModel.swift Pulse/Features/Builders/WorkoutBuilderView.swift Pulse/Features/Builders/BuilderModels.swift PulseTests/Features/Builders/WorkoutBuilderModelTests.swift
git commit -m "feat(builder): multi-select muscle Targets; retire WorkoutTag [BAK-52]"
```

---

## Task 4: `PickedExercise` + `replaceExercise` (additive)

**Files:**
- Modify: `Pulse/Features/Builders/BuilderModels.swift` (add `PickedExercise`)
- Modify: `Pulse/Features/Builders/WorkoutBuilderModel.swift` (add `replaceExercise`)
- Test: `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
func testReplaceExerciseSwapsExerciseAndVariationButKeepsSets() {
    let model = makeModel()                     // seeded: defaultWorkoutItems
    model.catalog = WorkoutBuilderModel.group(SampleData.exercises)  // resolve replacement
    let itemID = model.items[0].id
    let originalSets = model.items[0].sets
    let originalGroup = model.items[0].supersetGroup
    // pick a different catalog exercise via its real id from the in-memory catalog
    let replacement = SampleData.exercises.first { $0.id != model.items[0].exercise.id }!

    model.replaceExercise(itemID: itemID,
                          with: PickedExercise(id: replacement.id,
                                               variationID: replacement.defaultVariationID))

    XCTAssertEqual(model.items[0].exercise.id, replacement.id)
    XCTAssertEqual(model.items[0].variationID, replacement.defaultVariationID)
    XCTAssertEqual(model.items[0].sets, originalSets)             // sets preserved
    XCTAssertEqual(model.items[0].supersetGroup, originalGroup)   // grouping preserved
}
```

(The replacement `Exercise` is resolved from `model.catalog`, seeded in the test above.)

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/WorkoutBuilderModelTests/testReplaceExerciseSwapsExerciseAndVariationButKeepsSets`
Expected: FAIL — `PickedExercise` / `replaceExercise` not found.

- [ ] **Step 3: Add `PickedExercise` and `replaceExercise`**

In `Pulse/Features/Builders/BuilderModels.swift`:

```swift
/// One exercise chosen in the picker, with the variation selected inline.
struct PickedExercise: Identifiable, Equatable {
    let id: Exercise.ID
    let variationID: Variation.ID?
}
```

In `WorkoutBuilderModel` (resolve the replacement from the loaded catalog):

```swift
/// All catalog exercises by id (loaded catalog), for resolving picks.
private var catalogByID: [Exercise.ID: Exercise] {
    Dictionary(uniqueKeysWithValues: catalog.flatMap { $0.exercises }.map { ($0.id, $0) })
}

/// Swap the exercise at `itemID` for `picked`, keeping its sets and superset
/// grouping. Variation resets to the picked variation (or the new exercise's
/// default).
func replaceExercise(itemID: BuilderExercise.ID, with picked: PickedExercise) {
    guard let i = items.firstIndex(where: { $0.id == itemID }),
          let exercise = catalogByID[picked.id] else { return }
    items[i].exercise = exercise
    items[i].variationID = picked.variationID ?? exercise.defaultVariationID
    // sets and supersetGroup intentionally untouched
}
```

(`makeModel()` must have a populated `catalog`. If the fixture builds the model without loading the catalog, update it to `await model.loadCatalog()` once, or seed `model.catalog = WorkoutBuilderModel.group(SampleData.exercises)` in the fixture.)

- [ ] **Step 4: Run it to verify it passes**

Run: `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/WorkoutBuilderModelTests/testReplaceExerciseSwapsExerciseAndVariationButKeepsSets`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Builders/BuilderModels.swift Pulse/Features/Builders/WorkoutBuilderModel.swift PulseTests/Features/Builders/WorkoutBuilderModelTests.swift
git commit -m "feat(builder): add replaceExercise (keeps sets) + PickedExercise [BAK-52]"
```

---

## Task 5: Picker logic — pure, testable functions

**Files:**
- Create: `Pulse/Features/Builders/ExercisePickerLogic.swift`
- Test: `PulseTests/Features/Builders/ExercisePickerLogicTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// PulseTests/Features/Builders/ExercisePickerLogicTests.swift
import XCTest
@testable import Pulse

final class ExercisePickerLogicTests: XCTestCase {
    private var catalog: [BuilderCatalogGroup] { WorkoutBuilderModel.group(SampleData.exercises) }

    func testModeIsSectionedWithActiveMusclesAndNoSearch() {
        XCTAssertEqual(ExercisePickerLogic.mode(activeMuscles: ["Legs"], search: ""), .sectioned)
    }
    func testModeIsAlphabeticalWhenAllOrSearching() {
        XCTAssertEqual(ExercisePickerLogic.mode(activeMuscles: [], search: ""), .alphabetical)
        XCTAssertEqual(ExercisePickerLogic.mode(activeMuscles: ["Legs"], search: "row"), .alphabetical)
    }
    func testSectionedKeepsOnlyActiveMuscles() {
        let groups = ExercisePickerLogic.sectioned(catalog, activeMuscles: ["Chest"])
        XCTAssertEqual(groups.map(\.muscle), ["Chest"])
    }
    func testAlphabeticalSortsByNameAndFiltersBySearch() {
        let list = ExercisePickerLogic.alphabetical(catalog, activeMuscles: [], search: "row")
        XCTAssertFalse(list.isEmpty)
        XCTAssertEqual(list.map(\.name), list.map(\.name).sorted())
        XCTAssertTrue(list.allSatisfy { $0.name.localizedCaseInsensitiveContains("row") })
    }
    func testLetterIndexIsDistinctUppercaseFirstLetters() {
        let list = ExercisePickerLogic.alphabetical(catalog, activeMuscles: [], search: "")
        let idx = ExercisePickerLogic.letterIndex(list)
        XCTAssertEqual(idx, idx.sorted())
        XCTAssertEqual(Set(idx).count, idx.count)
        XCTAssertTrue(idx.allSatisfy { $0.count == 1 && $0 == $0.uppercased() })
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/ExercisePickerLogicTests`
Expected: FAIL — `ExercisePickerLogic` not found.

- [ ] **Step 3: Implement the logic**

```swift
// Pulse/Features/Builders/ExercisePickerLogic.swift
import Foundation

/// Pure filtering/sorting helpers for the exercise picker, kept out of the View
/// so they can be unit-tested. `activeMuscles` are `muscle_group` strings; an
/// empty set means "All".
enum ExercisePickerLogic {
    enum Mode: Equatable { case sectioned, alphabetical }

    /// Sectioned (muscle groups) when ≥1 muscle is active and not searching;
    /// otherwise a flat alphabetical list (browsing All or searching).
    static func mode(activeMuscles: Set<String>, search: String) -> Mode {
        let searching = !search.trimmingCharacters(in: .whitespaces).isEmpty
        return (!activeMuscles.isEmpty && !searching) ? .sectioned : .alphabetical
    }

    /// Catalog groups limited to the active muscles, preserving catalog order.
    static func sectioned(_ catalog: [BuilderCatalogGroup], activeMuscles: Set<String>) -> [BuilderCatalogGroup] {
        activeMuscles.isEmpty ? catalog : catalog.filter { activeMuscles.contains($0.muscle) }
    }

    /// Flat list sorted by name, filtered by active muscles (if any) and search.
    static func alphabetical(_ catalog: [BuilderCatalogGroup], activeMuscles: Set<String>, search: String) -> [Exercise] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return catalog
            .filter { activeMuscles.isEmpty || activeMuscles.contains($0.muscle) }
            .flatMap { $0.exercises }
            .filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Distinct uppercase first letters present in `list`, ascending — drives the
    /// A–Z scrubber.
    static func letterIndex(_ list: [Exercise]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for ex in list.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let l = String(ex.name.prefix(1)).uppercased()
            if !l.isEmpty, !seen.contains(l) { seen.insert(l); out.append(l) }
        }
        return out
    }
}
```

- [ ] **Step 4: Regenerate, run the tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/ExercisePickerLogicTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Builders/ExercisePickerLogic.swift PulseTests/Features/Builders/ExercisePickerLogicTests.swift
git commit -m "feat(builder): pure exercise-picker filter/sort/index logic [BAK-52]"
```

---

## Task 6: Picker view rebuild + `addExercises([PickedExercise])` + wiring

Rebuild `ExercisePickerSheet` to consume Task 5's logic: pre-set muscle chips, an All chip, functional search, sectioned↔alphabetical modes with an A–Z scrubber, and inline variation on selected rows. Switch the confirm callback + `addExercises` to carry the chosen variation, and update the builder's presentation.

**Files:**
- Modify: `Pulse/Features/Builders/ExercisePickerSheet.swift`
- Modify: `Pulse/Features/Builders/WorkoutBuilderModel.swift` (`addExercises`)
- Modify: `Pulse/Features/Builders/WorkoutBuilderView.swift` (presentation + onConfirm)
- Test: `PulseTests/Features/Builders/WorkoutBuilderModelTests.swift`

- [ ] **Step 1: Write the failing test (model side)**

```swift
func testAddExercisesAppliesChosenVariation() {
    let model = makeModel(); model.catalog = WorkoutBuilderModel.group(SampleData.exercises)
    let ex = SampleData.exercises.first { $0.variations.count > 1 }!
    let chosen = ex.variations[1].id
    model.addExercises([PickedExercise(id: ex.id, variationID: chosen)])
    let added = model.items.first { $0.exercise.id == ex.id }
    XCTAssertEqual(added?.variationID, chosen)
}

func testAddExercisesFallsBackToDefaultVariation() {
    let model = makeModel(); model.catalog = WorkoutBuilderModel.group(SampleData.exercises)
    let ex = SampleData.exercises.first { $0.defaultVariationID != nil }!
    model.addExercises([PickedExercise(id: ex.id, variationID: nil)])
    let added = model.items.first { $0.exercise.id == ex.id }
    XCTAssertEqual(added?.variationID, ex.defaultVariationID)
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/WorkoutBuilderModelTests/testAddExercisesAppliesChosenVariation`
Expected: FAIL — `addExercises` still takes `[Exercise.ID]`.

- [ ] **Step 3: Change `addExercises` to consume `PickedExercise`**

```swift
/// Append picked exercises (deduped against existing + within the batch), each
/// seeded with its chosen variation (fallback: the exercise default) and one
/// working set.
func addExercises(_ picked: [PickedExercise]) {
    var present = addedExerciseIDs
    let lookup = catalogByID
    for p in picked where !present.contains(p.id) {
        guard let exercise = lookup[p.id] else { continue }
        present.insert(p.id)
        items.append(BuilderExercise(
            exercise: exercise,
            variationID: p.variationID ?? exercise.defaultVariationID,
            supersetGroup: nil,
            sets: [SetSpec(reps: 10, rir: 2, type: .working)]))
    }
}
```

- [ ] **Step 4: Rebuild `ExercisePickerSheet`**

Replace the file with the hybrid picker. New inputs: `initialMuscles` (the workout's targets as raw strings) and `mode` (`.add` multi-select, or `.replace` single-select). Confirm returns `[PickedExercise]`.

```swift
import SwiftUI

struct ExercisePickerSheet: View {
    enum PickMode { case add, replace }

    let catalog: [BuilderCatalogGroup]
    let loading: Bool
    let errorText: String?
    let alreadyAdded: Set<Exercise.ID>
    var initialMuscles: [String] = []
    var mode: PickMode = .add
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onConfirm: ([PickedExercise]) -> Void

    @State private var selected: [Exercise.ID] = []                 // ordered by tap
    @State private var chosenVariation: [Exercise.ID: Variation.ID] = [:]
    @State private var active: Set<String> = []                     // active muscle filters; empty = All
    @State private var search: String = ""
    @State private var didSeed = false
    @Environment(Theme.self) private var theme

    private var catalogMuscles: [String] { catalog.map { $0.muscle } }
    private var pickerMode: ExercisePickerLogic.Mode {
        ExercisePickerLogic.mode(activeMuscles: active, search: search)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            if mode == .add { footer }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet, topTrailingRadius: theme.radiusSheet)
                .stroke(theme.ink, lineWidth: 2).ignoresSafeArea(edges: .bottom)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet, topTrailingRadius: theme.radiusSheet))
        .onAppear {
            guard !didSeed else { return }
            active = Set(initialMuscles).intersection(Set(catalogMuscles))
            didSeed = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Capsule().fill(theme.inkFaint).frame(width: 42, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 12)
            StatLabel(mode == .replace ? "REPLACE EXERCISE" : "ADD EXERCISE")
                .accessibilityIdentifier("eyebrow-ADD EXERCISE")
            Text(mode == .replace ? "Pick a replacement." : "Pick exercises.")
                .pulseStyle(.h1).foregroundStyle(theme.ink)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.inkFaint)
                TextField("Search", text: $search)
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("exercise-search")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(theme.inkFaint)
                }
            }
            .padding(theme.spacing[3])
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.inkFaint, lineWidth: 2))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing[1]) {
                    PillChip(label: "All", selected: active.isEmpty,
                             fill: theme.accent, onFill: theme.onAccent) { active.removeAll() }
                        .accessibilityIdentifier("picker-filter-All")
                    ForEach(catalogMuscles, id: \.self) { m in
                        PillChip(label: m, selected: active.contains(m),
                                 fill: theme.accent, onFill: theme.onAccent) { toggleMuscle(m) }
                            .accessibilityIdentifier("picker-filter-\(m)")
                    }
                }
            }
        }
        .padding(.horizontal, theme.spacing[5]).padding(.bottom, theme.spacing[3])
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("picker-loading")
        } else if let errorText {
            VStack(spacing: theme.spacing[3]) {
                Text(errorText).foregroundStyle(theme.inkSoft)
                Button("Retry", action: onRetry).accessibilityIdentifier("picker-retry")
            }.frame(maxWidth: .infinity, minHeight: 120)
        } else if pickerMode == .sectioned {
            sectionedList
        } else {
            alphabeticalList
        }
    }

    private var sectionedList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing[3]) {
                ForEach(ExercisePickerLogic.sectioned(catalog, activeMuscles: active)) { group in
                    StatLabel(group.muscle)
                    ForEach(group.exercises) { ex in row(ex) }
                }
            }
            .padding(.horizontal, theme.spacing[5]).padding(.bottom, theme.spacing[3])
        }
        .scrollIndicators(.hidden)
    }

    private var alphabeticalList: some View {
        let list = ExercisePickerLogic.alphabetical(catalog, activeMuscles: active, search: search)
        let letters = ExercisePickerLogic.letterIndex(list)
        return ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: theme.spacing[2]) {
                        ForEach(list) { ex in row(ex).id(ex.id) }
                    }
                    .padding(.horizontal, theme.spacing[5]).padding(.bottom, theme.spacing[3])
                }
                .scrollIndicators(.hidden)
                scrubber(letters: letters, list: list, proxy: proxy)
            }
        }
    }

    private func scrubber(letters: [String], list: [Exercise], proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 1) {
            ForEach(letters, id: \.self) { l in
                Button {
                    if let target = list.first(where: { String($0.name.prefix(1)).uppercased() == l })?.id {
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                } label: {
                    Text(l).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.inkSoft)
                }
                .accessibilityIdentifier("scrubber-\(l)")
            }
        }
        .padding(.trailing, 4)
    }

    private var footer: some View {
        HStack(spacing: theme.spacing[2]) {
            Button("Cancel", action: onCancel)
                .buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
                .accessibilityIdentifier("picker-cancel")
            Button { onConfirm(picks()) } label: {
                Text(selected.isEmpty ? "Select exercises" : "Add \(selected.count) selected")
            }
            .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
            .disabled(selected.isEmpty)
            .accessibilityIdentifier("picker-confirm")
        }
        .padding(theme.spacing[5])
    }

    private func picks() -> [PickedExercise] {
        selected.map { PickedExercise(id: $0, variationID: chosenVariation[$0]) }
    }

    @ViewBuilder private func row(_ ex: Exercise) -> some View {
        let added = alreadyAdded.contains(ex.id)
        let isSel = selected.contains(ex.id)
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Button {
                guard !added else { return }
                if mode == .replace {
                    onConfirm([PickedExercise(id: ex.id, variationID: ex.defaultVariationID)]); return
                }
                if let i = selected.firstIndex(of: ex.id) { selected.remove(at: i); chosenVariation[ex.id] = nil }
                else { selected.append(ex.id); chosenVariation[ex.id] = ex.defaultVariationID }
            } label: {
                HStack {
                    Text(ex.name).foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Image(systemName: (added || isSel) ? "checkmark" : "plus")
                        .foregroundStyle(added ? theme.inkSoft : theme.accent)
                }
                .padding(theme.spacing[3])
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(isSel ? theme.accent : theme.inkFaint, lineWidth: isSel ? 2 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(added).opacity(added ? 0.4 : 1)
            .accessibilityIdentifier("picker-row-\(ex.name)")

            if mode == .add, isSel, ex.variations.count > 1 {
                variationPicker(ex)
            }
        }
    }

    private func variationPicker(_ ex: Exercise) -> some View {
        let current = ex.variations.first { $0.id == chosenVariation[ex.id] }
        return Menu {
            ForEach(ex.variations) { v in
                Button {
                    chosenVariation[ex.id] = v.id
                } label: {
                    if v.id == chosenVariation[ex.id] { Label(v.name, systemImage: "checkmark") }
                    else { Text(v.name) }
                }
            }
        } label: {
            HStack(spacing: theme.spacing[2]) {
                StatLabel("VARIATION")
                Text(current?.name ?? "Default").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.ink)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.inkSoft)
            }
            .padding(.horizontal, theme.spacing[3])
        }
        .accessibilityIdentifier("picker-variation-\(ex.name)")
    }

    private func toggleMuscle(_ m: String) {
        if active.contains(m) { active.remove(m) } else { active.insert(m) }
    }
}
```

- [ ] **Step 5: Update the builder's picker presentation**

In `WorkoutBuilderView`, the `.sheet(isPresented: $model.pickerPresented)` block — pass the workout's targets as `initialMuscles` and the new confirm type:

```swift
ExercisePickerSheet(
    catalog: model.catalog, loading: model.catalogLoading, errorText: model.catalogError,
    alreadyAdded: model.addedExerciseIDs,
    initialMuscles: model.targets.map(\.rawValue),
    onRetry: { Task { await model.loadCatalog() } },
    onCancel: { model.pickerPresented = false },
    onConfirm: { picked in model.addExercises(picked); model.isReordering = false; model.pickerPresented = false })
```

- [ ] **Step 6: Update the `ExercisePickerSheet` preview + any test using the old `onConfirm`/`addExercises`**

Fix the `#Preview` at the bottom of `ExercisePickerSheet.swift` (`onConfirm: { _ in }` still type-checks). Then `grep -rn "addExercises(\[" PulseTests` and update any call to pass `[PickedExercise(...)]`.

- [ ] **Step 7: Regenerate, run logic + model + builder suites**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/WorkoutBuilderModelTests -only-testing:PulseTests/ExercisePickerLogicTests`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Pulse/Features/Builders/ExercisePickerSheet.swift Pulse/Features/Builders/WorkoutBuilderModel.swift Pulse/Features/Builders/WorkoutBuilderView.swift PulseTests/Features/Builders/WorkoutBuilderModelTests.swift
git commit -m "feat(builder): hybrid exercise picker w/ targets, A-Z, inline variation [BAK-52]"
```

---

## Task 7: Builder row `⋯` menu (Replace / Change variation / Remove)

Add a tappable `⋯` menu to each builder exercise row; wire Replace to the picker in `.replace` mode.

**Files:**
- Modify: `Pulse/Features/Builders/WorkoutBuilderView.swift`
- Modify: `Pulse/Features/Builders/WorkoutBuilderModel.swift` (replace-target state)

- [ ] **Step 1: Add replace-target state to the model**

```swift
/// The builder row currently being replaced (drives a single-select picker).
var replacingItemID: BuilderExercise.ID? = nil
```

- [ ] **Step 2: Add the `⋯` menu to `exerciseRow`**

In `WorkoutBuilderView.exerciseRow`, replace the standalone remove (`xmark`) button with a `Menu`. Keep the superset `link` button as-is:

```swift
Menu {
    Button { startReplace(item.id) } label: { Label("Replace exercise", systemImage: "arrow.left.arrow.right") }
    if item.exercise.variations.count > 1 {
        Menu("Change variation") {
            ForEach(item.exercise.variations) { v in
                Button {
                    model.updateVariation(itemID: item.id, variationID: v.id)
                } label: {
                    if v.id == item.variationID { Label(v.name, systemImage: "checkmark") } else { Text(v.name) }
                }
            }
        }
    }
    Button(role: .destructive) { model.removeItem(id: item.id) } label: { Label("Remove", systemImage: "trash") }
} label: {
    Image(systemName: "ellipsis").foregroundStyle(theme.inkSoft)
}
.accessibilityIdentifier("row-menu-\(item.exercise.name)")
```

Add the helper + a replace sheet on the view:

```swift
private func startReplace(_ id: BuilderExercise.ID) {
    model.replacingItemID = id
    model.pickerPresented = true
}
```

- [ ] **Step 3: Make the picker honour replace mode**

Update the picker `.sheet` in `WorkoutBuilderView` to pass `mode` and route a replace confirm:

```swift
ExercisePickerSheet(
    catalog: model.catalog, loading: model.catalogLoading, errorText: model.catalogError,
    alreadyAdded: model.replacingItemID == nil ? model.addedExerciseIDs : [],
    initialMuscles: model.targets.map(\.rawValue),
    mode: model.replacingItemID == nil ? .add : .replace,
    onRetry: { Task { await model.loadCatalog() } },
    onCancel: { model.replacingItemID = nil; model.pickerPresented = false },
    onConfirm: { picked in
        if let id = model.replacingItemID, let first = picked.first {
            model.replaceExercise(itemID: id, with: first)
            model.replacingItemID = nil
        } else {
            model.addExercises(picked); model.isReordering = false
        }
        model.pickerPresented = false
    })
```

- [ ] **Step 4: Build (no new logic to unit-test beyond Task 4's `replaceExercise`)**

Run: `xcodebuild build -scheme Pulse -destination "$SIM"`
Expected: BUILD SUCCEEDED. (Replace behaviour is covered by `testReplaceExerciseSwapsExerciseAndVariationButKeepsSets`.)

- [ ] **Step 5: Run the builder suite**

Run: `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/WorkoutBuilderModelTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Features/Builders/WorkoutBuilderView.swift Pulse/Features/Builders/WorkoutBuilderModel.swift
git commit -m "feat(builder): per-row ellipsis menu (replace/variation/remove) [BAK-52]"
```

---

## Task 8: End-to-end acceptance coverage + full-suite green

Model-level acceptance tests (the runnable form, since the XCUITest target can't run on the current runner) tying the slice together, then a full gated run.

**Files:**
- Test: `PulseTests/Features/Builders/TargetsPickerAcceptanceTests.swift`

- [ ] **Step 1: Write the acceptance tests**

```swift
// PulseTests/Features/Builders/TargetsPickerAcceptanceTests.swift
import XCTest
@testable import Pulse

@MainActor
final class TargetsPickerAcceptanceTests: XCTestCase {
    private func model() -> WorkoutBuilderModel {
        let store = MockStore()
        let m = WorkoutBuilderModel(catalog: InMemoryExerciseRepository(store: store),
                                    workouts: InMemoryWorkoutRepository(store: store))
        m.catalog = WorkoutBuilderModel.group(SampleData.exercises)
        return m
    }

    func testTargetsDriveThePickerFilterThenPersist() async {
        let m = model()
        m.toggleTarget(.chest); m.toggleTarget(.triceps)

        // The picker opens pre-filtered to the workout's targets.
        let active = Set(m.targets.map(\.rawValue))
        XCTAssertEqual(ExercisePickerLogic.mode(activeMuscles: active, search: ""), .sectioned)
        let sections = ExercisePickerLogic.sectioned(WorkoutBuilderModel.group(SampleData.exercises),
                                                     activeMuscles: active).map(\.muscle)
        XCTAssertEqual(Set(sections), ["Chest", "Triceps"])

        // Add an exercise with a chosen variation, then the draft persists targets.
        let ex = SampleData.exercises.first { $0.muscleGroup == "Chest" && $0.variations.count > 1 }!
        m.addExercises([PickedExercise(id: ex.id, variationID: ex.variations[1].id)])
        XCTAssertEqual(m.items.first?.variationID, ex.variations[1].id)
        XCTAssertEqual(m.makeDraft().targets, [.chest, .triceps])
    }

    func testSearchSwitchesToAlphabeticalAcrossMuscles() {
        let catalog = WorkoutBuilderModel.group(SampleData.exercises)
        XCTAssertEqual(ExercisePickerLogic.mode(activeMuscles: ["Chest"], search: "row"), .alphabetical)
        let rows = ExercisePickerLogic.alphabetical(catalog, activeMuscles: [], search: "row")
        XCTAssertEqual(rows.map(\.name), rows.map(\.name).sorted())
    }
}
```

- [ ] **Step 2: Regenerate, run them to verify they pass**

Run: `xcodegen generate && xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests/TargetsPickerAcceptanceTests`
Expected: PASS (all units already implemented). If a `SampleData.exercises` has no multi-variation Chest exercise, pick the muscle that does (Chest "Incline Chest Press" has 5 variations in the seed — but `SampleData.exercises` is the mock catalog; confirm a multi-variation chest entry exists, else adjust the filter).

- [ ] **Step 3: Run the full gated suite**

Run: `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests`
Expected: PASS (no regressions across the suite).

- [ ] **Step 4: Commit**

```bash
git add PulseTests/Features/Builders/TargetsPickerAcceptanceTests.swift
git commit -m "test(builder): targets + picker acceptance coverage [BAK-52]"
```

---

## Final verification (before PR)

- [ ] `xcodegen generate` (ensure all new files are in the project).
- [ ] `xcodebuild test -scheme Pulse -destination "$SIM" -only-testing:PulseTests` is green.
- [ ] Manually apply `0008_workout_targets.sql` in the Supabase dashboard (live path).
- [ ] Smoke the builder in the simulator: targets toggle; picker opens pre-filtered; All → alphabetical + scrubber; search filters; inline variation on a selected multi-variation exercise; `⋯` → Replace (sets preserved) / Change variation / Remove.
- [ ] `code-reviewer` agent + `/security-review`; move BAK-52 to In Progress with the PR link, then Done on merge.

## Notes on scope / non-goals (from the spec)

Tracking unit, inline Sets editing in the picker, per-workout scheduling, the guided wizard, the settings sheet, auto-suggest targets, coarse movement buckets, and templates/share are all **out of scope** for this plan.
