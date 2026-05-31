# Exercise Detail (BAK-11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the read-only Exercise Detail screen (`exdetail:<id>`), reached by tapping an exercise row in Library → Exercises. It shows a per-exercise progress view: an all-time personal-best top set, a 4-session volume trend mini-chart, and the last four logged sessions. UI-first: the screen binds to repository protocols backed by in-memory mocks with sample data; no real Supabase wiring.

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. The screen is a `View` + an `@Observable` `ExerciseDetailModel` in `Pulse/Features/ExerciseDetail/`. The model fetches through an `ExerciseRepository` protocol (data access never touches Supabase directly); an in-memory `MockExerciseRepository` seeds the catalog and per-exercise session history. All color/spacing/radii/type come from `Theme` tokens. The Library Exercises catalog gets a minimal list that pushes `ExerciseDetailView(exerciseID:)` onto a `NavigationStack`.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency (`async`/`await`), XCTest + XCUITest, XcodeGen. Test destination: `platform=iOS Simulator,name=iPhone 17`.

**Product decisions applied (authoritative — `docs/superpowers/specs/2026-05-31-product-decisions.md`):**
- **Weights are kilograms only (v1).** The prototype's "lbs"/"lb" copy is replaced with "KG"/"kg". All weight formatting goes through one helper (`WeightFormat`) so a future units toggle is localized. PB card bottom label is `kg ·\ntop set.`
- **PR = estimated 1RM via Epley** (`1RM = weight × (1 + reps/30)`, warmups excluded). The PB shown here is the top-set est-1RM derived from session history, not an ad-hoc `top`/`pr` flag on `Exercise`. The eyebrow shows `PERSONAL BEST · TRACKED` when the exercise's catalog metadata marks it a tracked PR lift.
- **Calendar/timezone:** date bucketing/formatting uses `Calendar.current` in the device-local timezone.
- **`⋯` overflow:** inert placeholder (no actions wired).
- **Open Q1 (variation filtering):** for v1 the variation pill is **cosmetic** — selecting it updates `selectedVariationIndex` only and does not re-query history. (Spec out-of-scope: "Per-variation PR tracking semantics beyond selecting a pill.")
- **Open Q6 (window size):** the window is "up to 4" — show fewer rows/bars when fewer sessions exist; cap at 4.

**Prerequisites (must be built first):**
- **Design System (BAK-7)** — `Theme` tokens, fonts (Hanken Grotesk / Oswald / Geist Mono), eyebrow/lockup/row styles. `Theme`/`Palette` already exist in `Pulse/Core/DesignSystem/`.
- **Data layer (BAK-6)** — repository protocols + in-memory mocks and the domain-model additions this screen needs. BAK-6 is **not yet merged**, so this plan defines the `ExerciseRepository` protocol, the `ExerciseSessionSummary`/`PersonalBest` types, the `MockExerciseRepository`, the analytics helper, and the `Exercise` metadata additions itself, behind the same protocol names BAK-6 will adopt. When BAK-6 lands, these are reconciled (same protocol surface).

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

- [ ] **Step 0b: Confirm `Theme`/`Palette` and `Exercise` exist**

Run: `ls Pulse/Core/DesignSystem/Theme.swift Pulse/Core/DesignSystem/Palette.swift Pulse/Core/Models/WorkoutModels.swift`
Expected: all three paths print (no "No such file").

- [ ] **Step 0c: Branch**

Run: `git checkout -b feature/BAK-11-exercise-detail`
Expected: switched to a new branch.

---

## Task 1: Domain-model additions — catalog metadata + est-1RM on `Exercise` (TDD)

The catalog exposes equipment and a "tracked PR" flag (design `EXERCISE_CATALOG`). The current `Exercise` has neither. Add `equipment` and `tracksPR` to `Exercise`. Per the product decision, the personal best itself is **derived** (est-1RM from history), not stored on `Exercise` — so we add no `top` field. We also add the Epley helper here because the model and the mock both need it.

**Files:**
- Modify: `Pulse/Core/Models/WorkoutModels.swift`
- Create: `Pulse/Core/Models/Analytics.swift`
- Create: `PulseTests/AnalyticsTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/AnalyticsTests.swift`**

```swift
import XCTest
@testable import Pulse

final class AnalyticsTests: XCTestCase {
    func testEpleyOneRepMax() {
        // 100kg × 10 reps → 100 × (1 + 10/30) = 133.33…
        XCTAssertEqual(Analytics.epleyOneRepMax(weight: 100, reps: 10), 133.333, accuracy: 0.01)
    }

    func testEpleyAtOneRepIsTheWeight() {
        XCTAssertEqual(Analytics.epleyOneRepMax(weight: 140, reps: 1), 140, accuracy: 0.0001)
    }

    func testTopSetEstOneRepMaxExcludesWarmups() {
        let sets = [
            SessionSet(reps: 12, weight: 40, type: .warmup),   // excluded
            SessionSet(reps: 8,  weight: 100, type: .working),  // 100×(1+8/30)=126.67
            SessionSet(reps: 5,  weight: 110, type: .working),  // 110×(1+5/30)=128.33 ← max
        ]
        XCTAssertEqual(Analytics.topSetEstOneRepMax(sets), 128.333, accuracy: 0.01)
    }

    func testTopSetEstOneRepMaxIsNilWhenNoWorkingSets() {
        let sets = [SessionSet(reps: 10, weight: 20, type: .warmup)]
        XCTAssertNil(Analytics.topSetEstOneRepMax(sets))
    }

    func testTopWeightOfWorkingSets() {
        let sets = [
            SessionSet(reps: 12, weight: 200, type: .warmup), // excluded despite being heaviest
            SessionSet(reps: 8,  weight: 100, type: .working),
            SessionSet(reps: 5,  weight: 110, type: .working),
        ]
        XCTAssertEqual(Analytics.topWorkingWeight(sets), 110)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `Analytics` is undefined (compile error).

- [ ] **Step 3: Write `Pulse/Core/Models/Analytics.swift`**

```swift
import Foundation

/// Derived training analytics. Centralized so PR/est-1RM rules live in one place
/// (product decision: PR = Epley est-1RM, warmups excluded; calendar = local tz).
enum Analytics {
    /// Epley estimated one-rep max: weight × (1 + reps/30).
    static func epleyOneRepMax(weight: Double, reps: Int) -> Double {
        weight * (1 + Double(reps) / 30)
    }

    /// Working/AMRAP sets only (warmups excluded).
    private static func scoringSets(_ sets: [SessionSet]) -> [SessionSet] {
        sets.filter { $0.type == .working || $0.type == .amrap }
    }

    /// Max est-1RM across the session's working/AMRAP sets; nil if none.
    static func topSetEstOneRepMax(_ sets: [SessionSet]) -> Double? {
        scoringSets(sets)
            .map { epleyOneRepMax(weight: $0.weight, reps: $0.reps) }
            .max()
    }

    /// Heaviest working/AMRAP set weight; nil if none.
    static func topWorkingWeight(_ sets: [SessionSet]) -> Double? {
        scoringSets(sets).map(\.weight).max()
    }
}
```

- [ ] **Step 4: Add `equipment` + `tracksPR` to `Exercise` in `Pulse/Core/Models/WorkoutModels.swift`**

Replace the `Exercise` struct (currently lines ~20-26) with:

```swift
struct Exercise: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var muscleGroup: String
    var equipment: String          // e.g. "MACHINE", "BARBELL", "BODYWEIGHT"
    var variations: [Variation]
    var defaultVariationID: Variation.ID?
    var tracksPR: Bool = false     // catalog marks certain lifts as tracked PR lifts
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (AnalyticsTests green; WorkoutModelsTests still green — they construct `Exercise` only via mocks added later, no existing test constructs `Exercise`). If `WorkoutModelsTests` references `Exercise`, update those call sites to pass `equipment:`.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/Models/Analytics.swift Pulse/Core/Models/WorkoutModels.swift PulseTests/AnalyticsTests.swift
git commit -m "feat: Epley est-1RM analytics helper and Exercise catalog metadata"
```

---

## Task 2: Weight formatting helper (kg-only, single source) (TDD)

Product decision: kg only for v1, but keep formatting in one helper so a future units toggle is localized.

**Files:**
- Create: `Pulse/Core/DesignSystem/WeightFormat.swift`
- Create: `PulseTests/WeightFormatTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/WeightFormatTests.swift`**

```swift
import XCTest
@testable import Pulse

final class WeightFormatTests: XCTestCase {
    func testWholeKgHasNoDecimals() {
        XCTAssertEqual(WeightFormat.kg(150), "150")
    }

    func testHalfKgKeepsOneDecimal() {
        XCTAssertEqual(WeightFormat.kg(67.5), "67.5")
    }

    func testZeroOrLessRendersBodyweight() {
        XCTAssertEqual(WeightFormat.weightOrBodyweight(0), "bodyweight")
        XCTAssertEqual(WeightFormat.weightOrBodyweight(-5), "bodyweight")
    }

    func testPositiveRendersKgWithUnit() {
        XCTAssertEqual(WeightFormat.weightOrBodyweight(100), "100 kg")
    }

    func testVolumeThousandsAbbreviation() {
        XCTAssertEqual(WeightFormat.volume(3600), "3.6k")
        XCTAssertEqual(WeightFormat.volume(0), "—")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `WeightFormat` undefined.

- [ ] **Step 3: Write `Pulse/Core/DesignSystem/WeightFormat.swift`**

```swift
import Foundation

/// Single source of truth for weight/volume display strings. v1 is kg-only;
/// a units toggle (later feature) would change only this type.
enum WeightFormat {
    /// Bare kg number, no unit. Whole numbers drop the decimal; halves keep one.
    static func kg(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    /// "100 kg" for positive weight, "bodyweight" for zero/negative.
    static func weightOrBodyweight(_ value: Double) -> String {
        value > 0 ? "\(kg(value)) kg" : "bodyweight"
    }

    /// Total volume abbreviated to thousands ("3.6k"); "—" when zero.
    static func volume(_ value: Double) -> String {
        value > 0 ? String(format: "%.1fk", value / 1000) : "—"
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Core/DesignSystem/WeightFormat.swift PulseTests/WeightFormatTests.swift
git commit -m "feat: kg-only weight/volume formatting helper"
```

---

## Task 3: `ExerciseRepository` protocol + summary/PB types (TDD)

Defines the data-access surface the screen binds to (coordinated with BAK-6). `ExerciseSessionSummary` is the view-facing shape; `PersonalBest` carries the top weight + date for the PB card.

**Files:**
- Create: `Pulse/Core/Data/ExerciseRepository.swift`
- Create: `PulseTests/ExerciseRepositoryTypeTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/ExerciseRepositoryTypeTests.swift`**

```swift
import XCTest
@testable import Pulse

final class ExerciseRepositoryTypeTests: XCTestCase {
    func testSessionSummaryHoldsDisplayFields() {
        let s = ExerciseSessionSummary(
            date: Date(timeIntervalSince1970: 0),
            repLine: "12 · 10 · 8",
            topWeight: 110,
            volume: 3600
        )
        XCTAssertEqual(s.repLine, "12 · 10 · 8")
        XCTAssertEqual(s.topWeight, 110)
        XCTAssertEqual(s.volume, 3600)
    }

    func testPersonalBestHoldsWeightAndDate() {
        let pb = PersonalBest(topWeight: 150, date: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(pb.topWeight, 150)
        XCTAssertEqual(pb.date, Date(timeIntervalSince1970: 0))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `ExerciseSessionSummary` / `PersonalBest` undefined.

- [ ] **Step 3: Write `Pulse/Core/Data/ExerciseRepository.swift`**

```swift
import Foundation

/// One logged session, reduced to what Exercise Detail displays.
/// `date` is an absolute instant; formatting to "FRI · MAY 23" is the view's job.
struct ExerciseSessionSummary: Equatable, Identifiable {
    var id = UUID()
    var date: Date
    var repLine: String      // e.g. "12 · 10 · 8"
    var topWeight: Double    // heaviest working set, kg (0 = bodyweight)
    var volume: Double       // total working volume, kg·reps
}

/// All-time personal best top set for an exercise (nil when none / bodyweight).
struct PersonalBest: Equatable {
    var topWeight: Double
    var date: Date
}

/// Read access to the exercise catalog and per-exercise logged history.
/// Views/models depend on this protocol only — never on a concrete backend.
protocol ExerciseRepository {
    func exercise(id: Exercise.ID) async throws -> Exercise
    func history(exerciseID: Exercise.ID,
                 variationID: Variation.ID?,
                 limit: Int) async throws -> [ExerciseSessionSummary]
}

/// Error surfaced when a catalog id is not found.
struct ExerciseNotFound: Error, Equatable {
    let id: Exercise.ID
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Core/Data/ExerciseRepository.swift PulseTests/ExerciseRepositoryTypeTests.swift
git commit -m "feat: ExerciseRepository protocol + session-summary/PB types"
```

---

## Task 4: `MockExerciseRepository` — in-memory catalog + sample history (TDD)

Seeds the catalog from the design `EXERCISE_CATALOG` and supplies realistic 4-entry history per exercise so the screen renders without Supabase. Includes a failure-injection switch for the error-state test, and an empty-history exercise for the empty-state test.

**Files:**
- Create: `Pulse/Core/Data/Mock/MockExerciseRepository.swift`
- Create: `PulseTests/MockExerciseRepositoryTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/MockExerciseRepositoryTests.swift`**

```swift
import XCTest
@testable import Pulse

final class MockExerciseRepositoryTests: XCTestCase {
    func testCatalogContainsKnownExercises() async throws {
        let repo = MockExerciseRepository()
        let flat = try await repo.exercise(id: MockExerciseRepository.flatID)
        XCTAssertEqual(flat.name, "Flat Machine Chest Press")
        XCTAssertEqual(flat.equipment, "MACHINE")
        XCTAssertEqual(flat.variations.count, 3)

        let bench = try await repo.exercise(id: MockExerciseRepository.benchID)
        XCTAssertTrue(bench.tracksPR)
    }

    func testUnknownIdThrowsNotFound() async {
        let repo = MockExerciseRepository()
        let missing = UUID()
        do {
            _ = try await repo.exercise(id: missing)
            XCTFail("expected throw")
        } catch let error as ExerciseNotFound {
            XCTAssertEqual(error.id, missing)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testHistoryReturnsMostRecentFirstCappedAtLimit() async throws {
        let repo = MockExerciseRepository()
        let hist = try await repo.history(exerciseID: MockExerciseRepository.flatID,
                                          variationID: nil, limit: 4)
        XCTAssertEqual(hist.count, 4)
        XCTAssertTrue(hist[0].date > hist[1].date, "most recent first")
        XCTAssertTrue(hist[0].topWeight > 0)
    }

    func testEmptyHistoryExerciseReturnsNoSessions() async throws {
        let repo = MockExerciseRepository()
        let hist = try await repo.history(exerciseID: MockExerciseRepository.emptyID,
                                          variationID: nil, limit: 4)
        XCTAssertTrue(hist.isEmpty)
    }

    func testFailureModeThrows() async {
        let repo = MockExerciseRepository(failing: true)
        do {
            _ = try await repo.history(exerciseID: MockExerciseRepository.flatID,
                                       variationID: nil, limit: 4)
            XCTFail("expected throw")
        } catch {
            // expected
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `MockExerciseRepository` undefined.

- [ ] **Step 3: Write `Pulse/Core/Data/Mock/MockExerciseRepository.swift`**

```swift
import Foundation

/// In-memory ExerciseRepository seeded from the design catalog. Used UI-first
/// until BAK-6's live Supabase-backed implementation lands behind this protocol.
final class MockExerciseRepository: ExerciseRepository {
    private let failing: Bool
    private let catalog: [Exercise]
    private let histories: [Exercise.ID: [ExerciseSessionSummary]]

    // Stable ids so tests + previews reference the same exercises.
    static let flatID = UUID()
    static let benchID = UUID()
    static let pushupID = UUID()   // bodyweight, top 0
    static let emptyID = UUID()    // exists but no logged history

    init(failing: Bool = false) {
        self.failing = failing

        let flat = Exercise(
            id: Self.flatID, name: "Flat Machine Chest Press",
            muscleGroup: "Chest", equipment: "MACHINE",
            variations: [Variation(name: "D-bar"),
                         Variation(name: "Neutral"),
                         Variation(name: "Wide")],
            defaultVariationID: nil, tracksPR: false)

        let bench = Exercise(
            id: Self.benchID, name: "Barbell Bench Press",
            muscleGroup: "Chest", equipment: "BARBELL",
            variations: [], defaultVariationID: nil, tracksPR: true)

        let pushup = Exercise(
            id: Self.pushupID, name: "Tricep Push Up",
            muscleGroup: "Triceps", equipment: "BODYWEIGHT",
            variations: [], defaultVariationID: nil, tracksPR: false)

        let empty = Exercise(
            id: Self.emptyID, name: "Incline DB Press",
            muscleGroup: "Chest", equipment: "DUMBBELL",
            variations: [], defaultVariationID: nil, tracksPR: false)

        self.catalog = [flat, bench, pushup, empty]

        // Four sessions, most-recent first, descending top weight (trend).
        func day(_ ago: Int) -> Date {
            Calendar.current.date(byAdding: .day, value: -ago, to: Date())!
        }
        func sessions(top: Double, line: String, reps: [Int]) -> [ExerciseSessionSummary] {
            [0, 4, 7, 11].enumerated().map { i, ago in
                let wt = max(0, top - Double(i) * 5)
                let vol = wt > 0 ? reps.reduce(0) { $0 + Double($1) * wt } : 0
                return ExerciseSessionSummary(date: day(ago), repLine: line,
                                              topWeight: wt, volume: vol)
            }
        }

        self.histories = [
            Self.flatID:   sessions(top: 150, line: "12 · 10 · 8", reps: [12, 10, 8]),
            Self.benchID:  sessions(top: 110, line: "5 · 5 · 5",   reps: [5, 5, 5]),
            Self.pushupID: sessions(top: 0,   line: "20 · 18 · 15", reps: [20, 18, 15]),
            Self.emptyID:  [],
        ]
    }

    func exercise(id: Exercise.ID) async throws -> Exercise {
        if failing { throw URLError(.timedOut) }
        guard let found = catalog.first(where: { $0.id == id }) else {
            throw ExerciseNotFound(id: id)
        }
        return found
    }

    func history(exerciseID: Exercise.ID,
                 variationID: Variation.ID?,
                 limit: Int) async throws -> [ExerciseSessionSummary] {
        if failing { throw URLError(.timedOut) }
        let all = histories[exerciseID] ?? []
        return Array(all.sorted { $0.date > $1.date }.prefix(limit))
    }

    /// All catalog exercises (for the Library list).
    func all() -> [Exercise] { catalog }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (5 mock tests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Core/Data/Mock/MockExerciseRepository.swift PulseTests/MockExerciseRepositoryTests.swift
git commit -m "feat: in-memory MockExerciseRepository with seeded catalog + history"
```

---

## Task 5: `ExerciseDetailModel` — load, derive, select (TDD)

The `@Observable` model: fetches exercise + history, derives PB (Epley top set), variation options, chart scaling, and load phase.

**Files:**
- Create: `Pulse/Features/ExerciseDetail/ExerciseDetailModel.swift`
- Create: `PulseTests/ExerciseDetail/ExerciseDetailModelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/ExerciseDetail/ExerciseDetailModelTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class ExerciseDetailModelTests: XCTestCase {
    private func model(_ id: Exercise.ID, failing: Bool = false) -> ExerciseDetailModel {
        ExerciseDetailModel(exerciseID: id,
                            repository: MockExerciseRepository(failing: failing))
    }

    func testLoadPopulatesAndSetsLoaded() async {
        let m = model(MockExerciseRepository.flatID)
        await m.load()
        XCTAssertEqual(m.exercise?.name, "Flat Machine Chest Press")
        XCTAssertEqual(m.sessions.count, 4)
        guard case .loaded = m.phase else { return XCTFail("expected .loaded") }
    }

    func testSessionsAreMostRecentFirstAndCapped() async {
        let m = model(MockExerciseRepository.flatID)
        await m.load()
        XCTAssertLessThanOrEqual(m.sessions.count, 4)
        XCTAssertTrue(m.sessions[0].date > m.sessions[1].date)
    }

    func testShowsPersonalBestTrueWhenTopWeightPositive() async {
        let m = model(MockExerciseRepository.flatID)
        await m.load()
        XCTAssertTrue(m.showsPersonalBest)
        XCTAssertEqual(m.personalBest?.topWeight, 150)
    }

    func testShowsPersonalBestFalseForBodyweight() async {
        let m = model(MockExerciseRepository.pushupID)
        await m.load()
        XCTAssertFalse(m.showsPersonalBest)
        XCTAssertNil(m.personalBest)
    }

    func testVariationsPrependAllAndPillVisibility() async {
        let multi = model(MockExerciseRepository.flatID)
        await multi.load()
        XCTAssertEqual(multi.variations.map(\.label), ["All", "D-bar", "Neutral", "Wide"])
        XCTAssertTrue(multi.showsVariationPills)
        XCTAssertEqual(multi.selectedVariationIndex, 1) // first named variation

        let none = model(MockExerciseRepository.benchID)
        await none.load()
        XCTAssertEqual(none.variations.map(\.label), ["All"])
        XCTAssertFalse(none.showsVariationPills)
        XCTAssertEqual(none.selectedVariationIndex, 0)  // "All"
    }

    func testMaxVolumeIsNeverZero() async {
        let m = model(MockExerciseRepository.pushupID) // all volumes 0
        await m.load()
        XCTAssertGreaterThan(m.maxVolume, 0)
    }

    func testEmptyHistorySetsEmptyPhase() async {
        let m = model(MockExerciseRepository.emptyID)
        await m.load()
        XCTAssertTrue(m.sessions.isEmpty)
        guard case .empty = m.phase else { return XCTFail("expected .empty") }
    }

    func testRepositoryFailureSetsErrorPhaseAndNoStaleData() async {
        let m = model(MockExerciseRepository.flatID, failing: true)
        await m.load()
        guard case .error = m.phase else { return XCTFail("expected .error") }
        XCTAssertTrue(m.sessions.isEmpty)
        XCTAssertNil(m.personalBest)
    }

    func testSelectVariationUpdatesIndexOnly() async {
        let m = model(MockExerciseRepository.flatID)
        await m.load()
        let before = m.sessions
        m.selectVariation(2)
        XCTAssertEqual(m.selectedVariationIndex, 2)
        XCTAssertEqual(m.sessions, before) // cosmetic for v1 (does not re-query)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `ExerciseDetailModel` / `VariationOption` undefined.

- [ ] **Step 3: Write `Pulse/Features/ExerciseDetail/ExerciseDetailModel.swift`**

```swift
import Foundation
import Observation

/// A selectable variation pill ("All" + named variations).
struct VariationOption: Equatable, Identifiable {
    var id = UUID()
    var label: String
    var variationID: Variation.ID?   // nil for the "All" pill
}

enum LoadPhase: Equatable {
    case loading, loaded, empty
    case error(String)
}

@MainActor
@Observable
final class ExerciseDetailModel {
    let exerciseID: Exercise.ID
    private let repository: ExerciseRepository
    private let window = 4

    var phase: LoadPhase = .loading
    var exercise: Exercise?
    var personalBest: PersonalBest?
    var sessions: [ExerciseSessionSummary] = []
    var variations: [VariationOption] = [VariationOption(label: "All", variationID: nil)]
    var selectedVariationIndex = 0

    init(exerciseID: Exercise.ID, repository: ExerciseRepository) {
        self.exerciseID = exerciseID
        self.repository = repository
    }

    var showsVariationPills: Bool { variations.count > 1 }
    var showsPersonalBest: Bool { personalBest != nil }

    /// Chart scaling denominator — never zero (avoids invisible / div-by-zero bars).
    var maxVolume: Double { max(1, sessions.map(\.volume).max() ?? 0) }

    func load() async {
        phase = .loading
        do {
            let ex = try await repository.exercise(id: exerciseID)
            self.exercise = ex
            self.variations = [VariationOption(label: "All", variationID: nil)]
                + ex.variations.map { VariationOption(label: $0.name, variationID: $0.id) }
            self.selectedVariationIndex = ex.variations.isEmpty ? 0 : 1

            let hist = try await repository.history(exerciseID: exerciseID,
                                                    variationID: nil, limit: window)
            self.sessions = hist
            self.personalBest = Self.derivePB(from: hist)

            phase = hist.isEmpty ? .empty : .loaded
        } catch {
            // No stale data: clear anything partially set.
            self.sessions = []
            self.personalBest = nil
            phase = .error("Couldn’t load this exercise. Pull to retry.")
        }
    }

    /// v1: cosmetic — updates the selection without re-querying history.
    func selectVariation(_ index: Int) {
        guard variations.indices.contains(index) else { return }
        selectedVariationIndex = index
    }

    /// PB = the heaviest top-set weight across sessions, with its session date.
    /// nil when every session is bodyweight (top weight 0).
    private static func derivePB(from sessions: [ExerciseSessionSummary]) -> PersonalBest? {
        guard let best = sessions.filter({ $0.topWeight > 0 }).max(by: { $0.topWeight < $1.topWeight })
        else { return nil }
        return PersonalBest(topWeight: best.topWeight, date: best.date)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (all ExerciseDetailModelTests green).

- [ ] **Step 5: Add `PulseTests/ExerciseDetail/` to the test target sources**

The test target globs `PulseTests` recursively (XcodeGen `sources: [PulseTests]`), so the new subfolder is picked up. Regenerate to be sure.

Run: `xcodegen generate`
Expected: clean regeneration; no `project.yml` edit needed.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Features/ExerciseDetail/ExerciseDetailModel.swift PulseTests/ExerciseDetail/ExerciseDetailModelTests.swift
git commit -m "feat: ExerciseDetailModel (load, derive PB, variations, chart scaling)"
```

---

## Task 6: Date-label helper for session rows (TDD)

Rows show dates like `FRI · MAY 23`; the PB card top label uses the weekday segment. Centralize the format (local timezone) so the view stays declarative and the format is testable.

**Files:**
- Create: `Pulse/Features/ExerciseDetail/SessionDateLabel.swift`
- Create: `PulseTests/ExerciseDetail/SessionDateLabelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/ExerciseDetail/SessionDateLabelTests.swift`**

```swift
import XCTest
@testable import Pulse

final class SessionDateLabelTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d
        return Calendar.current.date(from: c)!
    }

    func testRowLabelIsWeekdayDotMonthDay() {
        // 2026-05-22 is a Friday.
        XCTAssertEqual(SessionDateLabel.row(date(2026, 5, 22)), "FRI · MAY 22")
    }

    func testWeekdayOnlySegment() {
        XCTAssertEqual(SessionDateLabel.weekday(date(2026, 5, 22)), "FRI")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `SessionDateLabel` undefined.

- [ ] **Step 3: Write `Pulse/Features/ExerciseDetail/SessionDateLabel.swift`**

```swift
import Foundation

/// Uppercase session-date labels in the device-local calendar/timezone.
enum SessionDateLabel {
    private static func formatted(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f.string(from: date).uppercased()
    }

    /// "FRI · MAY 22"
    static func row(_ date: Date) -> String { formatted(date, "EEE '·' MMM d") }

    /// "FRI"
    static func weekday(_ date: Date) -> String { formatted(date, "EEE") }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/ExerciseDetail/SessionDateLabel.swift PulseTests/ExerciseDetail/SessionDateLabelTests.swift
git commit -m "feat: local-timezone session date-label helper"
```

---

## Task 7: `ExerciseDetailView` — screen assembly (View: preview + UI test)

Pure SwiftUI assembly against `Theme` tokens. Validated by `#Preview` + the UI test in Task 9. Structure mirrors the prototype `ExerciseDetailScreen`: top bar, H1, variation pills, PB card, volume mini-chart, last-4 sessions list, plus loading/empty/error states. Identifiers are set for the UI test.

**Files:**
- Create: `Pulse/Features/ExerciseDetail/ExerciseDetailView.swift`

- [ ] **Step 1: Write `Pulse/Features/ExerciseDetail/ExerciseDetailView.swift`**

```swift
import SwiftUI

struct ExerciseDetailView: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var model: ExerciseDetailModel

    init(exerciseID: Exercise.ID, repository: ExerciseRepository) {
        _model = State(initialValue: ExerciseDetailModel(exerciseID: exerciseID,
                                                          repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing[1]) {
                header
                if model.showsVariationPills { variationPills }
                content
            }
            .padding(.horizontal, theme.spacing[5])
            .padding(.top, theme.spacing[3])
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .tint(theme.ink)
                    .accessibilityIdentifier("exdetail-back")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "ellipsis")
                    .foregroundStyle(theme.inkSoft)        // inert per product decision
                    .accessibilityIdentifier("exdetail-overflow")
            }
        }
        .task { await model.load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing[0]) {
            Text(eyebrowText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("exdetail-eyebrow")
            Text("\(model.exercise?.name ?? "Exercise").")
                .font(.system(size: 28, weight: .heavy))
                .lineSpacing(-2)
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("exdetail-title")
        }
    }

    private var eyebrowText: String {
        guard let ex = model.exercise else { return "" }
        return "\(ex.muscleGroup.uppercased()) · \(ex.equipment)"
    }

    // MARK: - Variation pills

    private var variationPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing[1]) {
                ForEach(Array(model.variations.enumerated()), id: \.element.id) { i, v in
                    let selected = i == model.selectedVariationIndex
                    Button { model.selectVariation(i) } label: {
                        Text(v.label.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                            .padding(.horizontal, theme.spacing[3])
                            .padding(.vertical, theme.spacing[1])
                            .background(selected ? theme.accent : .clear)
                            .foregroundStyle(selected ? theme.onAccent : theme.inkSoft)
                            .overlay(
                                RoundedRectangle(cornerRadius: theme.radiusPill)
                                    .stroke(selected ? .clear : theme.inkFaint, lineWidth: 1.5))
                            .clipShape(RoundedRectangle(cornerRadius: theme.radiusPill))
                    }
                }
            }
        }
        .accessibilityIdentifier("exdetail-variation-pills")
    }

    // MARK: - Content (phase switch)

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("exdetail-loading")
        case .error(let message):
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(theme.inkSoft)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, theme.spacing[5])
                .accessibilityIdentifier("exdetail-error")
        case .empty:
            if model.showsPersonalBest { personalBestCard }
            emptyState
        case .loaded:
            if model.showsPersonalBest { personalBestCard }
            volumeChart
            sessionsList
        }
    }

    private var emptyState: some View {
        Text("No sessions logged yet")
            .font(.system(size: 14))
            .foregroundStyle(theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, theme.spacing[5])
            .accessibilityIdentifier("exdetail-empty")
    }

    // MARK: - Personal Best

    @ViewBuilder private var personalBestCard: some View {
        if let pb = model.personalBest {
            VStack(alignment: .leading, spacing: theme.spacing[1]) {
                Text(model.exercise?.tracksPR == true ? "PERSONAL BEST · TRACKED" : "PERSONAL BEST")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                HStack(alignment: .firstTextBaseline, spacing: theme.spacing[2]) {
                    Text(SessionDateLabel.weekday(pb.date))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.onAccent)            // never accent2 on accent card
                    Spacer()
                }
                Text(WeightFormat.kg(pb.topWeight))
                    .font(.custom("Oswald", size: 72))
                    .foregroundStyle(theme.onAccent)
                Text("kg ·\ntop set.")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.onAccent.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 14, leading: 16, bottom: 16, trailing: 16))
            .background(theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard))
            .accessibilityIdentifier("exdetail-pb-card")
        }
    }

    // MARK: - Volume chart

    private var volumeChart: some View {
        VStack(alignment: .leading, spacing: theme.spacing[1]) {
            eyebrow("VOLUME · LAST 4")
            HStack(alignment: .bottom, spacing: theme.spacing[1]) {
                let ordered = Array(model.sessions.reversed()) // oldest → newest
                ForEach(Array(ordered.enumerated()), id: \.element.id) { i, s in
                    let isLast = i == ordered.count - 1
                    let h = max(8, s.volume / model.maxVolume * 48)
                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                        .fill(isLast ? theme.accent2 : theme.accent.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: h)
                }
            }
            .frame(height: 56, alignment: .bottom)
            .accessibilityIdentifier("exdetail-volume-chart")
        }
    }

    // MARK: - Sessions list

    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: theme.spacing[1]) {
            eyebrow("LAST 4 SESSIONS")
            ForEach(Array(model.sessions.enumerated()), id: \.element.id) { i, s in
                sessionRow(s, first: i == 0)
            }
        }
        .accessibilityIdentifier("exdetail-sessions-list")
    }

    private func sessionRow(_ s: ExerciseSessionSummary, first: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SessionDateLabel.row(s.date))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.ink)
                Text("\(s.repLine) REPS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.inkSoft)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(s.topWeight > 0 ? WeightFormat.kg(s.topWeight) : "BW")
                    .font(.custom("Oswald", size: 18))
                    .foregroundStyle(first ? theme.accent : theme.ink)
                Text("\(WeightFormat.volume(s.volume)) VOL")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.inkSoft)
            }
        }
        .padding(theme.spacing[3])
        .overlay(
            RoundedRectangle(cornerRadius: theme.radiusCard)
                .stroke(first ? theme.accent : theme.inkFaint, lineWidth: first ? 2 : 1.5))
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(theme.inkSoft)
    }
}

#Preview("Loaded — Flat") {
    NavigationStack {
        ExerciseDetailView(exerciseID: MockExerciseRepository.flatID,
                           repository: MockExerciseRepository())
    }
    .environment(Theme())
}

#Preview("Bodyweight — no PB") {
    NavigationStack {
        ExerciseDetailView(exerciseID: MockExerciseRepository.pushupID,
                           repository: MockExerciseRepository())
    }
    .environment(Theme())
}

#Preview("Empty history") {
    NavigationStack {
        ExerciseDetailView(exerciseID: MockExerciseRepository.emptyID,
                           repository: MockExerciseRepository())
    }
    .environment(Theme())
}
```

- [ ] **Step 2: Build to confirm the view compiles**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/ExerciseDetail/ExerciseDetailView.swift
git commit -m "feat: ExerciseDetailView screen (header, pills, PB, chart, sessions, states)"
```

---

## Task 8: Library Exercises catalog list + navigation wiring (View: preview + UI test)

The Library tab is still a placeholder. Add a minimal Exercises catalog list inside `LibraryView`'s `NavigationStack` whose rows push `ExerciseDetailView(exerciseID:)`. Inject the shared `Theme` and a single `MockExerciseRepository`.

**Files:**
- Modify: `Pulse/App/PulseApp.swift` (inject `Theme` into the environment)
- Modify: `Pulse/Features/Library/LibraryView.swift`

- [ ] **Step 1: Inject `Theme` at the app root in `Pulse/App/PulseApp.swift`**

Replace the file body with:

```swift
import SwiftUI

@main
struct PulseApp: App {
    @State private var theme = Theme()
    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(theme)
        }
    }
}
```

- [ ] **Step 2: Rewrite `Pulse/Features/Library/LibraryView.swift` with an Exercises catalog**

```swift
import SwiftUI

struct LibraryView: View {
    @Environment(Theme.self) private var theme
    private let repository = MockExerciseRepository()

    var body: some View {
        NavigationStack {
            List(repository.all()) { exercise in
                NavigationLink {
                    ExerciseDetailView(exerciseID: exercise.id, repository: repository)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        Text("\(exercise.muscleGroup.uppercased()) · \(exercise.equipment)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.inkSoft)
                    }
                }
                .listRowBackground(theme.surface)
                .accessibilityIdentifier("library-exercise-\(exercise.name)")
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("Library")
        }
    }
}

#Preview {
    LibraryView().environment(Theme())
}
```

- [ ] **Step 3: Build**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Pulse/App/PulseApp.swift Pulse/Features/Library/LibraryView.swift
git commit -m "feat: Library exercises catalog list pushing Exercise Detail"
```

---

## Task 9: Acceptance UI tests (XCUITest)

Maps each acceptance criterion to a UI assertion. Navigates Library → Exercise Detail and back; checks header, pills, PB presence/absence, chart, sessions, and back navigation. Loading/empty/error and palette criteria are covered by the model unit tests (Task 5) + previews (Task 7); the UI test asserts the rendered structure that is deterministic in the simulator.

**Files:**
- Create: `PulseUITests/ExerciseDetailUITests.swift`

- [ ] **Step 1: Write `PulseUITests/ExerciseDetailUITests.swift`**

```swift
import XCTest

final class ExerciseDetailUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func openLibrary(_ app: XCUIApplication) {
        app.launch()
        app.tabBars.buttons["Library"].tap()
    }

    private func openExercise(_ app: XCUIApplication, _ name: String) {
        openLibrary(app)
        let row = app.buttons["library-exercise-\(name)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
    }

    // AC1 + AC2 + AC11: navigate in, header reflects exercise, back returns.
    func testNavigateInHeaderAndBack() {
        let app = XCUIApplication()
        openExercise(app, "Flat Machine Chest Press")

        let title = app.staticTexts["exdetail-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Flat Machine Chest Press.")
        XCTAssertEqual(app.staticTexts["exdetail-eyebrow"].label, "CHEST · MACHINE")

        app.buttons["exdetail-back"].tap()
        XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    }

    // AC3 + AC4: multi-variation shows pills; PB card present.
    func testMultiVariationShowsPillsAndPB() {
        let app = XCUIApplication()
        openExercise(app, "Flat Machine Chest Press")
        XCTAssertTrue(app.otherElements["exdetail-variation-pills"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["exdetail-pb-card"].exists)
    }

    // AC3: no-variation exercise shows no pill row.
    func testNoVariationHidesPills() {
        let app = XCUIApplication()
        openExercise(app, "Barbell Bench Press")
        XCTAssertTrue(app.staticTexts["exdetail-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["exdetail-variation-pills"].exists)
    }

    // AC5: bodyweight exercise hides the PB card.
    func testBodyweightHidesPBCard() {
        let app = XCUIApplication()
        openExercise(app, "Tricep Push Up")
        XCTAssertTrue(app.staticTexts["exdetail-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["exdetail-pb-card"].exists)
    }

    // AC6 + AC7: chart and sessions list render.
    func testChartAndSessionsRender() {
        let app = XCUIApplication()
        openExercise(app, "Flat Machine Chest Press")
        XCTAssertTrue(app.otherElements["exdetail-volume-chart"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["exdetail-sessions-list"].exists)
    }

    // AC9: empty-history exercise shows the empty message, no chart.
    func testEmptyHistoryShowsEmptyMessage() {
        let app = XCUIApplication()
        openExercise(app, "Incline DB Press")
        XCTAssertTrue(app.staticTexts["exdetail-empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["exdetail-volume-chart"].exists)
    }
}
```

- [ ] **Step 2: Regenerate and run the UI test suite**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseUITests/ExerciseDetailUITests test
```
Expected: PASS — all six UI tests green. (If a list row label is not hittable because the `accessibilityIdentifier` is on the row content rather than the `NavigationLink`, move the identifier onto the `NavigationLink` and re-run.)

- [ ] **Step 3: Commit**

```bash
git add PulseUITests/ExerciseDetailUITests.swift
git commit -m "test: acceptance UI tests for Exercise Detail (AC1-AC11)"
```

---

## Task 10: Full suite green + open PR

- [ ] **Step 1: Run the entire test suite**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test
```
Expected: `TEST SUCCEEDED` — Analytics, WeightFormat, ExerciseRepository types, Mock, ExerciseDetailModel, SessionDateLabel, and the UI tests all pass; pre-existing Palette/WorkoutModels tests still pass.

- [ ] **Step 2: Push and open the PR (⏸ confirm with the user first)**

Run:
```bash
git push -u origin feature/BAK-11-exercise-detail
gh pr create --fill --base main
```
Use the PR template; link Linear **BAK-11**; note the spec and this plan in the body.

- [ ] **Step 3: Validate & review (human gate)**

Run the `code-reviewer` agent and `/security-review` on the diff. Address findings, keep CI green, then request the human PR review gate per `CLAUDE.md`.

---

## Self-Review notes

- **Acceptance-criteria coverage:**
  - AC1/AC11 → Task 8 (nav wiring) + Task 9 `testNavigateInHeaderAndBack`.
  - AC2 → Task 7 header + Task 9 eyebrow/title assertions.
  - AC3/AC4 → Task 5 `testVariationsPrependAllAndPillVisibility` (default index, "All" prefix, visibility) + Task 7 pill styling + Task 9 `testMultiVariationShowsPillsAndPB` / `testNoVariationHidesPills`.
  - AC5 → Task 5 `testShowsPersonalBest*` + Task 7 PB card (onAccent, never accent2) + Task 9 PB present/absent. PB derived via Epley top-set (product decision), `· TRACKED` from `tracksPR`.
  - AC6 → Task 7 volume chart (oldest→newest, last bar `accent2`, others `accent` 0.55, 8px floor) + Task 5 `testMaxVolumeIsNeverZero` + Task 9 chart render.
  - AC7 → Task 7 sessions list (first row accent 2px border, Oswald top weight) + Task 9 list render.
  - AC8 (loading) → Task 5 `.loading` initial phase + Task 7 `ProgressView` placeholder.
  - AC9 (empty) → Task 5 `testEmptyHistorySetsEmptyPhase` + Task 7 empty state + Task 9 `testEmptyHistoryShowsEmptyMessage`.
  - AC10 (error) → Task 5 `testRepositoryFailureSetsErrorPhaseAndNoStaleData` + Task 7 error state (no stale bars).
  - AC12 (palette) → all colors are `Theme` token reads; no hardcoded colors/spacing; layout is token-independent, so Coastal↔Mint restyles without layout change.
- **Product decisions applied:** kg-only via `WeightFormat` (single helper); PB = Epley est-1RM, warmups excluded, derived not stored; local-tz date labels; inert `⋯`; variation pill cosmetic (Open Q1); window "up to 4" (Open Q6).
- **Conventions:** MVVM + `@Observable` model; data access only via `ExerciseRepository` (mock-backed, no Supabase); feature-folder layout under `Pulse/Features/ExerciseDetail/`; `Theme` tokens only; XcodeGen regenerate (no `.xcodeproj` hand-edits); TDD for all logic, preview + UI test for views.
- **Out of scope (per spec):** `⋯` actions, editing/logging, real Supabase, related-lift cross-linking, range selectors beyond last-4, per-variation PR semantics, widgets/Live Activity. None planned here.
- **BAK-6 reconciliation:** `ExerciseRepository`, `ExerciseSessionSummary`, `PersonalBest`, `MockExerciseRepository`, and the `Exercise` metadata additions are defined here behind the protocol BAK-6 will adopt; when BAK-6's live layer lands, the concrete Supabase repo conforms to the same protocol and the mock moves to the shared test/preview seed.
```