# Builders (Workout / Routine / Folder) (BAK-18) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the three creation surfaces a lifter reaches from the Library Create chooser (BAK-10): a **Workout Builder** (name, tag, exercise list with supersets and per-set editing), a **Routine Builder** (name, program length, weekly split), and a **Folder** creation screen (name + color). Deliver the three supporting sheets the builders host — the **Set Editor**, **Exercise Picker**, and **Workout Picker**. UI-first: every screen binds to repository protocols backed by in-memory mocks with sample data; no real Supabase wiring (that lands in BAK-6 behind the same protocol surface).

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. Each builder is a `View` + an `@Observable` model in `Pulse/Features/Builders/`. Display/draft structs (`BuilderExercise`, `BuilderDay`, `WorkoutTag`, `FolderColor`, `SaveState`) are co-located in `Pulse/Features/Builders/BuilderModels.swift`. Models reach storage only through repository protocols in `Pulse/Core/Data` (`WorkoutRepository`, `RoutineRepository`, `FolderRepository`, `ExerciseCatalogRepository`); in-memory mocks in `Pulse/Core/Data/Mocks` seed the catalog, saved-workout list, and capture writes. All color/spacing/radii/type come from `Theme` tokens. The builders are presented as `NavigationStack` destinations; sheets use native `.sheet` + `.presentationDetents` with styled content.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency (`async`/`await`), XCTest + XCUITest, XcodeGen. Test destination: `platform=iOS Simulator,name=iPhone 17`.

**Product decisions applied (authoritative — `docs/superpowers/specs/2026-05-31-product-decisions.md`):**
- **kg only (v1):** the Set Editor edits reps / RIR / type only; no weight field here (weight is captured live during a session). No units toggle.
- **`⋯` overflow menus & decorative search fields render as inert placeholders** (no actions wired) — applies to every builder top-bar `⋯` and the Exercise Picker search field.
- **`default_variation_id` exists on `Exercise`** (already in `Pulse/Core/Models/WorkoutModels.swift` as `defaultVariationID`). The builder seeds each added `WorkoutExercise` with `variationID = exercise.defaultVariationID`; no in-builder variation switcher (spec out-of-scope).
- **`SessionSet` has `exerciseID` + `order`** — not relevant here (builders edit `SetSpec`/`WorkoutExercise`, which stay array-ordered).
- Resolving the spec's open questions with the product-decisions defaults: **Save** assembles a draft and calls the mock repository write, then pops (Open Q1 — persistence target is the mock; real folder/program placement is BAK-6). **Drag-to-reorder is deferred** (Open Q2 — grip handle is decorative). **Create-only** (Open Q3 — no edit-in-place). **PUSH/PULL/LEGS is the complete single-select tag set; `+ TAG` is inert** (Open Q5). **Folder swatches become named brand-color tokens added to `Theme`, fixed across Coastal/Mint** (Open Q6 / edge case — satisfies "never hardcode colors"). **`+ Add set` clones the last set as `working`** (Open Q10). Empty/degenerate saves are **permitted** (Open Q9 — no blocking in v1).

**Prerequisites (must be built first):**
- **Design System (BAK-7)** — `Theme` tokens, fonts (Hanken Grotesk / Oswald / Geist Mono), and the chip / row / badge / `IconBtn` / `Sheet` / `FolderIcon` / button primitives. `Theme`/`Palette` already exist in `Pulse/Core/DesignSystem/`. This plan adds the six fixed `FolderColor` brand tokens to `Theme`.
- **Data layer (BAK-6)** — repository protocols + in-memory mocks and sample data. BAK-6 is **not yet merged**, so this plan defines the `WorkoutRepository` / `RoutineRepository` / `FolderRepository` / `ExerciseCatalogRepository` protocols, the `WorkoutSummary` / `MuscleGroupCatalog` / `CatalogExercise` display types, and the mocks itself, behind the same protocol names BAK-6 will adopt. When BAK-6 lands, these are reconciled (same protocol surface).
- Reached from the **Library Create chooser (BAK-10)**; this plan wires temporary entry points (NavigationStack destinations) so the builders are reachable and UI-testable without BAK-10.

No dependency on the active-flow engine or Live Activity (BAK-14).

---

## Prerequisites (verify before starting)

- [ ] **Step 0a: Confirm the skeleton builds**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 0b: Confirm `Theme`/`Palette` and the domain models exist**

Run: `ls Pulse/Core/DesignSystem/Theme.swift Pulse/Core/DesignSystem/Palette.swift Pulse/Core/Models/WorkoutModels.swift`
Expected: all three paths print (no "No such file"). The builder consumes `Exercise`, `Variation`, `WorkoutExercise`, `SetSpec`, `SetType`, `Workout`, `Program` from `WorkoutModels.swift`.

- [ ] **Step 0c: Branch**

Run: `git checkout -b feature/BAK-18-builders`
Expected: switched to a new branch.

---

## Task 1: Display / draft structs — `BuilderModels.swift` (TDD)

These are the UI-facing draft shapes the three models edit. They are pure value types with logic (superset re-badging, reps summary, MIXED flag) so they are unit-tested.

**Files:**
- Create: `Pulse/Features/Builders/BuilderModels.swift`
- Create: `PulseTests/BuilderModelsTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/BuilderModelsTests.swift`**

```swift
import XCTest
@testable import Pulse

final class BuilderModelsTests: XCTestCase {
    private func ex(_ name: String, _ muscle: String = "Chest") -> Exercise {
        Exercise(name: name, muscleGroup: muscle, variations: [], defaultVariationID: nil)
    }

    func testRepsSummaryJoinsWorkingSetsWithDash() {
        let item = BuilderExercise(
            exercise: ex("Flat bench"),
            variationID: nil,
            supersetGroup: nil,
            sets: [
                SetSpec(reps: 8, rir: 2, type: .working),
                SetSpec(reps: 10, rir: 2, type: .working),
            ])
        XCTAssertEqual(item.repsSummary, "8-10")
    }

    func testIsMixedTrueWhenAnyNonWorkingSet() {
        let working = BuilderExercise(
            exercise: ex("Incline"), variationID: nil, supersetGroup: nil,
            sets: [SetSpec(reps: 10, rir: 2, type: .working)])
        let mixed = BuilderExercise(
            exercise: ex("Flat bench"), variationID: nil, supersetGroup: nil,
            sets: [SetSpec(reps: 8, rir: 2, type: .warmup),
                   SetSpec(reps: 8, rir: 2, type: .working)])
        XCTAssertFalse(working.isMixed)
        XCTAssertTrue(mixed.isMixed)
    }

    func testFolderColorHasSixCasesBlueDefault() {
        XCTAssertEqual(FolderColor.allCases.count, 6)
        XCTAssertEqual(FolderColor.default, .blue)
        XCTAssertEqual(FolderColor.blue.hex, "#26B6F6")
    }

    func testWorkoutTagHasThreeCasesPushDefault() {
        XCTAssertEqual(WorkoutTag.allCases, [.push, .pull, .legs])
        XCTAssertEqual(WorkoutTag.push.label, "PUSH")
    }

    func testSaveStateEquatable() {
        XCTAssertEqual(SaveState.idle, .idle)
        XCTAssertNotEqual(SaveState.saved, SaveState.error("x"))
        XCTAssertEqual(SaveState.error("boom"), SaveState.error("boom"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `BuilderExercise`, `FolderColor`, `WorkoutTag`, `SaveState` undefined.

- [ ] **Step 3: Write `Pulse/Features/Builders/BuilderModels.swift`**

```swift
import Foundation

/// Lifecycle flag every builder exposes; the screen reads it to surface
/// saving / saved / error and to decide whether to pop.
enum SaveState: Equatable {
    case idle, saving, saved
    case error(String)
}

/// Single-select workout tag. PUSH/PULL/LEGS is the complete v1 set.
enum WorkoutTag: String, CaseIterable, Equatable {
    case push, pull, legs
    var label: String { rawValue.uppercased() }
}

/// The six fixed brand swatches a folder can take. Hex is the source value;
/// `Theme` exposes the matching `Color` so views never read hex directly.
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

/// A mutable editing view over `WorkoutExercise`. Consecutive items sharing a
/// non-nil `supersetGroup` render as one superset card.
struct BuilderExercise: Identifiable, Equatable {
    var id = UUID()
    var exercise: Exercise
    var variationID: Variation.ID?
    var supersetGroup: String?
    var sets: [SetSpec]

    /// Working-set reps joined by "-", e.g. "8-10-10".
    var repsSummary: String {
        sets.filter { $0.type == .working }.map { String($0.reps) }.joined(separator: "-")
    }

    /// True when any set is not a working set (drives the " · MIXED" suffix).
    var isMixed: Bool { sets.contains { $0.type != .working } }

    /// `{n} sets · {reps}` (+ " · MIXED").
    var subLine: String {
        let base = "\(sets.count) sets · \(repsSummary)"
        return isMixed ? "\(base) · MIXED" : base
    }
}

/// One ordered slot in a routine's weekly split. A rest day carries no source.
struct BuilderDay: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sub: String
    var isRest: Bool = false
    var sourceWorkoutID: Workout.ID? = nil
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (BuilderModelsTests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Builders/BuilderModels.swift PulseTests/BuilderModelsTests.swift
git commit -m "feat: builder draft structs (BuilderExercise/Day, WorkoutTag, FolderColor, SaveState)"
```

---

## Task 2: Repository protocols + display types (TDD via the mocks)

Defines the contracts the three builders bind to, plus the catalog/saved-workout display shapes. The protocols carry no logic; the *mocks* (Task 3) carry the seed data and write capture, so the failing test lives there. This task just lands the protocol surface so the mocks compile.

**Files:**
- Create: `Pulse/Core/Data/WorkoutRepository.swift`
- Create: `Pulse/Core/Data/RoutineRepository.swift`
- Create: `Pulse/Core/Data/FolderRepository.swift`
- Create: `Pulse/Core/Data/ExerciseCatalogRepository.swift`
- Create: `Pulse/Core/Data/CatalogTypes.swift`

- [ ] **Step 1: Write `Pulse/Core/Data/CatalogTypes.swift`**

```swift
import Foundation

/// One muscle section in the Exercise Picker catalog.
struct MuscleGroupCatalog: Identifiable, Equatable {
    var id = UUID()
    var muscle: String
    var exercises: [CatalogExercise]
}

/// A catalog row in the Exercise Picker. `exercise` is the full domain model
/// used to seed a `BuilderExercise` when picked.
struct CatalogExercise: Identifiable, Equatable {
    var id = UUID()
    var exercise: Exercise
    var equipment: String

    var name: String { exercise.name }
}

/// A saved workout as shown in the Workout Picker `FROM YOUR LIBRARY` list.
struct WorkoutSummary: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var sub: String              // e.g. "7 exercises"
    var sourceWorkoutID: Workout.ID
}
```

- [ ] **Step 2: Write `Pulse/Core/Data/ExerciseCatalogRepository.swift`**

```swift
import Foundation

/// Feeds the Exercise Picker. Shared with Library (BAK-10) / BAK-6.
protocol ExerciseCatalogRepository {
    func catalog() async throws -> [MuscleGroupCatalog]
}
```

- [ ] **Step 3: Write `Pulse/Core/Data/WorkoutRepository.swift`**

```swift
import Foundation

/// Saved-workout reads + workout writes. Real impl in BAK-6.
protocol WorkoutRepository {
    func savedWorkouts() async throws -> [WorkoutSummary]
    func saveWorkout(_ draft: Workout) async throws
}
```

- [ ] **Step 4: Write `Pulse/Core/Data/RoutineRepository.swift`**

```swift
import Foundation

/// Routine (Program) writes. Real impl in BAK-6.
protocol RoutineRepository {
    func saveRoutine(_ draft: Program) async throws
}
```

- [ ] **Step 5: Write `Pulse/Core/Data/FolderRepository.swift`**

```swift
import Foundation

/// Folder writes. Real impl in BAK-6.
protocol FolderRepository {
    func saveFolder(name: String, colorToken: FolderColor) async throws
}
```

- [ ] **Step 6: Build to confirm the protocols compile**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add Pulse/Core/Data/CatalogTypes.swift Pulse/Core/Data/ExerciseCatalogRepository.swift Pulse/Core/Data/WorkoutRepository.swift Pulse/Core/Data/RoutineRepository.swift Pulse/Core/Data/FolderRepository.swift
git commit -m "feat: builder repository protocols + catalog/summary display types"
```

---

## Task 3: In-memory mocks + sample data (TDD)

The mocks seed the prototype's catalog and saved-workout list, and capture writes so the model tests can assert on them. They have logic (capture, optional throw) so they are TDD'd.

**Files:**
- Create: `Pulse/Core/Data/Mocks/MockExerciseCatalogRepository.swift`
- Create: `Pulse/Core/Data/Mocks/MockWorkoutRepository.swift`
- Create: `Pulse/Core/Data/Mocks/MockRoutineRepository.swift`
- Create: `Pulse/Core/Data/Mocks/MockFolderRepository.swift`
- Create: `Pulse/Core/Data/Mocks/BuilderSampleData.swift`
- Create: `PulseTests/BuilderMocksTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/BuilderMocksTests.swift`**

```swift
import XCTest
@testable import Pulse

final class BuilderMocksTests: XCTestCase {
    func testCatalogMockReturnsGroupedExercises() async throws {
        let repo = MockExerciseCatalogRepository()
        let groups = try await repo.catalog()
        XCTAssertFalse(groups.isEmpty)
        XCTAssertTrue(groups.contains { $0.muscle == "Chest" })
        XCTAssertTrue(groups.allSatisfy { !$0.exercises.isEmpty })
    }

    func testSavedWorkoutsMockReturnsPrototypeList() async throws {
        let repo = MockWorkoutRepository()
        let saved = try await repo.savedWorkouts()
        XCTAssertEqual(saved.map(\.name).prefix(3),
                       ["Chest & Tris", "Back & Bis", "Legs"])
    }

    func testSaveWorkoutCapturesDraft() async throws {
        let repo = MockWorkoutRepository()
        let draft = Workout(name: "My push", weekday: nil, order: 0, exercises: [])
        try await repo.saveWorkout(draft)
        XCTAssertEqual(repo.savedDrafts.count, 1)
        XCTAssertEqual(repo.savedDrafts.first?.name, "My push")
    }

    func testSaveWorkoutThrowsWhenConfigured() async {
        let repo = MockWorkoutRepository(shouldThrow: true)
        do {
            try await repo.saveWorkout(Workout(name: "x", weekday: nil, order: 0, exercises: []))
            XCTFail("expected throw")
        } catch { /* expected */ }
    }

    func testSaveRoutineCapturesDraft() async throws {
        let repo = MockRoutineRepository()
        try await repo.saveRoutine(Program(name: "PPL", weeks: 8, workouts: []))
        XCTAssertEqual(repo.savedDrafts.first?.weeks, 8)
    }

    func testSaveFolderCapturesNameAndColor() async throws {
        let repo = MockFolderRepository()
        try await repo.saveFolder(name: "Cardio", colorToken: .pink)
        XCTAssertEqual(repo.saved.first?.name, "Cardio")
        XCTAssertEqual(repo.saved.first?.color, .pink)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — the mock types are undefined.

- [ ] **Step 3: Write `Pulse/Core/Data/Mocks/BuilderSampleData.swift`**

```swift
import Foundation

/// Prototype sample data shared by the builder mocks and default model state.
enum BuilderSampleData {

    static func exercise(_ name: String, _ muscle: String) -> Exercise {
        Exercise(name: name, muscleGroup: muscle, variations: [], defaultVariationID: nil)
    }

    /// Exercise Picker catalog (prototype EXERCISE_CATALOG).
    static let catalog: [MuscleGroupCatalog] = [
        MuscleGroupCatalog(muscle: "Chest", exercises: [
            CatalogExercise(exercise: exercise("Flat bench", "Chest"), equipment: "Barbell"),
            CatalogExercise(exercise: exercise("Incline press", "Chest"), equipment: "Dumbbell"),
            CatalogExercise(exercise: exercise("Cable fly", "Chest"), equipment: "Cable"),
        ]),
        MuscleGroupCatalog(muscle: "Back", exercises: [
            CatalogExercise(exercise: exercise("Lat pulldown", "Back"), equipment: "Cable"),
            CatalogExercise(exercise: exercise("Barbell row", "Back"), equipment: "Barbell"),
        ]),
        MuscleGroupCatalog(muscle: "Legs", exercises: [
            CatalogExercise(exercise: exercise("Back squat", "Legs"), equipment: "Barbell"),
            CatalogExercise(exercise: exercise("Leg press", "Legs"), equipment: "Machine"),
        ]),
        MuscleGroupCatalog(muscle: "Shoulders", exercises: [
            CatalogExercise(exercise: exercise("Overhead press", "Shoulders"), equipment: "Barbell"),
            CatalogExercise(exercise: exercise("Lateral raise", "Shoulders"), equipment: "Dumbbell"),
        ]),
        MuscleGroupCatalog(muscle: "Triceps", exercises: [
            CatalogExercise(exercise: exercise("Rope pushdown", "Triceps"), equipment: "Cable"),
        ]),
    ]

    /// Workout Picker `FROM YOUR LIBRARY`.
    static let savedWorkouts: [WorkoutSummary] = [
        WorkoutSummary(name: "Chest & Tris", sub: "7 exercises", sourceWorkoutID: UUID()),
        WorkoutSummary(name: "Back & Bis", sub: "6 exercises", sourceWorkoutID: UUID()),
        WorkoutSummary(name: "Legs", sub: "5 exercises", sourceWorkoutID: UUID()),
        WorkoutSummary(name: "Shoulders", sub: "5 exercises", sourceWorkoutID: UUID()),
        WorkoutSummary(name: "Arms · finisher", sub: "4 exercises", sourceWorkoutID: UUID()),
        WorkoutSummary(name: "Active recovery", sub: "3 exercises", sourceWorkoutID: UUID()),
    ]

    /// Default Workout Builder items: Flat bench (warmup/working×3/failure) + Incline (4 working).
    static var defaultWorkoutItems: [BuilderExercise] {
        [
            BuilderExercise(
                exercise: exercise("Flat bench", "Chest"), variationID: nil, supersetGroup: nil,
                sets: [
                    SetSpec(reps: 12, rir: 4, type: .warmup),
                    SetSpec(reps: 8, rir: 2, type: .working),
                    SetSpec(reps: 8, rir: 2, type: .working),
                    SetSpec(reps: 8, rir: 1, type: .working),
                    SetSpec(reps: 6, rir: 0, type: .failure),
                ]),
            BuilderExercise(
                exercise: exercise("Incline press", "Chest"), variationID: nil, supersetGroup: nil,
                sets: [
                    SetSpec(reps: 10, rir: 2, type: .working),
                    SetSpec(reps: 10, rir: 2, type: .working),
                    SetSpec(reps: 10, rir: 2, type: .working),
                    SetSpec(reps: 10, rir: 1, type: .working),
                ]),
        ]
    }

    /// Default Routine: 8 weeks, 5-day split.
    static var defaultRoutineDays: [BuilderDay] {
        [
            BuilderDay(name: "Chest & Tris", sub: "7 exercises"),
            BuilderDay(name: "Back & Bis", sub: "6 exercises"),
            BuilderDay(name: "Legs", sub: "5 exercises"),
            BuilderDay(name: "Rest", sub: "Recovery", isRest: true),
            BuilderDay(name: "Shoulders & Arms", sub: "6 exercises"),
        ]
    }
}
```

- [ ] **Step 4: Write `Pulse/Core/Data/Mocks/MockExerciseCatalogRepository.swift`**

```swift
import Foundation

final class MockExerciseCatalogRepository: ExerciseCatalogRepository {
    var shouldThrow = false
    func catalog() async throws -> [MuscleGroupCatalog] {
        if shouldThrow { throw MockError.failed }
        return BuilderSampleData.catalog
    }
}

enum MockError: Error { case failed }
```

- [ ] **Step 5: Write `Pulse/Core/Data/Mocks/MockWorkoutRepository.swift`**

```swift
import Foundation

final class MockWorkoutRepository: WorkoutRepository {
    private(set) var savedDrafts: [Workout] = []
    var shouldThrow: Bool

    init(shouldThrow: Bool = false) { self.shouldThrow = shouldThrow }

    func savedWorkouts() async throws -> [WorkoutSummary] {
        if shouldThrow { throw MockError.failed }
        return BuilderSampleData.savedWorkouts
    }

    func saveWorkout(_ draft: Workout) async throws {
        if shouldThrow { throw MockError.failed }
        savedDrafts.append(draft)
    }
}
```

- [ ] **Step 6: Write `Pulse/Core/Data/Mocks/MockRoutineRepository.swift`**

```swift
import Foundation

final class MockRoutineRepository: RoutineRepository {
    private(set) var savedDrafts: [Program] = []
    var shouldThrow: Bool

    init(shouldThrow: Bool = false) { self.shouldThrow = shouldThrow }

    func saveRoutine(_ draft: Program) async throws {
        if shouldThrow { throw MockError.failed }
        savedDrafts.append(draft)
    }
}
```

- [ ] **Step 7: Write `Pulse/Core/Data/Mocks/MockFolderRepository.swift`**

```swift
import Foundation

final class MockFolderRepository: FolderRepository {
    struct Saved: Equatable { var name: String; var color: FolderColor }
    private(set) var saved: [Saved] = []
    var shouldThrow: Bool

    init(shouldThrow: Bool = false) { self.shouldThrow = shouldThrow }

    func saveFolder(name: String, colorToken: FolderColor) async throws {
        if shouldThrow { throw MockError.failed }
        saved.append(Saved(name: name, color: colorToken))
    }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (BuilderMocksTests green).

- [ ] **Step 9: Commit**

```bash
git add Pulse/Core/Data/Mocks PulseTests/BuilderMocksTests.swift
git commit -m "feat: in-memory builder mocks + prototype sample data"
```

---

## Task 4: Folder color tokens on `Theme`

The six folder swatches are fixed brand colors that intentionally do NOT re-skin between Coastal and Mint. Expose them as a `Theme` accessor so views never read raw hex (satisfies the "Theme tokens only" rule).

**Files:**
- Modify: `Pulse/Core/DesignSystem/Theme.swift`

- [ ] **Step 1: Add a `color(for:)` accessor to `Theme`**

Insert into `Theme` (after the `onAccent` token):

```swift
    /// Fixed brand swatches for folders. Intentionally palette-independent.
    func folderColor(_ token: FolderColor) -> Color { Color(hex: token.hex) }
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Core/DesignSystem/Theme.swift
git commit -m "feat: Theme.folderColor token accessor for fixed brand swatches"
```

---

## Task 5: `WorkoutBuilderModel` (TDD)

The model owns the editable item list, tag, superset linking, and set editing, plus the save call. All logic — TDD.

**Files:**
- Create: `Pulse/Features/Builders/WorkoutBuilderModel.swift`
- Create: `PulseTests/WorkoutBuilderModelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/WorkoutBuilderModelTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class WorkoutBuilderModelTests: XCTestCase {
    private func makeModel() -> WorkoutBuilderModel {
        WorkoutBuilderModel(
            catalog: MockExerciseCatalogRepository(),
            workouts: MockWorkoutRepository())
    }

    private func catalogIDs(_ model: WorkoutBuilderModel) async -> [Exercise.ID] {
        await model.loadCatalog()
        return model.catalog.flatMap { $0.exercises }.map { $0.exercise.id }
    }

    func testStartsWithSeededItems() {
        let model = makeModel()
        XCTAssertEqual(model.items.count, 2)
        XCTAssertEqual(model.items.first?.exercise.name, "Flat bench")
    }

    func testTotalSetsSumsSetCounts() {
        let model = makeModel()
        XCTAssertEqual(model.totalSets, 9) // 5 + 4
    }

    func testAddExercisesAppendsAndSkipsDuplicates() async {
        let model = makeModel()
        await model.loadCatalog()
        let first = model.catalog[0].exercises[0].exercise   // Flat bench — already present? seeded by name not id
        let newID = model.catalog[1].exercises[0].exercise.id // Lat pulldown
        let before = model.items.count
        model.addExercises([newID, newID]) // duplicate id in the same call
        XCTAssertEqual(model.items.count, before + 1)
        XCTAssertEqual(model.items.last?.exercise.name, "Lat pulldown")
        // Adding the same id again is skipped.
        model.addExercises([newID])
        XCTAssertEqual(model.items.count, before + 1)
        _ = first
    }

    func testAddedExerciseSeedsADefaultSet() async {
        let model = makeModel()
        await model.loadCatalog()
        let newID = model.catalog[1].exercises[0].exercise.id
        model.addExercises([newID])
        XCTAssertEqual(model.items.last?.sets.count, 1)
        XCTAssertEqual(model.items.last?.sets.first?.type, .working)
    }

    func testRemoveItemDropsMatch() {
        let model = makeModel()
        let id = model.items[0].id
        model.removeItem(id: id)
        XCTAssertFalse(model.items.contains { $0.id == id })
        XCTAssertEqual(model.items.count, 1)
    }

    func testToggleLinkAssignsSharedGroupThenUnlinks() {
        let model = makeModel()
        model.toggleLink(at: 0)
        let g0 = model.items[0].supersetGroup
        let g1 = model.items[1].supersetGroup
        XCTAssertNotNil(g0)
        XCTAssertEqual(g0, g1)
        // Toggling again breaks the lower row out.
        model.toggleLink(at: 0)
        XCTAssertNil(model.items[1].supersetGroup)
    }

    func testToggleLinkLastRowIsNoOp() {
        let model = makeModel()
        let last = model.items.count - 1
        model.toggleLink(at: last)
        XCTAssertNil(model.items[last].supersetGroup)
    }

    func testAddSetClonesLastAsWorking() {
        let model = makeModel()
        let id = model.items[0].id
        let before = model.items[0].sets.count
        model.addSet(itemID: id)
        XCTAssertEqual(model.items[0].sets.count, before + 1)
        XCTAssertEqual(model.items[0].sets.last?.type, .working)
    }

    func testRemoveSetRefusesWhenOneRemains() {
        let model = makeModel()
        let id = model.items[1].id
        // Reduce to a single set.
        while model.items.first(where: { $0.id == id })!.sets.count > 1 {
            model.removeSet(itemID: id, index: 0)
        }
        let count = model.items.first(where: { $0.id == id })!.sets.count
        XCTAssertEqual(count, 1)
        model.removeSet(itemID: id, index: 0) // refused
        XCTAssertEqual(model.items.first(where: { $0.id == id })!.sets.count, 1)
    }

    func testUpdateSetClampsRIRToZeroFive() {
        let model = makeModel()
        let id = model.items[0].id
        model.updateSet(itemID: id, index: 0, reps: 9, rir: 99, type: .working)
        XCTAssertEqual(model.items[0].sets[0].rir, 5)
        XCTAssertEqual(model.items[0].sets[0].reps, 9)
        model.updateSet(itemID: id, index: 0, reps: 9, rir: -3, type: .amrap)
        XCTAssertEqual(model.items[0].sets[0].rir, 0)
        XCTAssertEqual(model.items[0].sets[0].type, .amrap)
    }

    func testSaveCallsRepositoryAndSetsSaved() async {
        let repo = MockWorkoutRepository()
        let model = WorkoutBuilderModel(catalog: MockExerciseCatalogRepository(), workouts: repo)
        await model.save()
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(repo.savedDrafts.count, 1)
        XCTAssertEqual(repo.savedDrafts.first?.exercises.count, model.items.count)
    }

    func testSaveErrorWhenRepositoryThrows() async {
        let repo = MockWorkoutRepository(shouldThrow: true)
        let model = WorkoutBuilderModel(catalog: MockExerciseCatalogRepository(), workouts: repo)
        await model.save()
        if case .error = model.saveState { } else { XCTFail("expected .error") }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `WorkoutBuilderModel` undefined.

- [ ] **Step 3: Write `Pulse/Features/Builders/WorkoutBuilderModel.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class WorkoutBuilderModel {
    var name: String = "New workout"
    var tag: WorkoutTag = .push
    var items: [BuilderExercise] = BuilderSampleData.defaultWorkoutItems
    var pickerPresented = false
    var editingItemID: BuilderExercise.ID? = nil
    var saveState: SaveState = .idle

    // Exercise Picker state.
    var catalog: [MuscleGroupCatalog] = []
    var catalogLoading = false
    var catalogError: String? = nil

    private let catalogRepo: ExerciseCatalogRepository
    private let workoutRepo: WorkoutRepository

    init(catalog: ExerciseCatalogRepository, workouts: WorkoutRepository) {
        self.catalogRepo = catalog
        self.workoutRepo = workouts
    }

    var totalSets: Int { items.reduce(0) { $0 + $1.sets.count } }

    /// The set of exercise ids already in the builder (drives picker dimming).
    var addedExerciseIDs: Set<Exercise.ID> { Set(items.map { $0.exercise.id }) }

    func loadCatalog() async {
        catalogLoading = true
        catalogError = nil
        do {
            catalog = try await catalogRepo.catalog()
        } catch {
            catalogError = "Couldn't load exercises."
        }
        catalogLoading = false
    }

    /// Append picked exercises (deduped against existing + within the batch),
    /// each seeded with one working set.
    func addExercises(_ ids: [Exercise.ID]) {
        var present = addedExerciseIDs
        let lookup = Dictionary(
            uniqueKeysWithValues: catalog.flatMap { $0.exercises }.map { ($0.exercise.id, $0.exercise) })
        for id in ids where !present.contains(id) {
            guard let exercise = lookup[id] else { continue }
            present.insert(id)
            items.append(BuilderExercise(
                exercise: exercise,
                variationID: exercise.defaultVariationID,
                supersetGroup: nil,
                sets: [SetSpec(reps: 10, rir: 2, type: .working)]))
        }
    }

    func removeItem(id: BuilderExercise.ID) {
        items.removeAll { $0.id == id }
    }

    /// Toggle the link between row `idx` and `idx+1`. No-op on the last row.
    func toggleLink(at idx: Int) {
        guard idx >= 0, idx + 1 < items.count else { return }
        let a = items[idx].supersetGroup
        let b = items[idx + 1].supersetGroup
        if let a, a == b {
            items[idx + 1].supersetGroup = nil       // break the lower row out
        } else {
            let group = a ?? UUID().uuidString
            items[idx].supersetGroup = group
            items[idx + 1].supersetGroup = group
        }
    }

    func addSet(itemID: BuilderExercise.ID) {
        guard let i = items.firstIndex(where: { $0.id == itemID }),
              let last = items[i].sets.last else { return }
        items[i].sets.append(SetSpec(reps: last.reps, rir: last.rir, type: .working))
    }

    func removeSet(itemID: BuilderExercise.ID, index: Int) {
        guard let i = items.firstIndex(where: { $0.id == itemID }),
              items[i].sets.count > 1,
              items[i].sets.indices.contains(index) else { return }
        items[i].sets.remove(at: index)
    }

    func updateSet(itemID: BuilderExercise.ID, index: Int, reps: Int, rir: Int, type: SetType) {
        guard let i = items.firstIndex(where: { $0.id == itemID }),
              items[i].sets.indices.contains(index) else { return }
        items[i].sets[index].reps = max(0, reps)
        items[i].sets[index].rir = min(5, max(0, rir))
        items[i].sets[index].type = type
    }

    func save() async {
        saveState = .saving
        let workoutExercises = items.map {
            WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                            supersetGroup: $0.supersetGroup, sets: $0.sets)
        }
        let draft = Workout(name: name, weekday: nil, order: 0, exercises: workoutExercises)
        do {
            try await workoutRepo.saveWorkout(draft)
            saveState = .saved
        } catch {
            saveState = .error("Couldn't save workout.")
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (WorkoutBuilderModelTests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Builders/WorkoutBuilderModel.swift PulseTests/WorkoutBuilderModelTests.swift
git commit -m "feat: WorkoutBuilderModel — items, supersets, set editing, save"
```

---

## Task 6: `RoutineBuilderModel` (TDD)

**Files:**
- Create: `Pulse/Features/Builders/RoutineBuilderModel.swift`
- Create: `PulseTests/RoutineBuilderModelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/RoutineBuilderModelTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class RoutineBuilderModelTests: XCTestCase {
    private func makeModel(_ repo: MockRoutineRepository = MockRoutineRepository(),
                           workouts: MockWorkoutRepository = MockWorkoutRepository()) -> RoutineBuilderModel {
        RoutineBuilderModel(routines: repo, workouts: workouts)
    }

    func testSeededDefaults() {
        let model = makeModel()
        XCTAssertEqual(model.weeks, 8)
        XCTAssertEqual(model.days.count, 5)
        XCTAssertEqual(model.workoutsPerWeek, 4) // 5 days, 1 rest
    }

    func testIncWeeks() {
        let model = makeModel()
        model.incWeeks()
        XCTAssertEqual(model.weeks, 9)
    }

    func testDecWeeksClampsAtOne() {
        let model = makeModel()
        model.weeks = 1
        model.decWeeks()
        XCTAssertEqual(model.weeks, 1)
    }

    func testAddWorkoutAppendsDay() {
        let model = makeModel()
        let before = model.days.count
        model.addWorkout(BuilderDay(name: "Arms", sub: "4 exercises"))
        XCTAssertEqual(model.days.count, before + 1)
        XCTAssertEqual(model.days.last?.name, "Arms")
    }

    func testAddRestDayAppendsRest() {
        let model = makeModel()
        let beforeWorkouts = model.workoutsPerWeek
        model.addRestDay()
        XCTAssertTrue(model.days.last?.isRest == true)
        XCTAssertEqual(model.workoutsPerWeek, beforeWorkouts) // rest doesn't count
    }

    func testRemoveDay() {
        let model = makeModel()
        let id = model.days[0].id
        model.removeDay(id: id)
        XCTAssertFalse(model.days.contains { $0.id == id })
    }

    func testSaveCallsRepositoryAndSetsSaved() async {
        let repo = MockRoutineRepository()
        let model = makeModel(repo)
        await model.save()
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(repo.savedDrafts.first?.weeks, 8)
        // Rest days are excluded from the persisted Program's workouts.
        XCTAssertEqual(repo.savedDrafts.first?.workouts.count, model.workoutsPerWeek)
    }

    func testSaveErrorWhenRepositoryThrows() async {
        let model = makeModel(MockRoutineRepository(shouldThrow: true))
        await model.save()
        if case .error = model.saveState { } else { XCTFail("expected .error") }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `RoutineBuilderModel` undefined.

- [ ] **Step 3: Write `Pulse/Features/Builders/RoutineBuilderModel.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class RoutineBuilderModel {
    var name: String = "New routine"
    var weeks: Int = 8
    var days: [BuilderDay] = BuilderSampleData.defaultRoutineDays
    var pickerPresented = false
    var saveState: SaveState = .idle

    // Workout Picker state.
    var savedWorkouts: [WorkoutSummary] = []
    var savedLoading = false
    var savedError: String? = nil

    private let routineRepo: RoutineRepository
    private let workoutRepo: WorkoutRepository

    init(routines: RoutineRepository, workouts: WorkoutRepository) {
        self.routineRepo = routines
        self.workoutRepo = workouts
    }

    var workoutsPerWeek: Int { days.filter { !$0.isRest }.count }

    func loadSavedWorkouts() async {
        savedLoading = true
        savedError = nil
        do {
            savedWorkouts = try await workoutRepo.savedWorkouts()
        } catch {
            savedError = "Couldn't load workouts."
        }
        savedLoading = false
    }

    func incWeeks() { weeks += 1 }
    func decWeeks() { weeks = max(1, weeks - 1) }

    func addWorkout(_ day: BuilderDay) { days.append(day) }

    func addRestDay() {
        days.append(BuilderDay(name: "Rest", sub: "Recovery", isRest: true))
    }

    func removeDay(id: BuilderDay.ID) { days.removeAll { $0.id == id } }

    func save() async {
        saveState = .saving
        let workouts = days.enumerated()
            .filter { !$0.element.isRest }
            .map { idx, day in
                Workout(name: day.name, weekday: nil, order: idx, exercises: [])
            }
        let draft = Program(name: name, weeks: weeks, workouts: workouts)
        do {
            try await routineRepo.saveRoutine(draft)
            saveState = .saved
        } catch {
            saveState = .error("Couldn't save routine.")
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (RoutineBuilderModelTests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Builders/RoutineBuilderModel.swift PulseTests/RoutineBuilderModelTests.swift
git commit -m "feat: RoutineBuilderModel — weeks, days, weekly split, save"
```

---

## Task 7: `FolderBuilderModel` (TDD)

**Files:**
- Create: `Pulse/Features/Builders/FolderBuilderModel.swift`
- Create: `PulseTests/FolderBuilderModelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/FolderBuilderModelTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class FolderBuilderModelTests: XCTestCase {
    func testDefaults() {
        let model = FolderBuilderModel(folders: MockFolderRepository())
        XCTAssertEqual(model.name, "New folder")
        XCTAssertEqual(model.colorToken, .blue)
    }

    func testSelectColorUpdatesToken() {
        let model = FolderBuilderModel(folders: MockFolderRepository())
        model.select(color: .purple)
        XCTAssertEqual(model.colorToken, .purple)
    }

    func testSaveCallsRepositoryWithNameAndColor() async {
        let repo = MockFolderRepository()
        let model = FolderBuilderModel(folders: repo)
        model.name = "Cardio"
        model.select(color: .pink)
        await model.save()
        XCTAssertEqual(model.saveState, .saved)
        XCTAssertEqual(repo.saved.first, .init(name: "Cardio", color: .pink))
    }

    func testSaveErrorWhenRepositoryThrows() async {
        let model = FolderBuilderModel(folders: MockFolderRepository(shouldThrow: true))
        await model.save()
        if case .error = model.saveState { } else { XCTFail("expected .error") }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `FolderBuilderModel` undefined.

- [ ] **Step 3: Write `Pulse/Features/Builders/FolderBuilderModel.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class FolderBuilderModel {
    var name: String = "New folder"
    var colorToken: FolderColor = .default
    var saveState: SaveState = .idle

    private let folderRepo: FolderRepository

    init(folders: FolderRepository) { self.folderRepo = folders }

    func select(color: FolderColor) { colorToken = color }

    func save() async {
        saveState = .saving
        do {
            try await folderRepo.saveFolder(name: name, colorToken: colorToken)
            saveState = .saved
        } catch {
            saveState = .error("Couldn't create folder.")
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (FolderBuilderModelTests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Builders/FolderBuilderModel.swift PulseTests/FolderBuilderModelTests.swift
git commit -m "feat: FolderBuilderModel — name, color, save"
```

---

## Task 8: Shared builder UI primitives (eyebrow, chip, badge, scaffold)

Small reusable pieces the builder views need. These are pure view assembly (no logic), validated by `#Preview`. If BAK-7 already ships equivalents (`FilterChip`, eyebrow text, `IconBtn`), reuse those instead and skip the duplicates — these are defined here so this feature is buildable standalone.

**Files:**
- Create: `Pulse/Features/Builders/BuilderUI.swift`

- [ ] **Step 1: Write `Pulse/Features/Builders/BuilderUI.swift`**

```swift
import SwiftUI

/// Geist Mono uppercase eyebrow / label.
struct Eyebrow: View {
    let text: String
    @Environment(Theme.self) private var theme
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(theme.inkSoft)
            .textCase(.uppercase)
            .accessibilityIdentifier("eyebrow-\(text)")
    }
}

/// Pill chip with the design-system border + hard offset shadow + press translate.
struct PillChip: View {
    let label: String
    let selected: Bool
    var fill: Color
    var onFill: Color
    let action: () -> Void
    @Environment(Theme.self) private var theme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(selected ? onFill : theme.inkSoft)
                .padding(.horizontal, theme.spacing[3])
                .padding(.vertical, theme.spacing[1])
                .background(selected ? fill : .clear, in: Capsule())
                .overlay(Capsule().stroke(theme.ink, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

/// Numbered / lettered badge used in exercise rows and the Set Editor.
struct BuilderBadge: View {
    let text: String
    var tinted: Bool
    @Environment(Theme.self) private var theme
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .foregroundStyle(tinted ? theme.onAccent : theme.ink)
            .frame(width: 28, height: 28)
            .background(tinted ? theme.accent2 : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.ink, lineWidth: 2))
    }
}

/// Builder screen scaffold: top bar (eyebrow + inert ⋯), content, footer
/// (Cancel + primary). Footer primary is disabled while saving.
struct BuilderScaffold<Content: View>: View {
    let eyebrow: String
    let primaryLabel: String
    let saving: Bool
    let onCancel: () -> Void
    let onPrimary: () -> Void
    @ViewBuilder var content: Content
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Eyebrow(text: eyebrow)
                Spacer()
                Image(systemName: "ellipsis")
                    .foregroundStyle(theme.inkSoft)
                    .accessibilityIdentifier("overflow")
            }
            .padding(.horizontal, theme.spacing[6])
            .padding(.vertical, theme.spacing[3])

            ScrollView { content.padding(.horizontal, theme.spacing[6]) }

            HStack(spacing: theme.spacing[2]) {
                Button("Cancel", action: onCancel)
                    .accessibilityIdentifier("builder-cancel")
                Spacer()
                Button(action: onPrimary) { Text(primaryLabel) }
                    .disabled(saving)
                    .accessibilityIdentifier("builder-primary")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.ink)
            .padding(theme.spacing[6])
        }
        .background(theme.bg.ignoresSafeArea())
    }
}

#Preview {
    BuilderScaffold(eyebrow: "NEW WORKOUT", primaryLabel: "Save workout →",
                    saving: false, onCancel: {}, onPrimary: {}) {
        VStack(alignment: .leading) {
            PillChip(label: "PUSH", selected: true, fill: .orange, onFill: .black, action: {})
            BuilderBadge(text: "A", tinted: true)
        }
    }
    .environment(Theme())
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Builders/BuilderUI.swift
git commit -m "feat: shared builder UI primitives (eyebrow, chip, badge, scaffold)"
```

---

## Task 9: Set Editor sheet (view assembly)

**Files:**
- Create: `Pulse/Features/Builders/SetEditorSheet.swift`

- [ ] **Step 1: Write `Pulse/Features/Builders/SetEditorSheet.swift`**

The sheet binds to the `WorkoutBuilderModel` and the editing item id; edits mutate the model's item in place via its intent methods.

```swift
import SwiftUI

struct SetEditorSheet: View {
    @Bindable var model: WorkoutBuilderModel
    let itemID: BuilderExercise.ID
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    private var item: BuilderExercise? { model.items.first { $0.id == itemID } }

    private let types: [SetType] = [.working, .warmup, .dropset, .failure, .amrap]
    private func typeLabel(_ t: SetType) -> String {
        switch t {
        case .working: return "Working"
        case .warmup:  return "Warm-up"
        case .dropset: return "Drop set"
        case .failure: return "To failure"
        case .amrap:   return "AMRAP"
        }
    }

    var body: some View {
        guard let item else { return AnyView(EmptyView()) }
        return AnyView(content(item))
    }

    private func content(_ item: BuilderExercise) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing[4]) {
            Eyebrow(text: "\(item.exercise.muscleGroup.uppercased()) · \(item.sets.count) SETS")
            Text("\(item.exercise.name).")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(theme.ink)

            HStack {
                Eyebrow(text: "SET")
                Spacer()
                Eyebrow(text: "REPS")
                Spacer()
                Eyebrow(text: "RIR")
            }

            ForEach(Array(item.sets.enumerated()), id: \.element.id) { idx, set in
                setRow(item: item, idx: idx, set: set)
            }

            Button {
                model.addSet(itemID: item.id)
            } label: {
                Text("+ Add set")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(theme.spacing[3])
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [5])))
            }
            .accessibilityIdentifier("set-editor-add")

            Button { dismiss() } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(theme.spacing[4])
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityIdentifier("set-editor-done")
        }
        .padding(theme.spacing[6])
        .background(theme.surface.ignoresSafeArea())
    }

    @ViewBuilder
    private func setRow(item: BuilderExercise, idx: Int, set: SetSpec) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            HStack(spacing: theme.spacing[3]) {
                BuilderBadge(text: "\(idx + 1)", tinted: set.type != .working)

                TextField("reps", value: Binding(
                    get: { set.reps },
                    set: { model.updateSet(itemID: item.id, index: idx, reps: $0, rir: set.rir, type: set.type) }),
                    format: .number)
                    .keyboardType(.numberPad)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.ink)
                    .frame(width: 60)
                    .accessibilityIdentifier("set-reps-\(idx)")

                HStack(spacing: theme.spacing[1]) {
                    Button("−") { model.updateSet(itemID: item.id, index: idx, reps: set.reps, rir: set.rir - 1, type: set.type) }
                        .accessibilityIdentifier("set-rir-dec-\(idx)")
                    Text("\(set.rir)").foregroundStyle(theme.accent)
                        .accessibilityIdentifier("set-rir-\(idx)")
                    Button("+") { model.updateSet(itemID: item.id, index: idx, reps: set.reps, rir: set.rir + 1, type: set.type) }
                        .accessibilityIdentifier("set-rir-inc-\(idx)")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.ink)

                Spacer()

                Button {
                    model.removeSet(itemID: item.id, index: idx)
                } label: { Image(systemName: "xmark") }
                    .disabled(item.sets.count <= 1)
                    .opacity(item.sets.count <= 1 ? 0.3 : 1)
                    .foregroundStyle(theme.inkSoft)
                    .accessibilityIdentifier("set-remove-\(idx)")
            }

            HStack(spacing: theme.spacing[1]) {
                ForEach(types, id: \.self) { t in
                    PillChip(label: typeLabel(t), selected: set.type == t,
                             fill: theme.accent, onFill: theme.onAccent) {
                        model.updateSet(itemID: item.id, index: idx, reps: set.reps, rir: set.rir, type: t)
                    }
                }
            }
        }
        .padding(.vertical, theme.spacing[1])
    }
}

#Preview {
    let model = WorkoutBuilderModel(catalog: MockExerciseCatalogRepository(), workouts: MockWorkoutRepository())
    return SetEditorSheet(model: model, itemID: model.items[0].id)
        .environment(Theme())
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Builders/SetEditorSheet.swift
git commit -m "feat: Set Editor sheet — per-set reps/RIR/type editing"
```

---

## Task 10: Exercise Picker sheet (view assembly)

**Files:**
- Create: `Pulse/Features/Builders/ExercisePickerSheet.swift`

- [ ] **Step 1: Write `Pulse/Features/Builders/ExercisePickerSheet.swift`**

The picker holds its own transient selection set; on confirm it calls back with the selected ids (the model dedupes). Already-added exercises are dimmed and non-selectable.

```swift
import SwiftUI

struct ExercisePickerSheet: View {
    let catalog: [MuscleGroupCatalog]
    let loading: Bool
    let errorText: String?
    let alreadyAdded: Set<Exercise.ID>
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onConfirm: ([Exercise.ID]) -> Void

    @State private var selected: Set<Exercise.ID> = []
    @State private var filter: String = "All"
    @Environment(Theme.self) private var theme

    private var muscles: [String] { ["All"] + catalog.map { $0.muscle } }
    private var visibleGroups: [MuscleGroupCatalog] {
        filter == "All" ? catalog : catalog.filter { $0.muscle == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: theme.spacing[3]) {
                Eyebrow(text: "ADD EXERCISE")
                Text("Pick exercises.")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(theme.ink)

                // Decorative search (inert per product decisions).
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.inkFaint)
                    Text("Search").foregroundStyle(theme.inkFaint)
                    Spacer()
                }
                .padding(theme.spacing[3])
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.inkFaint, lineWidth: 2))
                .accessibilityIdentifier("exercise-search")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: theme.spacing[1]) {
                        ForEach(muscles, id: \.self) { m in
                            PillChip(label: m, selected: filter == m,
                                     fill: theme.accent, onFill: theme.onAccent) { filter = m }
                        }
                    }
                }
            }
            .padding(theme.spacing[6])

            content

            HStack(spacing: theme.spacing[2]) {
                Button("Cancel", action: onCancel).accessibilityIdentifier("picker-cancel")
                Spacer()
                Button { onConfirm(Array(selected)) } label: {
                    Text(selected.isEmpty ? "Select exercises" : "Add \(selected.count) selected")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, theme.spacing[5])
                        .padding(.vertical, theme.spacing[3])
                        .background(theme.accent, in: Capsule())
                }
                .disabled(selected.isEmpty)
                .opacity(selected.isEmpty ? 0.5 : 1)
                .accessibilityIdentifier("picker-confirm")
            }
            .foregroundStyle(theme.ink)
            .padding(theme.spacing[6])
        }
        .background(theme.surface.ignoresSafeArea())
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("picker-loading")
        } else if let errorText {
            VStack(spacing: theme.spacing[3]) {
                Text(errorText).foregroundStyle(theme.inkSoft)
                Button("Retry", action: onRetry).accessibilityIdentifier("picker-retry")
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing[4]) {
                    ForEach(visibleGroups) { group in
                        Eyebrow(text: group.muscle)
                        ForEach(group.exercises) { ce in row(ce) }
                    }
                }
                .padding(.horizontal, theme.spacing[6])
            }
        }
    }

    @ViewBuilder private func row(_ ce: CatalogExercise) -> some View {
        let added = alreadyAdded.contains(ce.exercise.id)
        let isSel = selected.contains(ce.exercise.id)
        Button {
            guard !added else { return }
            if isSel { selected.remove(ce.exercise.id) } else { selected.insert(ce.exercise.id) }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(ce.name).foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                    Text(ce.equipment).foregroundStyle(theme.inkSoft).font(.system(size: 13))
                }
                Spacer()
                Image(systemName: (added || isSel) ? "checkmark" : "plus")
                    .foregroundStyle(added ? theme.inkSoft : theme.accent)
            }
            .padding(theme.spacing[3])
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isSel ? theme.accent : theme.inkFaint, lineWidth: isSel ? 2 : 1))
        }
        .buttonStyle(.plain)
        .disabled(added)
        .opacity(added ? 0.4 : 1)
        .accessibilityIdentifier("picker-row-\(ce.name)")
    }
}

#Preview {
    ExercisePickerSheet(catalog: BuilderSampleData.catalog, loading: false, errorText: nil,
                        alreadyAdded: [], onRetry: {}, onCancel: {}, onConfirm: { _ in })
        .environment(Theme())
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Builders/ExercisePickerSheet.swift
git commit -m "feat: Exercise Picker sheet — grouped multi-select catalog"
```

---

## Task 11: Workout Picker sheet (view assembly)

**Files:**
- Create: `Pulse/Features/Builders/WorkoutPickerSheet.swift`

- [ ] **Step 1: Write `Pulse/Features/Builders/WorkoutPickerSheet.swift`**

```swift
import SwiftUI

struct WorkoutPickerSheet: View {
    let saved: [WorkoutSummary]
    let loading: Bool
    let errorText: String?
    let onRetry: () -> Void
    let onCreateNew: () -> Void
    let onPick: (WorkoutSummary) -> Void
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: theme.spacing[3]) {
                Eyebrow(text: "ADD TO ROUTINE")
                Text("Add a workout.")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(theme.ink)

                Button(action: onCreateNew) {
                    HStack {
                        Image(systemName: "plus")
                            .foregroundStyle(theme.accent)
                            .frame(width: 40, height: 40)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.accent, lineWidth: 2))
                        VStack(alignment: .leading) {
                            Text("Create new workout").foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                            Text("Build from scratch").foregroundStyle(theme.inkSoft).font(.system(size: 13))
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(theme.accent)
                    }
                    .padding(theme.spacing[3])
                    .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.accent, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wpicker-create-new")
            }
            .padding(theme.spacing[6])

            content
        }
        .background(theme.surface.ignoresSafeArea())
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("wpicker-loading")
        } else if let errorText {
            VStack(spacing: theme.spacing[3]) {
                Text(errorText).foregroundStyle(theme.inkSoft)
                Button("Retry", action: onRetry).accessibilityIdentifier("wpicker-retry")
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing[2]) {
                    Eyebrow(text: "FROM YOUR LIBRARY")
                    ForEach(saved) { w in
                        Button { onPick(w) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(w.name).foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                                    Text(w.sub).foregroundStyle(theme.inkSoft).font(.system(size: 13))
                                }
                                Spacer()
                                Image(systemName: "plus").foregroundStyle(theme.accent)
                            }
                            .padding(theme.spacing[3])
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.inkFaint, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wpicker-row-\(w.name)")
                    }
                }
                .padding(.horizontal, theme.spacing[6])
            }
        }
    }
}

#Preview {
    WorkoutPickerSheet(saved: BuilderSampleData.savedWorkouts, loading: false, errorText: nil,
                       onRetry: {}, onCreateNew: {}, onPick: { _ in })
        .environment(Theme())
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Builders/WorkoutPickerSheet.swift
git commit -m "feat: Workout Picker sheet — create-new card + saved list"
```

---

## Task 12: Workout Builder view (view assembly)

**Files:**
- Create: `Pulse/Features/Builders/WorkoutBuilderView.swift`

- [ ] **Step 1: Write `Pulse/Features/Builders/WorkoutBuilderView.swift`**

Renders the name field, tag chips, counts header, the grouped exercise list (superset cards + rows), the add-exercise row, and the footer. Hosts the Set Editor and Exercise Picker sheets. On `.saved`, dismisses.

```swift
import SwiftUI

struct WorkoutBuilderView: View {
    @State var model: WorkoutBuilderModel
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    init(model: WorkoutBuilderModel) { _model = State(initialValue: model) }

    var body: some View {
        BuilderScaffold(
            eyebrow: "NEW WORKOUT", primaryLabel: "Save workout →",
            saving: model.saveState == .saving,
            onCancel: { dismiss() },
            onPrimary: { Task { await model.save() } }
        ) {
            VStack(alignment: .leading, spacing: theme.spacing[4]) {
                TextField("Workout name", text: $model.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("workout-name")

                HStack(spacing: theme.spacing[1]) {
                    ForEach(WorkoutTag.allCases, id: \.self) { tag in
                        PillChip(label: tag.label, selected: model.tag == tag,
                                 fill: theme.accent2, onFill: theme.onAccent) { model.tag = tag }
                    }
                    Text("+ TAG")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.inkFaint)
                        .padding(.horizontal, theme.spacing[3]).padding(.vertical, theme.spacing[1])
                        .overlay(Capsule().strokeBorder(theme.inkFaint, style: StrokeStyle(lineWidth: 2, dash: [4])))
                }

                HStack {
                    Eyebrow(text: "EXERCISES · \(model.items.count)")
                    Spacer()
                    Eyebrow(text: "\(model.totalSets) SETS")
                }

                exerciseList

                Button { model.pickerPresented = true } label: {
                    Text("+ ADD EXERCISE")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity).padding(theme.spacing[4])
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6])))
                }
                .accessibilityIdentifier("add-exercise")

                Text("Tap ⛓ on an exercise to superset it with the one below.")
                    .font(.system(size: 12)).foregroundStyle(theme.inkSoft)

                if case let .error(msg) = model.saveState {
                    Text(msg).foregroundStyle(theme.accent2).accessibilityIdentifier("save-error")
                }
            }
            .padding(.vertical, theme.spacing[3])
        }
        .sheet(item: Binding(get: { model.editingItemID.map { IDBox(id: $0) } },
                             set: { model.editingItemID = $0?.id })) { box in
            SetEditorSheet(model: model, itemID: box.id)
                .environment(theme)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $model.pickerPresented) {
            ExercisePickerSheet(
                catalog: model.catalog, loading: model.catalogLoading, errorText: model.catalogError,
                alreadyAdded: model.addedExerciseIDs,
                onRetry: { Task { await model.loadCatalog() } },
                onCancel: { model.pickerPresented = false },
                onConfirm: { ids in model.addExercises(ids); model.pickerPresented = false })
            .environment(theme)
            .presentationDetents([.large])
            .task { if model.catalog.isEmpty { await model.loadCatalog() } }
        }
        .onChange(of: model.saveState) { _, new in if new == .saved { dismiss() } }
    }

    private var exerciseList: some View {
        VStack(spacing: theme.spacing[2]) {
            ForEach(Array(model.items.enumerated()), id: \.element.id) { idx, item in
                exerciseRow(idx: idx, item: item)
            }
        }
    }

    @ViewBuilder
    private func exerciseRow(idx: Int, item: BuilderExercise) -> some View {
        let badge = badgeText(idx: idx, item: item)
        HStack(spacing: theme.spacing[2]) {
            Image(systemName: "line.3.horizontal").foregroundStyle(theme.inkFaint)
            BuilderBadge(text: badge, tinted: item.supersetGroup != nil)
            Button { model.editingItemID = item.id } label: {
                VStack(alignment: .leading) {
                    Text(item.exercise.name).foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                    Text(item.subLine).foregroundStyle(theme.inkSoft).font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exercise-row-\(item.exercise.name)")
            Spacer()
            if idx < model.items.count - 1 {
                Button { model.toggleLink(at: idx) } label: { Image(systemName: "link") }
                    .foregroundStyle(item.supersetGroup != nil ? theme.accent2 : theme.inkSoft)
                    .accessibilityIdentifier("link-\(idx)")
            }
            Button { model.removeItem(id: item.id) } label: { Image(systemName: "xmark") }
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("remove-\(item.exercise.name)")
        }
        .padding(theme.spacing[3])
        .background(superset(item) ? theme.surface : .clear, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(superset(item) ? theme.accent2 : theme.inkFaint, lineWidth: superset(item) ? 2 : 1))
    }

    private func superset(_ item: BuilderExercise) -> Bool {
        guard let g = item.supersetGroup else { return false }
        return model.items.filter { $0.supersetGroup == g }.count >= 2
    }

    /// Index badge, or A/B/C/D within a superset group.
    private func badgeText(idx: Int, item: BuilderExercise) -> String {
        guard let g = item.supersetGroup else { return "\(idx + 1)" }
        let members = model.items.filter { $0.supersetGroup == g }
        guard members.count >= 2, let pos = members.firstIndex(where: { $0.id == item.id }) else {
            return "\(idx + 1)"
        }
        return String(UnicodeScalar(65 + pos)!)
    }
}

/// Identifiable wrapper so `.sheet(item:)` can drive the Set Editor by id.
private struct IDBox: Identifiable { let id: BuilderExercise.ID }

#Preview {
    NavigationStack {
        WorkoutBuilderView(model: WorkoutBuilderModel(
            catalog: MockExerciseCatalogRepository(), workouts: MockWorkoutRepository()))
    }
    .environment(Theme())
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Builders/WorkoutBuilderView.swift
git commit -m "feat: Workout Builder view — tags, counts, superset rows, sheets"
```

---

## Task 13: Routine Builder view (view assembly)

**Files:**
- Create: `Pulse/Features/Builders/RoutineBuilderView.swift`

- [ ] **Step 1: Write `Pulse/Features/Builders/RoutineBuilderView.swift`**

```swift
import SwiftUI

struct RoutineBuilderView: View {
    @State var model: RoutineBuilderModel
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    init(model: RoutineBuilderModel) { _model = State(initialValue: model) }

    private let dowLetters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        BuilderScaffold(
            eyebrow: "NEW ROUTINE", primaryLabel: "Save routine →",
            saving: model.saveState == .saving,
            onCancel: { dismiss() },
            onPrimary: { Task { await model.save() } }
        ) {
            VStack(alignment: .leading, spacing: theme.spacing[4]) {
                TextField("Routine name", text: $model.name)
                    .font(.system(size: 30, weight: .bold)).foregroundStyle(theme.ink)
                    .accessibilityIdentifier("routine-name")

                Eyebrow(text: "PROGRAM LENGTH")
                HStack(spacing: theme.spacing[3]) {
                    Button { model.decWeeks() } label: { Image(systemName: "minus") }
                        .accessibilityIdentifier("weeks-dec")
                    Text("\(model.weeks)wks")
                        .font(.system(size: 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.ink)
                        .accessibilityIdentifier("weeks-value")
                    Button { model.incWeeks() } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("weeks-inc")
                }
                .foregroundStyle(theme.ink)

                HStack {
                    Eyebrow(text: "WEEKLY SPLIT")
                    Spacer()
                    Eyebrow(text: "\(model.workoutsPerWeek) WORKOUTS / WK")
                }

                dayList

                Button { model.pickerPresented = true } label: {
                    Text("+ ADD / CREATE WORKOUT")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity).padding(theme.spacing[4])
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6])))
                }
                .accessibilityIdentifier("add-workout")

                Button { model.addRestDay() } label: {
                    Text("+ Add rest day")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.inkSoft)
                        .frame(maxWidth: .infinity).padding(theme.spacing[3])
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(theme.inkFaint, style: StrokeStyle(lineWidth: 2, dash: [4])))
                }
                .accessibilityIdentifier("add-rest")

                if case let .error(msg) = model.saveState {
                    Text(msg).foregroundStyle(theme.accent2).accessibilityIdentifier("save-error")
                }
            }
            .padding(.vertical, theme.spacing[3])
        }
        .sheet(isPresented: $model.pickerPresented) {
            WorkoutPickerSheet(
                saved: model.savedWorkouts, loading: model.savedLoading, errorText: model.savedError,
                onRetry: { Task { await model.loadSavedWorkouts() } },
                onCreateNew: {
                    model.addWorkout(BuilderDay(name: "New workout", sub: "Build from scratch"))
                    model.pickerPresented = false
                },
                onPick: { w in
                    model.addWorkout(BuilderDay(name: w.name, sub: w.sub, sourceWorkoutID: w.sourceWorkoutID))
                    model.pickerPresented = false
                })
            .environment(theme)
            .presentationDetents([.large])
            .task { if model.savedWorkouts.isEmpty { await model.loadSavedWorkouts() } }
        }
        .onChange(of: model.saveState) { _, new in if new == .saved { dismiss() } }
    }

    private var dayList: some View {
        VStack(spacing: theme.spacing[2]) {
            ForEach(Array(model.days.enumerated()), id: \.element.id) { idx, day in
                HStack(spacing: theme.spacing[2]) {
                    BuilderBadge(text: idx < dowLetters.count ? dowLetters[idx] : "D", tinted: false)
                    VStack(alignment: .leading) {
                        Text(day.name).foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                        Text("\(dow(idx)) · \(day.sub)").foregroundStyle(theme.inkSoft).font(.system(size: 13))
                    }
                    Spacer()
                    Button { model.removeDay(id: day.id) } label: { Image(systemName: "xmark") }
                        .foregroundStyle(theme.inkSoft)
                        .accessibilityIdentifier("remove-day-\(idx)")
                }
                .padding(theme.spacing[3])
                .opacity(day.isRest ? 0.55 : 1)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.inkFaint, style: StrokeStyle(lineWidth: day.isRest ? 2 : 1,
                                                               dash: day.isRest ? [4] : [])))
            }
        }
    }

    private func dow(_ idx: Int) -> String {
        let names = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
        return idx < names.count ? names[idx] : "DAY \(idx + 1)"
    }
}

#Preview {
    NavigationStack {
        RoutineBuilderView(model: RoutineBuilderModel(
            routines: MockRoutineRepository(), workouts: MockWorkoutRepository()))
    }
    .environment(Theme())
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Builders/RoutineBuilderView.swift
git commit -m "feat: Routine Builder view — week stepper, day split, Workout Picker"
```

---

## Task 14: Folder Builder view (view assembly)

**Files:**
- Create: `Pulse/Features/Builders/FolderBuilderView.swift`

- [ ] **Step 1: Write `Pulse/Features/Builders/FolderBuilderView.swift`**

```swift
import SwiftUI

struct FolderBuilderView: View {
    @State var model: FolderBuilderModel
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    init(model: FolderBuilderModel) { _model = State(initialValue: model) }

    var body: some View {
        BuilderScaffold(
            eyebrow: "NEW FOLDER", primaryLabel: "Create folder →",
            saving: model.saveState == .saving,
            onCancel: { dismiss() },
            onPrimary: { Task { await model.save() } }
        ) {
            VStack(spacing: theme.spacing[5]) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(theme.folderColor(model.colorToken))
                    .frame(width: 120, height: 96)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.ink, lineWidth: 3))
                    .shadow(color: theme.ink, radius: 0, x: 4, y: 4)
                    .accessibilityIdentifier("folder-preview")

                TextField("Folder name", text: $model.name)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(theme.ink)
                    .accessibilityIdentifier("folder-name")

                Eyebrow(text: "FOLDER COLOR")

                HStack(spacing: theme.spacing[3]) {
                    ForEach(FolderColor.allCases, id: \.self) { c in
                        Button { model.select(color: c) } label: {
                            Circle()
                                .fill(theme.folderColor(c))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().stroke(theme.ink,
                                                         lineWidth: model.colorToken == c ? 3 : 0))
                                .overlay(Circle().stroke(theme.accent2,
                                                         lineWidth: model.colorToken == c ? 2 : 0)
                                            .padding(-4))
                        }
                        .accessibilityIdentifier("swatch-\(c.rawValue)")
                    }
                }

                if case let .error(msg) = model.saveState {
                    Text(msg).foregroundStyle(theme.accent2).accessibilityIdentifier("save-error")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.spacing[6])
        }
        .onChange(of: model.saveState) { _, new in if new == .saved { dismiss() } }
    }
}

#Preview {
    NavigationStack {
        FolderBuilderView(model: FolderBuilderModel(folders: MockFolderRepository()))
    }
    .environment(Theme())
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Builders/FolderBuilderView.swift
git commit -m "feat: Folder Builder view — color preview, name, 6-swatch picker"
```

---

## Task 15: Temporary entry points + Theme injection (view assembly)

BAK-10's Create chooser is the real entry point. Until it lands, wire reachable destinations from `LibraryView` so the builders mount, run in the simulator, and are UI-testable. Also ensure `Theme` is injected at the app root.

**Files:**
- Modify: `Pulse/App/PulseApp.swift`
- Modify: `Pulse/Features/Library/LibraryView.swift`

- [ ] **Step 1: Inject `Theme` in `Pulse/App/PulseApp.swift`**

```swift
import SwiftUI

@main
struct PulseApp: App {
    @State private var theme = Theme()
    var body: some Scene {
        WindowGroup {
            AppShell().environment(theme)
        }
    }
}
```

- [ ] **Step 2: Add temporary builder links to `Pulse/Features/Library/LibraryView.swift`**

```swift
import SwiftUI

struct LibraryView: View {
    @Environment(Theme.self) private var theme
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("New workout") {
                    WorkoutBuilderView(model: WorkoutBuilderModel(
                        catalog: MockExerciseCatalogRepository(), workouts: MockWorkoutRepository()))
                }
                .accessibilityIdentifier("open-workout-builder")
                NavigationLink("New routine") {
                    RoutineBuilderView(model: RoutineBuilderModel(
                        routines: MockRoutineRepository(), workouts: MockWorkoutRepository()))
                }
                .accessibilityIdentifier("open-routine-builder")
                NavigationLink("New folder") {
                    FolderBuilderView(model: FolderBuilderModel(folders: MockFolderRepository()))
                }
                .accessibilityIdentifier("open-folder-builder")
            }
            .navigationTitle("Library")
        }
    }
}
```

- [ ] **Step 3: Build to confirm it compiles**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Pulse/App/PulseApp.swift Pulse/Features/Library/LibraryView.swift
git commit -m "feat: inject Theme + temporary Library entry points for builders"
```

---

## Task 16: Acceptance / UI tests (XCUITest)

Covers the spec's acceptance criteria via the temporary Library entry points. Each builder is opened, exercised, and asserted on key elements.

**Files:**
- Create: `PulseUITests/BuildersTests.swift`

- [ ] **Step 1: Write `PulseUITests/BuildersTests.swift`**

```swift
import XCTest

final class BuildersTests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Library"].tap()
        return app
    }

    private func openWorkoutBuilder(_ app: XCUIApplication) {
        app.buttons["open-workout-builder"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-NEW WORKOUT"].waitForExistence(timeout: 5))
    }

    func testWorkoutBuilderShowsHeaderTagsAndSeededRows() { // AC1, AC2
        let app = launch()
        openWorkoutBuilder(app)
        XCTAssertTrue(app.textFields["workout-name"].exists)
        XCTAssertTrue(app.buttons["exercise-row-Flat bench"].exists)
        XCTAssertTrue(app.buttons["exercise-row-Incline press"].exists)
        XCTAssertTrue(app.staticTexts["eyebrow-EXERCISES · 2"].exists)
        XCTAssertTrue(app.staticTexts["eyebrow-9 SETS"].exists)
    }

    func testTappingRowOpensSetEditor() { // AC3, AC6
        let app = launch()
        openWorkoutBuilder(app)
        app.buttons["exercise-row-Flat bench"].tap()
        XCTAssertTrue(app.buttons["set-editor-add"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["set-editor-done"].exists)
        app.buttons["set-editor-add"].tap()        // clone a set
        app.buttons["set-editor-done"].tap()
    }

    func testLinkGroupsTwoRows() { // AC4
        let app = launch()
        openWorkoutBuilder(app)
        app.buttons["link-0"].tap()
        // After linking, the lower row's superset badge "B" exists.
        XCTAssertTrue(app.staticTexts["B"].waitForExistence(timeout: 3))
    }

    func testAddExerciseOpensPickerAndAppends() { // AC5, AC7
        let app = launch()
        openWorkoutBuilder(app)
        app.buttons["add-exercise"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-ADD EXERCISE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["picker-confirm"].exists)
        app.buttons["picker-row-Lat pulldown"].tap()
        app.buttons["picker-confirm"].tap()
        XCTAssertTrue(app.buttons["exercise-row-Lat pulldown"].waitForExistence(timeout: 5))
    }

    func testRoutineBuilderStepperAndSplit() { // AC8, AC9
        let app = launch()
        app.buttons["open-routine-builder"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-NEW ROUTINE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["weeks-value"].exists)
        XCTAssertTrue(app.staticTexts["eyebrow-4 WORKOUTS / WK"].exists)
        app.buttons["weeks-inc"].tap()
        XCTAssertTrue(app.staticTexts["9wks"].exists)
        app.buttons["add-rest"].tap()  // still 4 workouts/wk
        XCTAssertTrue(app.staticTexts["eyebrow-4 WORKOUTS / WK"].exists)
    }

    func testRoutineWorkoutPickerAppendsDay() { // AC10
        let app = launch()
        app.buttons["open-routine-builder"].tap()
        app.buttons["add-workout"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-ADD TO ROUTINE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["wpicker-create-new"].exists)
        app.buttons["wpicker-row-Arms · finisher"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-5 WORKOUTS / WK"].waitForExistence(timeout: 5))
    }

    func testFolderBuilderSwatchSelection() { // AC11
        let app = launch()
        app.buttons["open-folder-builder"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-NEW FOLDER"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["folder-preview"].exists)
        XCTAssertTrue(app.textFields["folder-name"].exists)
        app.buttons["swatch-purple"].tap()
        XCTAssertTrue(app.buttons["swatch-purple"].exists)
    }

    func testCancelPopsBackToLibrary() { // AC12
        let app = launch()
        app.buttons["open-folder-builder"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-NEW FOLDER"].waitForExistence(timeout: 5))
        app.buttons["builder-cancel"].tap()
        XCTAssertTrue(app.buttons["open-folder-builder"].waitForExistence(timeout: 5))
    }

    func testSavePopsBackToLibrary() { // AC12
        let app = launch()
        app.buttons["open-folder-builder"].tap()
        XCTAssertTrue(app.staticTexts["eyebrow-NEW FOLDER"].waitForExistence(timeout: 5))
        app.buttons["builder-primary"].tap()
        XCTAssertTrue(app.buttons["open-folder-builder"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 2: Run the UI tests**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS — all `BuildersTests` plus the existing unit suites green.

- [ ] **Step 3: Commit**

```bash
git add PulseUITests/BuildersTests.swift
git commit -m "test: acceptance UI tests for the three builders + sheets"
```

---

## Task 17: Theme parity check + final full test run

- [ ] **Step 1: Verify both palettes render via the previews**

Open `Pulse/Features/Builders/WorkoutBuilderView.swift`, `RoutineBuilderView.swift`, and `FolderBuilderView.swift` previews in Xcode and toggle the injected `Theme()`'s palette between `.coastal` and `.mint` (edit the preview to `Theme(); $0.palette = .mint`). Confirm chips, badges, superset cards, swatches, and the folder preview re-skin (except the six folder swatches, which are fixed brand colors by design). No hardcoded `Color(...)` literals remain — every color reads a `Theme` token. (AC13)

- [ ] **Step 2: Run the complete suite once more**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test
```
Expected: `TEST SUCCEEDED` — `BuilderModelsTests`, `BuilderMocksTests`, `WorkoutBuilderModelTests`, `RoutineBuilderModelTests`, `FolderBuilderModelTests`, `BuildersTests`, plus the pre-existing `PaletteTests` / `WorkoutModelsTests` all green.

- [ ] **Step 3: Open the PR**

Run:
```bash
git push -u origin feature/BAK-18-builders
gh pr create --fill --base main
```
Then verify CI is green and request review (`code-reviewer` + `/security-review`), per the workflow gates in `CLAUDE.md`.

---

## Self-Review notes

- **Spec coverage:** AC1–AC2 (Workout Builder header/tags/rows) Tasks 5, 12, 16; AC3/AC6 (Set Editor) Tasks 5, 9, 16; AC4 (supersets) Tasks 5, 12, 16; AC5/AC7 (Exercise Picker) Tasks 5, 10, 16; AC8–AC9 (Routine Builder) Tasks 6, 13, 16; AC10 (Workout Picker) Tasks 6, 11, 16; AC11 (Folder) Tasks 7, 14, 16; AC12 (save/cancel) Tasks 5–7, 12–14, 16; AC13 (Theme parity) Tasks 4, 8, 17.
- **TDD vs view assembly:** all logic (draft structs, mocks, three models) is strict TDD (failing test → run → impl → run → commit). Pure view assembly (scaffold, three sheets, three builder screens) uses concrete SwiftUI + `#Preview` + XCUITest, per policy.
- **Product decisions honored:** kg-only (no weight in Set Editor), inert `⋯`/search, single-select PUSH/PULL/LEGS with inert `+ TAG`, folder swatches tokenized via `Theme.folderColor` and fixed across palettes, `+ Add set` clones as `working`, degenerate saves permitted, create-only, no reorder, no in-builder variation switcher.
- **Repository discipline:** models touch storage only through the four protocols; mocks are in `Core/Data/Mocks`; no Supabase calls. Reconciled with BAK-6 on the same protocol surface.
- **Open items for BAK-6/BAK-10:** real persistence target (folder placement of saved workouts/routines), the Create chooser as the production entry point (Task 15 wiring is temporary), and reconciling `WorkoutSummary`/`MuscleGroupCatalog` shapes with the shared catalog.
