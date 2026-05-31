# Workout Active Flow (pre → set → rest → summary) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the full-screen active-workout takeover — `pre → active → rest → summary` — driven by an `@Observable` session engine (state machine + flattened per-set step list) and four SwiftUI phase screens plus three bottom sheets (Swap / History / Jump). The engine owns step computation, swaps, the per-set ledger, rest countdown, and a derived receipt; it binds only to repository protocols + in-memory mocks (never Supabase). The engine must publish the state downstream Live Activity / Widgets will subscribe to (phase, current/next step context, absolute `restEndsAt`, overall progress).

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. The session engine lives in `Pulse/Core/Workout`; the pure step builder is a separate value-type helper in the same folder (unit-tested independently). Phase screens + sheets live in `Pulse/Features/ActiveWorkout/`. The app shell branches on session state to hide the tab bar and present the takeover. All colors/spacing come from `Theme` tokens; all data comes through `Core/Data` repository protocols backed by in-memory mocks. Project is generated from `project.yml` via XcodeGen (never hand-edit the `.xcodeproj`).

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency, XcodeGen, XCTest + XCUITest.

**Authoritative product decisions (from `docs/superpowers/specs/2026-05-31-product-decisions.md` — these override the spec's Open questions):**
- **Units: kilograms only for v1.** All weight copy reads "KG" (not "LBS"). Weight stepper increments are **±2.5 kg**; reps **±1**. Keep weight formatting in one helper (`WeightFormat`) so a later units toggle is localized.
- **PR = estimated 1RM via Epley:** `1RM = weight × (1 + reps/30)`, computed per logged `working`/`amrap` set (warmups excluded). The summary PR count is **derived** — count exercises whose best logged est-1RM this session beats the baseline from the history repository.
- **Failure-set logged value:** a logged `failure` set stores `reps: 0, weight: 0, type: .failure` (steppers are hidden; rep target is not a real count). It is excluded from volume and PR.
- **Skip on the final step is a no-op** beyond clamping (`afterRest` clamps `stepIdx` at the last index and stays `.active`). Only `logSet` on the final step goes to `.summary`.
- **Default rest = constant 90 s** for this feature (`restTotal = 90`). A per-exercise/global preference is a later feature.
- **Stepper seed:** weight/reps seed from the current set's planned target (`SetSpec.reps`, and the planned weight carried on the step — see Task 2 sample data).
- **Sheets:** native `.sheet` + `.presentationDetents` with custom styled content (26pt top radius, scrim, drag handle). The `⋯` overflow and History sheet content beyond "recent sets" are inert/minimal placeholders for v1.

---

## Prerequisites (verify before starting)

This feature is **UI-first against repository protocols + in-memory mocks**. It depends on two earlier features being built first:

- **BAK-7 (Design System):** `Theme` (`Pulse/Core/DesignSystem/Theme.swift`) + `Palette` exist and provide `bg / surface / surface2 / ink / inkSoft / inkFaint / accent / accentDeep / accent2 / onAccent`, `spacing`, `radiusCard`, `radiusPill`; the pressable `PulseButtonStyle`, the `Lockup` hero-numeral view, the `Eyebrow`/Geist-Mono label style, and the bottom-sheet styling helper. Fonts (Hanken Grotesk, Oswald, Geist Mono) are vendored and declared in `project.yml`.
- **BAK-6 (Data layer):** the domain models in `Pulse/Core/Models/WorkoutModels.swift` (already present), plus the repository **protocols + in-memory mocks + sample data** this flow binds to. `SessionSet` carries `exerciseID` and `order` (per product decisions).

- [ ] **Step 0a: Confirm the design system exists**

Run: `ls Pulse/Core/DesignSystem/Theme.swift Pulse/Core/DesignSystem/Palette.swift`
Expected: both paths print (no "No such file").

- [ ] **Step 0b: Confirm the data layer exists**

Run: `ls Pulse/Core/Data 2>/dev/null && echo OK || echo "BAK-6 not built — build it first"`
Expected: `OK`. If the folder is missing, stop — BAK-6 must land first.

- [ ] **Step 0c: Confirm XcodeGen + simulator and a clean build**

Run:
```bash
which xcodegen && xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 0d: Branch**

Run: `git checkout -b feature/BAK-14-workout-active-flow`
Expected: switched to a new branch.

---

## Task 1: `WorkoutStep` + `buildSteps` (pure helper, strict TDD)

The flattened step list and the exercise→steps index. This is pure logic with no UI — strict TDD.

**Files:**
- Create: `Pulse/Core/Workout/WorkoutStep.swift`
- Create: `PulseTests/ActiveWorkout/WorkoutStepTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/ActiveWorkout/WorkoutStepTests.swift`**

```swift
import XCTest
@testable import Pulse

final class WorkoutStepTests: XCTestCase {

    // Helpers ---------------------------------------------------------------
    private func ex(_ name: String, group: String = "Chest",
                    superset: String? = nil, setCount: Int) -> WorkoutExercise {
        WorkoutExercise(
            exercise: Exercise(name: name, muscleGroup: group, variations: []),
            variationID: nil,
            supersetGroup: superset,
            sets: (0..<setCount).map { _ in SetSpec(reps: 10, rir: 2, type: .working) }
        )
    }
    private func workout(_ exercises: [WorkoutExercise]) -> Workout {
        Workout(name: "W", weekday: nil, order: 0, exercises: exercises)
    }

    // buildSteps: non-superset ---------------------------------------------
    func testNonSupersetOneStepPerSetAllRestExceptLast() {
        let w = workout([ex("Bench", setCount: 3)])
        let steps = buildSteps(w)
        XCTAssertEqual(steps.count, 3)
        XCTAssertEqual(steps.map(\.exIdx), [0, 0, 0])
        XCTAssertEqual(steps.map(\.setIdx), [0, 1, 2])
        XCTAssertEqual(steps.map(\.rest), [true, true, false]) // last forced false
        XCTAssertTrue(steps.allSatisfy { $0.supersetPartnerExIdx == nil })
    }

    // buildSteps: superset interleave --------------------------------------
    func testSupersetInterleavesRoundsAndRestsOnLastMember() {
        let a = ex("A", superset: "ss1", setCount: 2)
        let b = ex("B", superset: "ss1", setCount: 2)
        let steps = buildSteps(workout([a, b]))
        // order A1, B1, A2, B2
        XCTAssertEqual(steps.map(\.exIdx), [0, 1, 0, 1])
        XCTAssertEqual(steps.map(\.setIdx), [0, 0, 1, 1])
        // rest only after the last member of each round, last step forced false
        XCTAssertEqual(steps.map(\.rest), [false, true, false, false])
        XCTAssertEqual(steps.map(\.supersetPartnerExIdx), [1, 0, 1, 0])
    }

    func testSupersetMemberWithFewerSetsSkippedInLaterRounds() {
        let a = ex("A", superset: "ss1", setCount: 3)
        let b = ex("B", superset: "ss1", setCount: 1) // only round 0
        let steps = buildSteps(workout([a, b]))
        // round0: A1,B1 ; round1: A2 ; round2: A3
        XCTAssertEqual(steps.map(\.exIdx), [0, 1, 0, 0])
        XCTAssertEqual(steps.map(\.setIdx), [0, 0, 1, 2])
    }

    // ssLabel ---------------------------------------------------------------
    func testSsLabelDerivedFromGroupPosition() {
        let a = ex("A", superset: "ss1", setCount: 1)
        let b = ex("B", superset: "ss1", setCount: 1)
        let w = workout([a, b])
        let steps = buildSteps(w)
        XCTAssertEqual(steps[0].ssLabel(in: w), "1A")
        XCTAssertEqual(steps[1].ssLabel(in: w), "1B")
    }

    // exerciseSteps index ---------------------------------------------------
    func testExerciseStepsMapsExIdxToStepIndices() {
        let a = ex("A", superset: "ss1", setCount: 2)
        let b = ex("B", superset: "ss1", setCount: 2)
        let map = exerciseSteps(buildSteps(workout([a, b])))
        XCTAssertEqual(map[0], [0, 2])
        XCTAssertEqual(map[1], [1, 3])
    }

    func testSingleSetWorkoutLastStepNoRest() {
        let steps = buildSteps(workout([ex("Solo", setCount: 1)]))
        XCTAssertEqual(steps.count, 1)
        XCTAssertEqual(steps[0].rest, false)
    }
}
```

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `WorkoutStep`, `buildSteps`, `exerciseSteps` undefined (does not compile).

- [ ] **Step 3: Write `Pulse/Core/Workout/WorkoutStep.swift`**

```swift
import Foundation

/// One logged unit of work: a single set of one exercise (per round for supersets).
/// `rest == true` means a rest phase follows after logging; the final step is always false.
struct WorkoutStep: Equatable {
    let exIdx: Int
    let setIdx: Int
    let rest: Bool
    let supersetPartnerExIdx: Int?

    /// "1A"/"1B" style label: superset-group ordinal (1-based among groups) + member letter.
    /// Returns nil when the step's exercise is not part of a superset.
    func ssLabel(in workout: Workout) -> String? {
        let ex = workout.exercises
        guard let group = ex[exIdx].supersetGroup else { return nil }
        // ordinal of this group among the distinct groups, in first-appearance order
        var seen: [String] = []
        for e in ex where e.supersetGroup != nil {
            if let g = e.supersetGroup, !seen.contains(g) { seen.append(g) }
        }
        guard let groupOrdinal = seen.firstIndex(of: group) else { return nil }
        // member letter: position of this exIdx among consecutive members of the group
        let members = ex.indices.filter { ex[$0].supersetGroup == group }
        guard let memberPos = members.firstIndex(of: exIdx) else { return nil }
        let letter = String(UnicodeScalar(65 + memberPos)!) // A, B, C…
        return "\(groupOrdinal + 1)\(letter)"
    }
}

/// Flatten a workout into an ordered step list.
/// - Non-superset exercise: one step per set, all `rest == true`.
/// - Superset group (consecutive members sharing `supersetGroup`): interleave
///   A1→B1→A2→B2; `rest == true` only on the last member of each round; a member
///   with fewer sets is skipped in later rounds.
/// - The very last emitted step's `rest` is forced `false`.
func buildSteps(_ workout: Workout) -> [WorkoutStep] {
    let ex = workout.exercises
    var steps: [WorkoutStep] = []
    var i = 0
    while i < ex.count {
        if let group = ex[i].supersetGroup {
            var members: [Int] = []
            var j = i
            while j < ex.count && ex[j].supersetGroup == group { members.append(j); j += 1 }
            let rounds = members.map { ex[$0].sets.count }.max() ?? 0
            for r in 0..<rounds {
                for (k, mIdx) in members.enumerated() where r < ex[mIdx].sets.count {
                    let isLastMemberOfRound = (k == members.count - 1)
                    let partner = members.first { $0 != mIdx }
                    steps.append(WorkoutStep(exIdx: mIdx, setIdx: r,
                                             rest: isLastMemberOfRound,
                                             supersetPartnerExIdx: partner))
                }
            }
            i = j
        } else {
            for s in ex[i].sets.indices {
                steps.append(WorkoutStep(exIdx: i, setIdx: s, rest: true, supersetPartnerExIdx: nil))
            }
            i += 1
        }
    }
    if !steps.isEmpty {
        let last = steps.count - 1
        steps[last] = WorkoutStep(exIdx: steps[last].exIdx, setIdx: steps[last].setIdx,
                                  rest: false, supersetPartnerExIdx: steps[last].supersetPartnerExIdx)
    }
    return steps
}

/// exIdx → ordered list of its step indices (for Jump + per-exercise done counts).
func exerciseSteps(_ steps: [WorkoutStep]) -> [Int: [Int]] {
    var map: [Int: [Int]] = [:]
    for (idx, step) in steps.enumerated() { map[step.exIdx, default: []].append(idx) }
    return map
}
```

- [ ] **Step 4: Run the test to verify it PASSES**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS — `WorkoutStepTests` green.

- [ ] **Step 5: Generate + commit**

```bash
xcodegen generate
git add Pulse/Core/Workout/WorkoutStep.swift PulseTests/ActiveWorkout/WorkoutStepTests.swift project.yml
git commit -m "feat: WorkoutStep + buildSteps step-list helper (BAK-14)"
```

---

## Task 2: Active-workout repository protocols + in-memory mocks + sample data (strict TDD)

This feature binds to repository protocols. BAK-6 owns the canonical protocols; this task adds the three this flow needs **iff they are not already defined by BAK-6**, plus the sample-data mocks the screens render from. Logic (mock return values, sample shape) is unit-tested.

> **Coordination note:** If BAK-6 already exposes `WorkoutRepository`, `ExerciseRepository`, `HistoryRepository`, reuse them and only add the in-memory mocks/sample data here. The protocols below are the contract this feature assumes.

**Files:**
- Create (or extend BAK-6's): `Pulse/Core/Data/ActiveWorkoutRepositories.swift`
- Create: `Pulse/Core/Data/Mocks/ActiveWorkoutMocks.swift`
- Create: `PulseTests/ActiveWorkout/ActiveWorkoutMocksTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/ActiveWorkout/ActiveWorkoutMocksTests.swift`**

```swift
import XCTest
@testable import Pulse

final class ActiveWorkoutMocksTests: XCTestCase {

    func testSampleWorkoutHasASupersetPairAndAFailureSet() async throws {
        let repo = MockWorkoutRepository()
        let w = try await repo.workout(id: MockWorkoutRepository.sampleID)
        // contains at least one superset group
        XCTAssertTrue(w.exercises.contains { $0.supersetGroup != nil })
        // contains at least one failure set somewhere
        XCTAssertTrue(w.exercises.flatMap(\.sets).contains { $0.type == .failure })
    }

    func testAlternativesReturnsSameMuscleGroupAndExcludesNothingByDefault() async throws {
        let repo = MockExerciseRepository()
        let alts = try await repo.alternatives(muscleGroup: "Chest")
        XCTAssertFalse(alts.isEmpty)
        XCTAssertTrue(alts.allSatisfy { $0.muscleGroup == "Chest" })
    }

    func testHistoryReturnsRecentSetsForExercise() async throws {
        let repo = MockHistoryRepository()
        let ex = Exercise(name: "Bench", muscleGroup: "Chest", variations: [])
        let sets = try await repo.recentSets(exerciseID: ex.id)
        XCTAssertFalse(sets.isEmpty)
    }

    func testSaveSessionStubRecordsTheSession() async throws {
        let repo = MockSessionWriter()
        let session = WorkoutSession(workoutID: UUID(), startedAt: .now, endedAt: .now, sets: [])
        try await repo.save(session)
        XCTAssertEqual(repo.saved.count, 1)
    }
}
```

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — protocols/mocks undefined (does not compile).

- [ ] **Step 3: Write `Pulse/Core/Data/ActiveWorkoutRepositories.swift`** (skip any protocol BAK-6 already declares)

```swift
import Foundation

/// Source of the workout to run. UI-first: backed by an in-memory mock.
protocol WorkoutRepository {
    func workout(id: Workout.ID) async throws -> Workout
}

/// Alternatives for the Swap sheet, grouped by muscle group.
protocol ExerciseRepository {
    func alternatives(muscleGroup: String) async throws -> [Exercise]
}

/// Recent logged sets for the History sheet.
protocol HistoryRepository {
    func recentSets(exerciseID: Exercise.ID) async throws -> [SessionSet]
}

/// Persists a finished session. Real wiring is BAK-6; here it is a stub.
protocol SessionWriter {
    func save(_ session: WorkoutSession) async throws
}
```

- [ ] **Step 4: Write `Pulse/Core/Data/Mocks/ActiveWorkoutMocks.swift`**

```swift
import Foundation

/// Deterministic sample workout: a few straight exercises, one superset pair,
/// and a bodyweight-to-failure finisher — enough to drive every screen state.
enum SampleData {
    static let bench = Exercise(name: "Flat Machine Press", muscleGroup: "Chest",
                                variations: [Variation(name: "Wide")])
    static let incline = Exercise(name: "Incline DB Press", muscleGroup: "Chest", variations: [])
    static let triCable = Exercise(name: "Tricep Cable Ext.", muscleGroup: "Triceps",
                                   variations: [Variation(name: "Rope")])
    static let latRaise = Exercise(name: "Single Arm Lateral Raise", muscleGroup: "Delts",
                                   variations: [Variation(name: "Cable")])
    static let pushup = Exercise(name: "Tricep Pushup", muscleGroup: "Triceps", variations: [])

    /// Planned weight per (exIdx, setIdx). Stepper seeds read from here (kg).
    static func plannedWeight(exIdx: Int, setIdx: Int) -> Double {
        switch exIdx {
        case 0: return 60      // bench
        case 1: return 28      // incline
        case 2: return 25      // tri cable
        case 3: return 12      // lat raise
        default: return 0      // pushup (failure / bodyweight)
        }
    }

    static let workout = Workout(
        name: "Chest & Tris", weekday: 1, order: 0,
        exercises: [
            WorkoutExercise(exercise: bench, variationID: bench.variations.first?.id,
                            supersetGroup: nil,
                            sets: [SetSpec(reps: 15, rir: 3, type: .warmup),
                                   SetSpec(reps: 12, rir: 2, type: .working),
                                   SetSpec(reps: 10, rir: 1, type: .working),
                                   SetSpec(reps: 8,  rir: 0, type: .working)]),
            WorkoutExercise(exercise: incline, variationID: nil, supersetGroup: nil,
                            sets: [SetSpec(reps: 12, rir: 2, type: .working),
                                   SetSpec(reps: 10, rir: 1, type: .dropset)]),
            WorkoutExercise(exercise: triCable, variationID: triCable.variations.first?.id,
                            supersetGroup: "ss1",
                            sets: [SetSpec(reps: 12, rir: 2, type: .working),
                                   SetSpec(reps: 12, rir: 1, type: .working)]),
            WorkoutExercise(exercise: latRaise, variationID: latRaise.variations.first?.id,
                            supersetGroup: "ss1",
                            sets: [SetSpec(reps: 15, rir: 2, type: .working),
                                   SetSpec(reps: 15, rir: 1, type: .amrap)]),
            WorkoutExercise(exercise: pushup, variationID: nil, supersetGroup: nil,
                            sets: [SetSpec(reps: 0, rir: 0, type: .failure)]),
        ])
}

struct MockWorkoutRepository: WorkoutRepository {
    static let sampleID = SampleData.workout.id
    func workout(id: Workout.ID) async throws -> Workout { SampleData.workout }
}

struct MockExerciseRepository: ExerciseRepository {
    func alternatives(muscleGroup: String) async throws -> [Exercise] {
        switch muscleGroup {
        case "Chest":
            return [Exercise(name: "Barbell Bench", muscleGroup: "Chest", variations: []),
                    Exercise(name: "Cable Fly", muscleGroup: "Chest", variations: []),
                    Exercise(name: "Pec Deck", muscleGroup: "Chest", variations: [])]
        case "Triceps":
            return [Exercise(name: "Skullcrusher", muscleGroup: "Triceps", variations: []),
                    Exercise(name: "Overhead Ext.", muscleGroup: "Triceps", variations: [])]
        default:
            return [Exercise(name: "Alt \(muscleGroup)", muscleGroup: muscleGroup, variations: [])]
        }
    }
}

struct MockHistoryRepository: HistoryRepository {
    func recentSets(exerciseID: Exercise.ID) async throws -> [SessionSet] {
        [SessionSet(reps: 10, weight: 55, type: .working),
         SessionSet(reps: 8,  weight: 60, type: .working),
         SessionSet(reps: 6,  weight: 62.5, type: .working)]
    }
}

final class MockSessionWriter: SessionWriter {
    private(set) var saved: [WorkoutSession] = []
    func save(_ session: WorkoutSession) async throws { saved.append(session) }
}
```

> If `SessionSet` in `WorkoutModels.swift` does not yet carry `exerciseID`/`order` (BAK-6 adds them), construct sample sets with those fields once present; volume/PR math here only reads `reps`/`weight`/`type`.

- [ ] **Step 5: Run the test to verify it PASSES**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS — `ActiveWorkoutMocksTests` green.

- [ ] **Step 6: Generate + commit**

```bash
xcodegen generate
git add Pulse/Core/Data PulseTests/ActiveWorkout/ActiveWorkoutMocksTests.swift project.yml
git commit -m "feat: active-workout repository protocols, mocks, sample data (BAK-14)"
```

---

## Task 3: Weight formatting + Epley PR analytics helper (strict TDD)

Centralize kg formatting and the est-1RM math the summary uses. Pure logic — strict TDD.

**Files:**
- Create: `Pulse/Core/Workout/WeightFormat.swift`
- Create: `Pulse/Core/Workout/PRMath.swift`
- Create: `PulseTests/ActiveWorkout/PRMathTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/ActiveWorkout/PRMathTests.swift`**

```swift
import XCTest
@testable import Pulse

final class PRMathTests: XCTestCase {

    func testEpleyOneRepMax() {
        // 100kg × (1 + 10/30) = 133.33…
        XCTAssertEqual(epley1RM(weight: 100, reps: 10), 100 * (1 + 10.0/30), accuracy: 0.0001)
    }

    func testEpleyZeroRepsIsWeight() {
        XCTAssertEqual(epley1RM(weight: 80, reps: 0), 80, accuracy: 0.0001)
    }

    func testBestEpleyExcludesWarmupAndFailure() {
        let sets = [SessionSet(reps: 12, weight: 100, type: .warmup),   // excluded
                    SessionSet(reps: 10, weight: 100, type: .working),  // 133.3
                    SessionSet(reps: 5,  weight: 120, type: .working),  // 140.0  <- best
                    SessionSet(reps: 0,  weight: 0,   type: .failure)]  // excluded
        let best = bestEpley(in: sets)
        XCTAssertEqual(best!, 120 * (1 + 5.0/30), accuracy: 0.0001)
    }

    func testBestEpleyNilWhenNoQualifyingSets() {
        XCTAssertNil(bestEpley(in: [SessionSet(reps: 0, weight: 0, type: .failure)]))
    }

    func testWeightFormatKgWholeAndHalf() {
        XCTAssertEqual(WeightFormat.kg(60), "60 kg")
        XCTAssertEqual(WeightFormat.kg(62.5), "62.5 kg")
    }

    func testWeightFormatEyebrowUppercase() {
        XCTAssertEqual(WeightFormat.eyebrow(weight: 60, reps: 10), "60 KG · 10 REPS")
    }
}
```

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `epley1RM`, `bestEpley`, `WeightFormat` undefined.

- [ ] **Step 3: Write `Pulse/Core/Workout/PRMath.swift`**

```swift
import Foundation

/// Epley estimated one-rep max: weight × (1 + reps/30).
func epley1RM(weight: Double, reps: Int) -> Double {
    weight * (1 + Double(reps) / 30)
}

/// Best est-1RM among qualifying sets (working/amrap only; warmup & failure excluded).
/// Returns nil when no set qualifies.
func bestEpley(in sets: [SessionSet]) -> Double? {
    let qualifying = sets.filter { $0.type == .working || $0.type == .amrap }
    guard !qualifying.isEmpty else { return nil }
    return qualifying.map { epley1RM(weight: $0.weight, reps: $0.reps) }.max()
}
```

- [ ] **Step 4: Write `Pulse/Core/Workout/WeightFormat.swift`**

```swift
import Foundation

/// Single source of truth for weight display (kg-only in v1; a units toggle is later).
enum WeightFormat {
    /// "60 kg" / "62.5 kg" — trims a trailing ".0".
    static func kg(_ weight: Double) -> String {
        let trimmed = weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(weight))
            : String(weight)
        return "\(trimmed) kg"
    }

    /// Footer eyebrow: "60 KG · 10 REPS".
    static func eyebrow(weight: Double, reps: Int) -> String {
        let w = weight.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(weight)) : String(weight)
        return "\(w) KG · \(reps) REPS"
    }
}
```

- [ ] **Step 5: Run the test to verify it PASSES**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS — `PRMathTests` green.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/Workout/PRMath.swift Pulse/Core/Workout/WeightFormat.swift PulseTests/ActiveWorkout/PRMathTests.swift
git commit -m "feat: Epley est-1RM helper + kg weight formatter (BAK-14)"
```

---

## Task 4: `ActiveWorkoutModel` — state machine + step logic (strict TDD)

The heart of the feature. Strict TDD: every transition tested first. Rest is driven by an absolute `restEndsAt` (Live-Activity-friendly) plus a `remainingRest(now:)` derivation, so tests are deterministic by passing an explicit `now`.

**Files:**
- Create: `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift`
- Create: `Pulse/Features/ActiveWorkout/SessionSummary.swift`
- Create: `PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift`**

```swift
import XCTest
@testable import Pulse

final class ActiveWorkoutModelTests: XCTestCase {

    private func makeModel() -> ActiveWorkoutModel {
        ActiveWorkoutModel(
            exerciseRepo: MockExerciseRepository(),
            historyRepo: MockHistoryRepository(),
            sessionWriter: MockSessionWriter()
        )
    }
    private func started() -> ActiveWorkoutModel {
        let m = makeModel(); m.startWorkout(SampleData.workout); return m
    }

    // AC1 ------------------------------------------------------------------
    func testStartWorkoutResetsState() {
        let m = makeModel()
        m.startWorkout(SampleData.workout)
        XCTAssertEqual(m.phase, .pre)
        XCTAssertEqual(m.stepIdx, 0)
        XCTAssertTrue(m.doneSteps.isEmpty)
        XCTAssertTrue(m.swaps.isEmpty)
        XCTAssertEqual(m.steps, buildSteps(SampleData.workout))
    }

    // AC2 ------------------------------------------------------------------
    func testBeginSetsMovesPreToActiveKeepingStepIdx() {
        let m = started()
        m.beginSets()
        XCTAssertEqual(m.phase, .active)
        XCTAssertEqual(m.stepIdx, 0)
    }

    // AC4 — non-superset set logs → rest, idempotent ------------------------
    func testLogNonSupersetGoesToRestIdempotently() {
        let m = started(); m.beginSets()           // step 0 = bench warmup, rest == true
        m.logSet(reps: 15, weight: 40)
        XCTAssertEqual(m.phase, .rest)
        XCTAssertEqual(m.stepIdx, 0)
        XCTAssertEqual(m.doneSteps, [0])
        m.logSet(reps: 15, weight: 40)             // logging twice does not duplicate
        XCTAssertEqual(m.doneSteps.count, 1)
    }

    // AC5 — mid-superset set advances without rest --------------------------
    func testLogMidSupersetAdvancesNoRest() {
        let m = started(); m.beginSets()
        // jump to the first superset step (tri cable, exIdx 2)
        m.jump(toExerciseIndex: 2)
        let step = m.currentStep
        XCTAssertEqual(step.rest, false)           // first member of round → no rest
        m.logSet(reps: 12, weight: 25)
        XCTAssertEqual(m.phase, .active)
        XCTAssertEqual(m.stepIdx, step.exIdx == 2 ? m.stepIdx, "advanced")
        XCTAssertTrue(m.stepIdx > 0)
    }

    func testLogButtonLabelMidSupersetReadsPartner() {
        let m = started(); m.beginSets(); m.jump(toExerciseIndex: 2)
        // partner is lat raise; ssLabel "1B"
        XCTAssertEqual(m.logButtonLabel, "Log → 1B")
    }

    // AC6 — final step → summary, label "Finish workout" --------------------
    func testLogFinalStepGoesToSummary() {
        let m = started(); m.beginSets()
        m.jump(toExerciseIndex: 4)                 // pushup, single failure set = last step
        XCTAssertEqual(m.currentStep, m.steps.last)
        XCTAssertEqual(m.logButtonLabel, "Finish workout")
        m.logSet(reps: 0, weight: 0)
        XCTAssertEqual(m.phase, .summary)
    }

    // AC7 — rest auto-advance / afterRest ----------------------------------
    func testAfterRestAdvancesAndClampsAtLast() {
        let m = started(); m.beginSets()
        m.logSet(reps: 15, weight: 40)             // → rest at step 0
        m.afterRest()
        XCTAssertEqual(m.phase, .active)
        XCTAssertEqual(m.stepIdx, 1)
        // clamp at last
        m.jump(toExerciseIndex: 4)
        m.afterRest()
        XCTAssertEqual(m.stepIdx, m.steps.count - 1) // clamped, not summary
        XCTAssertEqual(m.phase, .active)
    }

    // AC8 — rest adjust clamps at 0, no upper clamp -------------------------
    func testAdjustRestClampsAtZeroNoUpperClamp() {
        let m = started(); m.beginSets()
        let base = Date(timeIntervalSince1970: 1_000)
        m.logSet(reps: 15, weight: 40, now: base)  // restEndsAt = base + 90
        m.adjustRest(30, now: base)
        XCTAssertEqual(m.remainingRest(now: base), 120, accuracy: 0.5)
        m.adjustRest(-1000, now: base)             // clamp at 0
        XCTAssertEqual(m.remainingRest(now: base), 0, accuracy: 0.5)
    }

    // AC9 — skip advances without logging -----------------------------------
    func testSkipSetAdvancesWithoutMarkingDone() {
        let m = started(); m.beginSets()
        m.skipSet()
        XCTAssertEqual(m.stepIdx, 1)
        XCTAssertEqual(m.phase, .active)
        XCTAssertTrue(m.doneSteps.isEmpty)
    }

    // AC10 — jump to first un-logged, fallback to first ---------------------
    func testJumpLandsOnFirstUnloggedStepWithFallback() {
        let m = started(); m.beginSets()
        m.logSet(reps: 15, weight: 40)             // step 0 done
        m.jump(toExerciseIndex: 0)                 // bench has steps [0,1,2,3]; first un-logged = 1
        XCTAssertEqual(m.stepIdx, 1)
        // mark all bench steps done, then jump → falls back to first (0)
        [0,1,2,3].forEach { m.markDoneForTest($0) }
        m.jump(toExerciseIndex: 0)
        XCTAssertEqual(m.stepIdx, 0)
        XCTAssertEqual(m.phase, .active)
    }

    // AC11 — swap is session-only, does not mutate workout ------------------
    func testSwapWritesOverrideWithoutMutatingWorkout() {
        let m = started()
        let alt = Exercise(name: "Pec Deck", muscleGroup: "Chest", variations: [])
        m.swap(exerciseIndex: 0, to: alt)
        XCTAssertEqual(m.swaps[0], alt)
        XCTAssertEqual(m.displayName(forExercise: 0), "Pec Deck")
        XCTAssertEqual(m.workout.exercises[0].exercise.name, "Flat Machine Press") // untouched
    }

    // AC13 — set-type labels cover all five ---------------------------------
    func testSetTypeLabelMapCoversAllFiveCases() {
        let m = makeModel()
        for type in SetType.allCases {
            let label = m.setTypeLabel(type)
            XCTAssertFalse(label.isEmpty)
        }
        XCTAssertEqual(m.setTypeLabel(.dropset), "DROP SET") // never blank
        XCTAssertEqual(m.setTypeLabel(.working), "WORKING")
    }

    // AC16 — summary derived from logged sets, empty-safe -------------------
    func testSummaryDerivesVolumeSetsAndIsEmptySafe() {
        let m = started(); m.beginSets()
        // empty: no logs yet
        XCTAssertEqual(m.summary.totalVolume, 0)
        XCTAssertEqual(m.summary.completedSets, 0)
        XCTAssertEqual(m.summary.totalSets, m.steps.count)
        XCTAssertEqual(m.summary.prCount, 0)
        // log two working sets
        m.jump(toExerciseIndex: 0)
        m.logSet(reps: 12, weight: 100)            // step done
        m.afterRest()
        m.logSet(reps: 10, weight: 110)
        XCTAssertEqual(m.summary.completedSets, 2)
        XCTAssertEqual(m.summary.totalVolume, 12*100 + 10*110, accuracy: 0.5)
    }

    // AC17 — endWorkout clears session --------------------------------------
    func testEndWorkoutClearsSession() {
        let m = started(); m.beginSets()
        m.endWorkout()
        XCTAssertFalse(m.isActive)
    }
}
```

> Note: the test uses a tiny test-only seam `markDoneForTest(_:)`. Provide it behind `#if DEBUG` in the model so production state stays `private(set)`.

- [ ] **Step 2: Run the test to verify it FAILS**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `ActiveWorkoutModel`, `SessionSummary` undefined.

- [ ] **Step 3: Write `Pulse/Features/ActiveWorkout/SessionSummary.swift`**

```swift
import Foundation

/// Derived receipt totals for the summary screen. All values come from logged sets.
struct SessionSummary: Equatable {
    var totalVolume: Double   // Σ reps×weight over working/amrap/dropset (failure excluded)
    var elapsedMinutes: Int
    var completedSets: Int    // doneSteps.count
    var totalSets: Int        // steps.count
    var prCount: Int          // exercises whose session best est-1RM beats baseline
}
```

- [ ] **Step 4: Write `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift`**

```swift
import Foundation
import Observation

@Observable
final class ActiveWorkoutModel {
    enum Phase { case pre, active, rest, summary }
    enum ActiveSheet: Identifiable { case swap, history, jump; var id: Self { self } }

    // dependencies (repository protocols only — never Supabase)
    private let exerciseRepo: ExerciseRepository
    private let historyRepo: HistoryRepository
    private let sessionWriter: SessionWriter

    // session state
    private(set) var workout: Workout = SampleData.workout
    private(set) var steps: [WorkoutStep] = []
    private(set) var phase: Phase = .pre
    private(set) var stepIdx: Int = 0
    private(set) var doneSteps: Set<Int> = []
    private(set) var swaps: [Int: Exercise] = [:]
    private(set) var loggedSets: [Int: SessionSet] = [:]
    private(set) var startedAt: Date = .now
    var activeSheet: ActiveSheet?
    /// nil when no session is running (drives the app-shell takeover branch).
    private(set) var isActive: Bool = false

    // rest state (absolute end is Live-Activity-friendly)
    let restTotal: TimeInterval = 90
    private(set) var restEndsAt: Date?

    // baseline est-1RM per exercise for PR detection (loaded from history)
    private var prBaseline: [Exercise.ID: Double] = [:]

    init(exerciseRepo: ExerciseRepository,
         historyRepo: HistoryRepository,
         sessionWriter: SessionWriter) {
        self.exerciseRepo = exerciseRepo
        self.historyRepo = historyRepo
        self.sessionWriter = sessionWriter
    }

    // MARK: - lifecycle

    func startWorkout(_ w: Workout) {
        workout = w
        steps = buildSteps(w)
        phase = .pre
        stepIdx = 0
        doneSteps = []
        swaps = [:]
        loggedSets = [:]
        startedAt = .now
        restEndsAt = nil
        isActive = true
        activeSheet = nil
    }

    func beginSets() { phase = .active }

    func endWorkout() {
        isActive = false
        phase = .pre
        activeSheet = nil
    }

    // MARK: - logging / transitions

    func logSet(reps: Int, weight: Double, now: Date = .now) {
        guard !steps.isEmpty else { return }
        let step = steps[stepIdx]
        let type = currentSet?.type ?? .working
        loggedSets[stepIdx] = SessionSet(reps: reps, weight: weight, type: type)
        doneSteps.insert(stepIdx)

        if stepIdx == steps.count - 1 {
            phase = .summary
        } else if step.rest {
            startRest(now: now)
            phase = .rest
        } else {
            stepIdx += 1
            phase = .active
        }
    }

    /// Rest finished (auto at 0) or "Skip rest" — advance, clamp, back to active.
    func afterRest() {
        stepIdx = min(stepIdx + 1, steps.count - 1)
        restEndsAt = nil
        phase = .active
    }

    /// Skip the current set without logging it. Same advance/clamp as afterRest.
    func skipSet() {
        stepIdx = min(stepIdx + 1, steps.count - 1)
        phase = .active
    }

    private func startRest(now: Date) { restEndsAt = now.addingTimeInterval(restTotal) }

    func adjustRest(_ delta: TimeInterval, now: Date = .now) {
        guard let end = restEndsAt else { return }
        let newRemaining = max(0, end.timeIntervalSince(now) + delta)
        restEndsAt = now.addingTimeInterval(newRemaining)
    }

    func remainingRest(now: Date = .now) -> TimeInterval {
        guard let end = restEndsAt else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    // MARK: - jump / swap

    func jump(toExerciseIndex exIdx: Int) {
        let idxs = exerciseSteps(steps)[exIdx] ?? []
        let target = idxs.first { !doneSteps.contains($0) } ?? idxs.first ?? stepIdx
        stepIdx = target
        phase = .active
        activeSheet = nil
    }

    func swap(exerciseIndex exIdx: Int, to alt: Exercise) {
        swaps[exIdx] = alt
        activeSheet = nil
    }

    func alternatives(for exIdx: Int) async -> [Exercise] {
        (try? await exerciseRepo.alternatives(muscleGroup: workout.exercises[exIdx].exercise.muscleGroup)) ?? []
    }

    func history(for exIdx: Int) async -> [SessionSet] {
        (try? await historyRepo.recentSets(exerciseID: workout.exercises[exIdx].exercise.id)) ?? []
    }

    // MARK: - derived UI state

    var currentStep: WorkoutStep { steps[stepIdx] }
    var nextStep: WorkoutStep? { stepIdx + 1 < steps.count ? steps[stepIdx + 1] : nil }
    private var currentExercise: WorkoutExercise { workout.exercises[currentStep.exIdx] }
    private var currentSet: SetSpec? {
        let ex = currentExercise
        return currentStep.setIdx < ex.sets.count ? ex.sets[currentStep.setIdx] : nil
    }

    func displayName(forExercise exIdx: Int) -> String {
        swaps[exIdx]?.name ?? workout.exercises[exIdx].exercise.name
    }

    func isSwapped(_ exIdx: Int) -> Bool { swaps[exIdx] != nil }

    func setTypeLabel(_ type: SetType) -> String {
        switch type {
        case .working: return "WORKING"
        case .warmup:  return "WARMUP"
        case .dropset: return "DROP SET"   // prototype omitted this — never blank
        case .failure: return "FAILURE"
        case .amrap:   return "AMRAP"
        }
    }

    var logButtonLabel: String {
        if stepIdx == steps.count - 1 { return "Finish workout" }
        let step = currentStep
        if !step.rest, let partner = step.supersetPartnerExIdx {
            // partner's ssLabel for the *partner's* step in this round
            let partnerStep = WorkoutStep(exIdx: partner, setIdx: step.setIdx,
                                          rest: false, supersetPartnerExIdx: step.exIdx)
            if let label = partnerStep.ssLabel(in: workout) { return "Log → \(label)" }
        }
        return "Log set"
    }

    /// Planned stepper seeds for the current step (kg).
    var seedReps: Int { currentSet?.reps ?? 0 }
    var seedWeight: Double { SampleData.plannedWeight(exIdx: currentStep.exIdx, setIdx: currentStep.setIdx) }

    // MARK: - summary

    var summary: SessionSummary {
        let logged = Array(loggedSets.values)
        let volume = logged
            .filter { $0.type != .failure && $0.type != .warmup }
            .reduce(0) { $0 + Double($1.reps) * $1.weight }
        let elapsed = Int(Date.now.timeIntervalSince(startedAt) / 60)
        // PR: group logged sets by exercise, compare best est-1RM to baseline
        var byExercise: [Exercise.ID: [SessionSet]] = [:]
        for (idx, set) in loggedSets {
            let exID = workout.exercises[steps[idx].exIdx].exercise.id
            byExercise[exID, default: []].append(set)
        }
        let prs = byExercise.reduce(into: 0) { count, pair in
            guard let best = bestEpley(in: pair.value) else { return }
            let baseline = prBaseline[pair.key] ?? 0
            if best > baseline { count += 1 }
        }
        return SessionSummary(totalVolume: volume,
                              elapsedMinutes: elapsed,
                              completedSets: doneSteps.count,
                              totalSets: steps.count,
                              prCount: prs)
    }

    /// One LOG-row per exercise for the receipt.
    struct LogRow: Identifiable { let id: Int; let name: String; let summaryLine: String; let volume: Double; let isPR: Bool }

    var logRows: [LogRow] {
        workout.exercises.indices.compactMap { exIdx in
            let stepIdxs = exerciseSteps(steps)[exIdx] ?? []
            let sets = stepIdxs.compactMap { loggedSets[$0] }
            guard !sets.isEmpty else { return nil }
            let vol = sets.filter { $0.type != .failure && $0.type != .warmup }
                          .reduce(0) { $0 + Double($1.reps) * $1.weight }
            let line: String
            if sets.contains(where: { $0.type == .failure }) {
                line = "To failure"
            } else {
                let reps = sets.map { String($0.reps) }.joined(separator: "·")
                let topWeight = sets.map(\.weight).max() ?? 0
                line = "\(reps) @ \(WeightFormat.kg(topWeight))"
            }
            let baseline = prBaseline[workout.exercises[exIdx].exercise.id] ?? 0
            let isPR = (bestEpley(in: sets) ?? 0) > baseline
            return LogRow(id: exIdx, name: displayName(forExercise: exIdx),
                          summaryLine: line, volume: vol, isPR: isPR)
        }
    }

    #if DEBUG
    func markDoneForTest(_ idx: Int) { doneSteps.insert(idx) }
    #endif
}
```

- [ ] **Step 5: Run the test to verify it PASSES**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS — `ActiveWorkoutModelTests` green. (If `markDoneForTest` is not visible, confirm `PulseTests` builds against the DEBUG config.)

- [ ] **Step 6: Generate + commit**

```bash
xcodegen generate
git add Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift Pulse/Features/ActiveWorkout/SessionSummary.swift PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift project.yml
git commit -m "feat: ActiveWorkoutModel state machine + derived summary (BAK-14)"
```

---

## Task 5: Phase router + takeover shell (`ActiveWorkoutFlowView`) — View assembly

The full-screen router that branches on `phase` and applies the fade+rise mount transition. Validated by preview + UI test, not line-by-line TDD.

**Files:**
- Create: `Pulse/Features/ActiveWorkout/ActiveWorkoutFlowView.swift`
- Create: `Pulse/Features/ActiveWorkout/PhaseTransition.swift`

- [ ] **Step 1: Write `Pulse/Features/ActiveWorkout/PhaseTransition.swift`**

```swift
import SwiftUI

/// Fade + 6pt rise mount transition, 0.28s — re-triggered on every phase change.
extension AnyTransition {
    static var phaseMount: AnyTransition {
        .modifier(
            active: PhaseMountModifier(opacity: 0, offset: 6),
            identity: PhaseMountModifier(opacity: 1, offset: 0)
        )
    }
}

private struct PhaseMountModifier: ViewModifier {
    let opacity: Double
    let offset: CGFloat
    func body(content: Content) -> some View {
        content.opacity(opacity).offset(y: offset)
    }
}
```

- [ ] **Step 2: Write `Pulse/Features/ActiveWorkout/ActiveWorkoutFlowView.swift`**

```swift
import SwiftUI

struct ActiveWorkoutFlowView: View {
    @Bindable var model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            Group {
                switch model.phase {
                case .pre:     PreWorkoutView(model: model)
                case .active:  ActiveSetView(model: model)
                case .rest:    RestView(model: model)
                case .summary: SummaryView(model: model)
                }
            }
            .id(model.phase)                       // re-mount on phase change
            .transition(.phaseMount)
            .accessibilityIdentifier("activeFlow.phase.\(phaseID)")
        }
        .animation(.easeOut(duration: 0.28), value: model.phase)
        .sheet(item: Binding(get: { model.activeSheet }, set: { model.activeSheet = $0 })) { sheet in
            switch sheet {
            case .swap:    SwapSheet(model: model)
            case .history: HistorySheet(model: model)
            case .jump:    JumpSheet(model: model)
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(26)
        }
    }

    private var phaseID: String {
        switch model.phase {
        case .pre: return "pre"; case .active: return "active"
        case .rest: return "rest"; case .summary: return "summary"
        }
    }
}

#Preview {
    let m = ActiveWorkoutModel(exerciseRepo: MockExerciseRepository(),
                               historyRepo: MockHistoryRepository(),
                               sessionWriter: MockSessionWriter())
    m.startWorkout(SampleData.workout)
    return ActiveWorkoutFlowView(model: m).environment(Theme())
}
```

- [ ] **Step 3: Build to confirm it compiles (sheets/phase views are stubbed next)**

For now the four phase views and three sheets do not exist; create empty stubs so the router compiles, then flesh them out in Tasks 6–11. Add temporary stubs:

`Pulse/Features/ActiveWorkout/_Stubs.swift` (delete in Task 11):
```swift
import SwiftUI
struct PreWorkoutView: View { let model: ActiveWorkoutModel; var body: some View { Text("pre") } }
struct ActiveSetView: View { let model: ActiveWorkoutModel; var body: some View { Text("active") } }
struct RestView: View { let model: ActiveWorkoutModel; var body: some View { Text("rest") } }
struct SummaryView: View { let model: ActiveWorkoutModel; var body: some View { Text("summary") } }
struct SwapSheet: View { let model: ActiveWorkoutModel; var body: some View { Text("swap") } }
struct HistorySheet: View { let model: ActiveWorkoutModel; var body: some View { Text("history") } }
struct JumpSheet: View { let model: ActiveWorkoutModel; var body: some View { Text("jump") } }
```

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Pulse/Features/ActiveWorkout/ActiveWorkoutFlowView.swift Pulse/Features/ActiveWorkout/PhaseTransition.swift Pulse/Features/ActiveWorkout/_Stubs.swift project.yml
git commit -m "feat: active-flow phase router + fade/rise transition + stubs (BAK-14)"
```

---

## Task 6: App-shell takeover branch (hide tab bar while session active) — View assembly + UI test

**Files:**
- Modify: `Pulse/App/AppShell.swift`
- Modify: `Pulse/Features/Today/TodayView.swift` (add a "Start workout" entry point)
- Create: `PulseUITests/ActiveWorkoutFlowTests.swift`

- [ ] **Step 1: Modify `Pulse/App/AppShell.swift` to branch on session state**

```swift
import SwiftUI

struct AppShell: View {
    @State private var theme = Theme()
    @State private var session = ActiveWorkoutModel(
        exerciseRepo: MockExerciseRepository(),
        historyRepo: MockHistoryRepository(),
        sessionWriter: MockSessionWriter())

    var body: some View {
        Group {
            if session.isActive {
                // takeover: tab bar hidden, full-screen flow
                ActiveWorkoutFlowView(model: session)
                    .accessibilityIdentifier("activeFlow.root")
            } else {
                TabView {
                    TodayView(session: session)
                        .tabItem { Label("Today", systemImage: "bolt.fill") }
                    LibraryView()
                        .tabItem { Label("Library", systemImage: "square.stack.fill") }
                    PlanView()
                        .tabItem { Label("Plan", systemImage: "calendar") }
                    YouView()
                        .tabItem { Label("You", systemImage: "person.fill") }
                }
            }
        }
        .environment(theme)
    }
}

#Preview { AppShell() }
```

- [ ] **Step 2: Add the Today entry point in `Pulse/Features/Today/TodayView.swift`**

```swift
import SwiftUI

struct TodayView: View {
    let session: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    var body: some View {
        NavigationStack {
            VStack {
                Button("Start workout") {
                    session.startWorkout(SampleData.workout)
                }
                .buttonStyle(PulseButtonStyle())
                .accessibilityIdentifier("today.startWorkout")
            }
            .navigationTitle("Today")
        }
    }
}
```

> If BAK-9 (Today) has a richer entry point, wire `session.startWorkout(_:)` into its existing "start" button instead of replacing the screen.

- [ ] **Step 3: Write the UI test `PulseUITests/ActiveWorkoutFlowTests.swift` (AC1–2, AC17)**

```swift
import XCTest

final class ActiveWorkoutFlowTests: XCTestCase {

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    func testStartHidesTabBarAndShowsPre() {
        let app = launch()
        app.buttons["today.startWorkout"].tap()
        // tab bar gone, pre phase shown
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        XCTAssertTrue(app.otherElements["activeFlow.phase.pre"].waitForExistence(timeout: 3))
    }

    func testBeginMovesToActive() {
        let app = launch()
        app.buttons["today.startWorkout"].tap()
        app.buttons["pre.begin"].tap()
        XCTAssertTrue(app.otherElements["activeFlow.phase.active"].waitForExistence(timeout: 3))
    }

    func testDoneReturnsToTodayWithTabBar() {
        let app = launch()
        app.buttons["today.startWorkout"].tap()
        app.buttons["pre.back"].tap()              // endWorkout from pre
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
    }
}
```

- [ ] **Step 4: Build + run UI tests (some will fail until later tasks add the buttons)**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseUITests/ActiveWorkoutFlowTests/testStartHidesTabBarAndShowsPre
```
Expected: PASS for `testStartHidesTabBarAndShowsPre`. The other two pass after Task 7 adds `pre.begin`/`pre.back`.

- [ ] **Step 5: Commit**

```bash
git add Pulse/App/AppShell.swift Pulse/Features/Today/TodayView.swift PulseUITests/ActiveWorkoutFlowTests.swift
git commit -m "feat: app-shell takeover branch + Today start entry point (BAK-14)"
```

---

## Task 7: `PreWorkoutView` — View assembly

Replace the pre stub with the workout-overview screen.

**Files:**
- Create: `Pulse/Features/ActiveWorkout/PreWorkoutView.swift`
- Modify: `Pulse/Features/ActiveWorkout/_Stubs.swift` (remove `PreWorkoutView` stub)

- [ ] **Step 1: Write `Pulse/Features/ActiveWorkout/PreWorkoutView.swift`**

```swift
import SwiftUI

struct PreWorkoutView: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            HStack {
                Button(action: { model.endWorkout() }) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityIdentifier("pre.back")
                Spacer()
            }

            Text("READY")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            Text(model.workout.name + ".")
                .font(.largeTitle.bold())
                .foregroundStyle(theme.ink)

            // exercise list overview
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing[1]) {
                    ForEach(Array(model.workout.exercises.enumerated()), id: \.offset) { idx, ex in
                        HStack {
                            Text(ex.exercise.name)
                                .foregroundStyle(theme.ink)
                            Spacer()
                            Text("\(ex.sets.count) sets")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(theme.inkSoft)
                        }
                        .padding(theme.spacing[2])
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
                    }
                }
            }

            Spacer()
            Button("Begin") { model.beginSets() }
                .buttonStyle(PulseButtonStyle())
                .accessibilityIdentifier("pre.begin")
        }
        .padding(theme.spacing[5])
    }
}

#Preview {
    let m = ActiveWorkoutModel(exerciseRepo: MockExerciseRepository(),
                               historyRepo: MockHistoryRepository(),
                               sessionWriter: MockSessionWriter())
    m.startWorkout(SampleData.workout)
    return PreWorkoutView(model: m).environment(Theme())
}
```

- [ ] **Step 2: Remove the `PreWorkoutView` stub from `_Stubs.swift`** (delete that one line).

- [ ] **Step 3: Build + run the two now-passing UI tests**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseUITests/ActiveWorkoutFlowTests
```
Expected: PASS for all three `ActiveWorkoutFlowTests` (start, begin, done).

- [ ] **Step 4: Commit**

```bash
git add Pulse/Features/ActiveWorkout/PreWorkoutView.swift Pulse/Features/ActiveWorkout/_Stubs.swift
git commit -m "feat: PreWorkoutView overview screen (BAK-14)"
```

---

## Task 8: `ActiveSetView` — View assembly (hero card, steppers, partner peek, Skip/Log)

The richest screen. Validated by preview + UI tests for the load-bearing behaviors (log label, failure rendering, swapped eyebrow). Internal `@State` holds the editable reps/weight seeded from the model.

**Files:**
- Create: `Pulse/Features/ActiveWorkout/ActiveSetView.swift`
- Create: `Pulse/Features/ActiveWorkout/SetTypePill.swift`
- Modify: `Pulse/Features/ActiveWorkout/_Stubs.swift` (remove `ActiveSetView` stub)

- [ ] **Step 1: Write `Pulse/Features/ActiveWorkout/SetTypePill.swift`**

```swift
import SwiftUI

/// Uppercase set-type pill. `working` = solid accent fill + onAccent text;
/// every other type = transparent with a white-40% / inkFaint border.
struct SetTypePill: View {
    let label: String
    let isWorking: Bool
    @Environment(Theme.self) private var theme

    var body: some View {
        Text(label)
            .font(.system(.caption2, design: .monospaced)).fontWeight(.semibold)
            .tracking(2)
            .padding(.horizontal, theme.spacing[1])
            .padding(.vertical, 2)
            .foregroundStyle(isWorking ? theme.accent : theme.onAccent)
            .background(isWorking ? theme.onAccent : .clear,
                        in: Capsule())
            .overlay(Capsule().strokeBorder(isWorking ? .clear : Color.white.opacity(0.4), lineWidth: 1.5))
            .accessibilityIdentifier("active.setTypePill")
    }
}
```

- [ ] **Step 2: Write `Pulse/Features/ActiveWorkout/ActiveSetView.swift`**

```swift
import SwiftUI

struct ActiveSetView: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    @State private var reps: Int = 0
    @State private var weight: Double = 0

    private var step: WorkoutStep { model.currentStep }
    private var exIdx: Int { step.exIdx }
    private var exercise: WorkoutExercise { model.workout.exercises[exIdx] }
    private var set: SetSpec { exercise.sets[step.setIdx] }
    private var isFailure: Bool { set.type == .failure }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            topBar
            progressSegments
            exerciseHeader
            actionChips
            heroCard
            if !isFailure { steppers }
            if exercise.supersetGroup != nil { partnerPeek }
            Spacer()
            footer
        }
        .padding(theme.spacing[5])
        .onChange(of: model.stepIdx, initial: true) { _, _ in
            reps = model.seedReps
            weight = model.seedWeight
        }
    }

    // top bar: back · EX n/N · ⋯
    private var topBar: some View {
        HStack {
            Button { model.endWorkout() } label: { Image(systemName: "chevron.left") }
                .accessibilityIdentifier("active.back")
            Spacer()
            Text("EX \(exIdx + 1) / \(model.workout.exercises.count)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            Spacer()
            Image(systemName: "ellipsis")           // inert per product decisions
                .foregroundStyle(theme.inkSoft)
        }
    }

    private var progressSegments: some View {
        HStack(spacing: 4) {
            ForEach(exercise.sets.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6)
                    .fill(i < step.setIdx ? theme.accent
                          : i == step.setIdx ? theme.accent2 : theme.inkFaint)
                    .frame(height: 6)
            }
        }
        .accessibilityIdentifier("active.progress")
    }

    private var exerciseHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrowText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.inkSoft)
                    .accessibilityIdentifier("active.eyebrow")
                Text(model.displayName(forExercise: exIdx) + ".")
                    .font(.title2.bold())
                    .foregroundStyle(theme.ink)
            }
            Spacer()
            // variation chip — only when the (un-swapped) exercise has a variation
            if !model.isSwapped(exIdx), let v = exercise.exercise.variations.first {
                Button { model.activeSheet = .swap } label: {
                    Text("\(v.name) ⇆")
                        .font(.system(.caption2, design: .monospaced))
                }
                .accessibilityIdentifier("active.variationChip")
            }
        }
    }

    private var eyebrowText: String {
        var s = exercise.exercise.muscleGroup.uppercased()
        if let label = step.ssLabel(in: model.workout) { s += " · \(label)" }
        if model.isSwapped(exIdx) { s += " · SWAPPED" }
        return s
    }

    private var actionChips: some View {
        HStack(spacing: 6) {
            chip("⇆ Swap", .swap, id: "active.chip.swap")
            chip("↻ History", .history, id: "active.chip.history")
            chip("☰ Jump", .jump, id: "active.chip.jump")
        }
    }
    private func chip(_ label: String, _ sheet: ActiveWorkoutModel.ActiveSheet, id: String) -> some View {
        Button(label) { model.activeSheet = sheet }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(theme.ink)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .overlay(Capsule().strokeBorder(theme.inkFaint, lineWidth: 1))
            .accessibilityIdentifier(id)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            HStack(alignment: .top) {
                SetTypePill(label: model.setTypeLabel(set.type), isWorking: set.type == .working)
                Spacer()
                Text("SET \(step.setIdx + 1) / \(exercise.sets.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.onAccent.opacity(0.85))
            }
            // hero numeral: ∞ for failure
            Lockup(numeral: isFailure ? "∞" : "\(reps)",
                   top: isFailure ? "To failure" : "Set \(step.setIdx + 1)",
                   bottom: isFailure ? "Max reps." : "Reps @ \(WeightFormat.kg(weight)).")
            .accessibilityIdentifier(isFailure ? "active.hero.failure" : "active.hero.reps")

            HStack {
                Text(isFailure ? "BODYWEIGHT" : WeightFormat.eyebrow(weight: weight, reps: reps))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                    .accessibilityIdentifier("active.hero.footer")
                Spacer()
                repSchedule
            }
        }
        .padding(.init(top: 16, leading: 18, bottom: 20, trailing: 18))
        .background(theme.accent, in: RoundedRectangle(cornerRadius: 20))
    }

    // rep schedule: non-warmup targets joined by " → ", current underlined in accent2
    private var repSchedule: some View {
        let working = exercise.sets.enumerated().filter { $0.element.type != .warmup }
        return HStack(spacing: 0) {
            ForEach(Array(working.enumerated()), id: \.offset) { k, pair in
                let (i, spec) = pair
                Text("\(spec.reps)")
                    .underline(i == step.setIdx, color: theme.accent2)
                    .foregroundStyle(theme.onAccent)
                if k < working.count - 1 {
                    Text(" → ").foregroundStyle(theme.onAccent.opacity(0.5))
                }
            }
        }
        .font(.system(.caption2, design: .monospaced)).fontWeight(.semibold)
        .accessibilityIdentifier("active.repSchedule")
    }

    private var steppers: some View {
        HStack(spacing: 8) {
            Stepper2(label: "WEIGHT", value: WeightFormat.kg(weight),
                     onDec: { weight = max(0, weight - 2.5) }, onInc: { weight += 2.5 })
                .accessibilityIdentifier("active.stepper.weight")
            Stepper2(label: "REPS", value: "\(reps)",
                     onDec: { reps = max(0, reps - 1) }, onInc: { reps += 1 }, accent: true)
                .accessibilityIdentifier("active.stepper.reps")
        }
    }

    private var partnerPeek: some View {
        Group {
            if let partnerIdx = step.supersetPartnerExIdx {
                let partner = model.workout.exercises[partnerIdx]
                let pSet = partner.sets.indices.contains(step.setIdx) ? partner.sets[step.setIdx] : partner.sets.first
                let goesToPartner = !step.rest
                HStack(spacing: 10) {
                    Text(WorkoutStep(exIdx: partnerIdx, setIdx: step.setIdx, rest: false,
                                     supersetPartnerExIdx: exIdx).ssLabel(in: model.workout) ?? "")
                        .font(.title2.bold()).foregroundStyle(theme.accent2)
                    VStack(alignment: .leading) {
                        Text(model.displayName(forExercise: partnerIdx))
                            .font(.subheadline.bold()).foregroundStyle(theme.ink)
                        Text("\(goesToPartner ? "NEXT IN PAIR" : "PAIRED") · \(pSet?.reps ?? 0) REPS")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.inkSoft)
                    }
                    Spacer()
                }
                .padding(theme.spacing[2])
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.accent2, lineWidth: 2))
                .opacity(0.85)
                .accessibilityIdentifier("active.partnerPeek")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Skip") { model.skipSet() }
                .buttonStyle(PulseButtonStyle(kind: .secondary))
                .accessibilityIdentifier("active.skip")
            Button(model.logButtonLabel) { model.logSet(reps: reps, weight: weight) }
                .buttonStyle(PulseButtonStyle())
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("active.log")
        }
    }
}

#Preview {
    let m = ActiveWorkoutModel(exerciseRepo: MockExerciseRepository(),
                               historyRepo: MockHistoryRepository(),
                               sessionWriter: MockSessionWriter())
    m.startWorkout(SampleData.workout); m.beginSets()
    return ActiveSetView(model: m).environment(Theme())
}
```

> `Lockup`, `Stepper2`, and `PulseButtonStyle(kind:)` come from BAK-7's design system. If a `Stepper2` helper does not exist, build a small local `StepperField` view inline (label + `−`/value/`+`); it is pure layout, no logic.

- [ ] **Step 3: Remove the `ActiveSetView` stub from `_Stubs.swift`.**

- [ ] **Step 4: Add UI tests for AC5–6, AC11, AC12 to `PulseUITests/ActiveWorkoutFlowTests.swift`**

```swift
    func testLogButtonAndFailureRendering() {
        let app = launch()
        app.buttons["today.startWorkout"].tap()
        app.buttons["pre.begin"].tap()
        // step 0 = warmup non-superset → "Log set"
        XCTAssertEqual(app.buttons["active.log"].label, "Log set")
        // jump to the failure finisher and confirm ∞ + hidden steppers + BODYWEIGHT
        app.buttons["active.chip.jump"].tap()
        app.buttons["jump.exercise.4"].tap()
        XCTAssertTrue(app.staticTexts["active.hero.failure"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.otherElements["active.stepper.weight"].exists)
        XCTAssertEqual(app.staticTexts["active.hero.footer"].label, "BODYWEIGHT")
        XCTAssertEqual(app.buttons["active.log"].label, "Finish workout")
    }

    func testSwapShowsSwappedEyebrow() {
        let app = launch()
        app.buttons["today.startWorkout"].tap()
        app.buttons["pre.begin"].tap()
        app.buttons["active.chip.swap"].tap()
        app.buttons["swap.alt.0"].tap()
        XCTAssertTrue(app.staticTexts["active.eyebrow"].label.contains("SWAPPED"))
    }
```

- [ ] **Step 5: Build + run (failure/log-label tests pass; swap test passes after Task 10)**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseUITests/ActiveWorkoutFlowTests/testLogButtonAndFailureRendering
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Features/ActiveWorkout/ActiveSetView.swift Pulse/Features/ActiveWorkout/SetTypePill.swift Pulse/Features/ActiveWorkout/_Stubs.swift PulseUITests/ActiveWorkoutFlowTests.swift
git commit -m "feat: ActiveSetView hero card, steppers, partner peek (BAK-14)"
```

---

## Task 9: `RestView` — countdown ring + adjust chips + UP NEXT — View assembly

The ring drives off `model.remainingRest(now:)` ticked by a `TimelineView`; auto-advance calls `afterRest()` at 0.

**Files:**
- Create: `Pulse/Features/ActiveWorkout/RestView.swift`
- Modify: `Pulse/Features/ActiveWorkout/_Stubs.swift` (remove `RestView` stub)

- [ ] **Step 1: Write `Pulse/Features/ActiveWorkout/RestView.swift`**

```swift
import SwiftUI

struct RestView: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = model.remainingRest(now: context.date)
            content(remaining: remaining)
                .onChange(of: remaining <= 0) { _, done in
                    if done { model.afterRest() }
                }
        }
    }

    @ViewBuilder
    private func content(remaining: TimeInterval) -> some View {
        let total = model.restTotal
        let pct = total > 0 ? remaining / total : 0
        VStack(spacing: theme.spacing[3]) {
            HStack {
                Text("REST · BREATHE")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.inkSoft)
                Spacer()
                Button { model.afterRest() } label: { Image(systemName: "chevron.right") }
                    .accessibilityIdentifier("rest.forward")
            }
            Spacer()
            ZStack {
                Circle().stroke(theme.inkFaint, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: pct)
                    .stroke(theme.accent2, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: pct)
                VStack {
                    Text(timeString(remaining))
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(theme.accent2)
                        .accessibilityIdentifier("rest.time")
                    Text("OF 1:30")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(theme.inkSoft)
                }
            }
            .frame(width: 220, height: 220)
            Spacer()
            HStack(spacing: 6) {
                adjustChip("−15", -15)
                adjustChip("+15", 15)
                adjustChip("+30", 30)
            }
            if let next = model.nextStep { upNextCard(next) }
            Button("Skip rest →") { model.afterRest() }
                .buttonStyle(PulseButtonStyle())
                .accessibilityIdentifier("rest.skip")
        }
        .padding(theme.spacing[5])
    }

    private func adjustChip(_ label: String, _ delta: TimeInterval) -> some View {
        Button("\(label)s") { model.adjustRest(delta) }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(theme.ink)
            .padding(.vertical, 6).padding(.horizontal, 14)
            .overlay(Capsule().strokeBorder(theme.inkFaint, lineWidth: 1.5))
            .accessibilityIdentifier("rest.adjust.\(Int(delta))")
    }

    private func upNextCard(_ next: WorkoutStep) -> some View {
        let ex = model.workout.exercises[next.exIdx]
        let set = ex.sets.indices.contains(next.setIdx) ? ex.sets[next.setIdx] : nil
        return HStack(spacing: 12) {
            Text("\(next.setIdx + 1)")
                .font(.headline.bold()).foregroundStyle(theme.onAccent)
                .frame(width: 36, height: 36)
                .background(theme.accent, in: Circle())
            VStack(alignment: .leading) {
                Text("UP NEXT" + (next.ssLabel(in: model.workout).map { " · \($0)" } ?? ""))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.inkSoft)
                Text(model.displayName(forExercise: next.exIdx))
                    .font(.subheadline.bold()).foregroundStyle(theme.ink)
            }
            Spacer()
            Text(set?.type == .failure ? "∞" : "\(set?.reps ?? 0)")
                .font(.title.bold()).foregroundStyle(theme.accent)
        }
        .padding(theme.spacing[2])
        .overlay(RoundedRectangle(cornerRadius: theme.radiusCard).strokeBorder(theme.accent, lineWidth: 2))
        .accessibilityIdentifier("rest.upNext")
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }
}

#Preview {
    let m = ActiveWorkoutModel(exerciseRepo: MockExerciseRepository(),
                               historyRepo: MockHistoryRepository(),
                               sessionWriter: MockSessionWriter())
    m.startWorkout(SampleData.workout); m.beginSets(); m.logSet(reps: 15, weight: 40)
    return RestView(model: m).environment(Theme())
}
```

- [ ] **Step 2: Remove the `RestView` stub from `_Stubs.swift`.**

- [ ] **Step 3: Add UI test for AC7–8 (rest auto-advance + adjust) to `ActiveWorkoutFlowTests.swift`**

```swift
    func testRestAppearsOnLogAndChipsAdjust() {
        let app = launch()
        app.buttons["today.startWorkout"].tap()
        app.buttons["pre.begin"].tap()
        app.buttons["active.log"].tap()           // log step 0 → rest
        XCTAssertTrue(app.otherElements["activeFlow.phase.rest"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["rest.adjust.30"].exists)
        app.buttons["rest.adjust.30"].tap()       // +30s, no crash, still resting
        XCTAssertTrue(app.staticTexts["rest.time"].exists)
        app.buttons["rest.skip"].tap()            // afterRest → active
        XCTAssertTrue(app.otherElements["activeFlow.phase.active"].waitForExistence(timeout: 3))
    }
```

- [ ] **Step 4: Build + run**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test -only-testing:PulseUITests/ActiveWorkoutFlowTests/testRestAppearsOnLogAndChipsAdjust
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/ActiveWorkout/RestView.swift Pulse/Features/ActiveWorkout/_Stubs.swift PulseUITests/ActiveWorkoutFlowTests.swift
git commit -m "feat: RestView countdown ring, adjust chips, UP NEXT (BAK-14)"
```

---

## Task 10: Bottom sheets — Swap / History / Jump — View assembly

**Files:**
- Create: `Pulse/Features/ActiveWorkout/Sheets/SwapSheet.swift`
- Create: `Pulse/Features/ActiveWorkout/Sheets/JumpSheet.swift`
- Create: `Pulse/Features/ActiveWorkout/Sheets/HistorySheet.swift`
- Modify: `Pulse/Features/ActiveWorkout/_Stubs.swift` (remove all three sheet stubs)

- [ ] **Step 1: Write `Pulse/Features/ActiveWorkout/Sheets/SwapSheet.swift`**

```swift
import SwiftUI

struct SwapSheet: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme
    @State private var alts: [Exercise] = []

    private var exIdx: Int { model.currentStep.exIdx }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Text("SWAP EXERCISE")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            Text("By muscle group")
                .font(.title3.bold()).foregroundStyle(theme.ink)

            // current marked NOW
            row(name: model.displayName(forExercise: exIdx), tag: "NOW", action: nil, id: "swap.now")

            ForEach(Array(alts.enumerated()), id: \.offset) { i, alt in
                row(name: alt.name, tag: nil,
                    action: { model.swap(exerciseIndex: exIdx, to: alt) },
                    id: "swap.alt.\(i)")
            }
            Spacer()
        }
        .padding(theme.spacing[5])
        .background(theme.bg)
        .task { alts = await model.alternatives(for: exIdx) }
    }

    private func row(name: String, tag: String?, action: (() -> Void)?, id: String) -> some View {
        Button { action?() } label: {
            HStack {
                Text(name).foregroundStyle(theme.ink)
                Spacer()
                if let tag { Text(tag).font(.system(.caption2, design: .monospaced)).foregroundStyle(theme.accent2) }
            }
            .padding(theme.spacing[2])
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
        }
        .disabled(action == nil)
        .accessibilityIdentifier(id)
    }
}
```

- [ ] **Step 2: Write `Pulse/Features/ActiveWorkout/Sheets/JumpSheet.swift`**

```swift
import SwiftUI

struct JumpSheet: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Text("JUMP TO EXERCISE")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            ScrollView {
                VStack(spacing: theme.spacing[1]) {
                    ForEach(model.workout.exercises.indices, id: \.self) { exIdx in
                        let steps = exerciseSteps(model.steps)[exIdx] ?? []
                        let done = steps.filter { model.doneSteps.contains($0) }.count
                        let glyph = done == steps.count ? "✓" : (exIdx == model.currentStep.exIdx ? "•" : "→")
                        Button { model.jump(toExerciseIndex: exIdx) } label: {
                            HStack {
                                Text(glyph).foregroundStyle(theme.accent2)
                                Text(model.displayName(forExercise: exIdx)).foregroundStyle(theme.ink)
                                Spacer()
                                Text("\(done)/\(steps.count)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(theme.inkSoft)
                            }
                            .padding(theme.spacing[2])
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
                        }
                        .accessibilityIdentifier("jump.exercise.\(exIdx)")
                    }
                }
            }
        }
        .padding(theme.spacing[5])
        .background(theme.bg)
    }
}
```

- [ ] **Step 3: Write `Pulse/Features/ActiveWorkout/Sheets/HistorySheet.swift`**

```swift
import SwiftUI

struct HistorySheet: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme
    @State private var sets: [SessionSet] = []

    private var exIdx: Int { model.currentStep.exIdx }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Text("RECENT")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            Text(model.displayName(forExercise: exIdx))
                .font(.title3.bold()).foregroundStyle(theme.ink)
            ForEach(Array(sets.enumerated()), id: \.offset) { _, s in
                HStack {
                    Text("\(s.reps) reps").foregroundStyle(theme.ink)
                    Spacer()
                    Text(WeightFormat.kg(s.weight))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.inkSoft)
                }
                .padding(theme.spacing[2])
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
            }
            Spacer()
        }
        .padding(theme.spacing[5])
        .background(theme.bg)
        .task { sets = await model.history(for: exIdx) }
    }
}
```

- [ ] **Step 4: Remove the three sheet stubs from `_Stubs.swift`.**

- [ ] **Step 5: Add UI test for AC10 (Jump) and re-run the Task 8 swap test**

```swift
    func testJumpListLandsOnExercise() {
        let app = launch()
        app.buttons["today.startWorkout"].tap()
        app.buttons["pre.begin"].tap()
        app.buttons["active.chip.jump"].tap()
        XCTAssertTrue(app.buttons["jump.exercise.2"].waitForExistence(timeout: 3))
        app.buttons["jump.exercise.2"].tap()
        XCTAssertTrue(app.otherElements["activeFlow.phase.active"].waitForExistence(timeout: 3))
        // tri cable is a superset → eyebrow carries a superset label
        XCTAssertTrue(app.staticTexts["active.eyebrow"].label.contains("1A"))
    }
```

- [ ] **Step 6: Build + run the swap + jump UI tests**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseUITests/ActiveWorkoutFlowTests/testSwapShowsSwappedEyebrow \
  -only-testing:PulseUITests/ActiveWorkoutFlowTests/testJumpListLandsOnExercise
```
Expected: PASS for both.

- [ ] **Step 7: Commit**

```bash
git add Pulse/Features/ActiveWorkout/Sheets PulseUITests/ActiveWorkoutFlowTests.swift Pulse/Features/ActiveWorkout/_Stubs.swift
git commit -m "feat: Swap / Jump / History bottom sheets (BAK-14)"
```

---

## Task 11: `SummaryView` receipt + persist stub + delete stubs — View assembly

**Files:**
- Create: `Pulse/Features/ActiveWorkout/SummaryView.swift`
- Delete: `Pulse/Features/ActiveWorkout/_Stubs.swift` (last stubs removed)

- [ ] **Step 1: Write `Pulse/Features/ActiveWorkout/SummaryView.swift`**

```swift
import SwiftUI

struct SummaryView: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    var body: some View {
        let s = model.summary
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("WORKOUT COMPLETE · \(dateString)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            Text(model.workout.name + ".")
                .font(.largeTitle.bold()).foregroundStyle(theme.ink)
            Text("Day \(model.workout.order + 1) · program")
                .font(.subheadline).foregroundStyle(theme.inkSoft)

            // 2×2 stat grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                statBox("VOLUME", value: volumeK(s.totalVolume), sub: "kg total")
                statBox("TIME", value: "\(s.elapsedMinutes)", sub: "min elapsed")
                statBox("SETS", value: "\(s.completedSets)/\(s.totalSets)", sub: "complete", dim: true)
                statBox("PR", value: "+\(s.prCount)", sub: "this session", accent: true)
            }

            Text("LOG")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(theme.inkSoft)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.logRows) { row in
                        HStack {
                            Text("\(row.id + 1)").font(.caption.bold())
                                .frame(width: 20, height: 20)
                                .background(theme.surface2, in: Circle())
                            VStack(alignment: .leading) {
                                Text(row.name).font(.subheadline).foregroundStyle(theme.ink)
                                Text(row.summaryLine).font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(theme.inkSoft)
                            }
                            Spacer()
                            if row.isPR { Text("PR").font(.caption2.bold()).foregroundStyle(theme.accent2) }
                            Text(volumeK(row.volume)).foregroundStyle(theme.ink)
                        }
                        .padding(theme.spacing[2])
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
                    }
                }
            }
            .accessibilityIdentifier("summary.log")

            HStack(spacing: 8) {
                Button("Edit log") { }            // destination deferred per spec; inert v1
                    .buttonStyle(PulseButtonStyle(kind: .secondary))
                Button("Done →") { model.endWorkout() }
                    .buttonStyle(PulseButtonStyle())
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("summary.done")
            }
        }
        .padding(theme.spacing[5])
        .accessibilityIdentifier("summary.root")
    }

    private func statBox(_ label: String, value: String, sub: String,
                         dim: Bool = false, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(.caption2, design: .monospaced)).foregroundStyle(theme.inkSoft)
            Text(value).font(.title.bold())
                .foregroundStyle(dim ? theme.inkSoft : theme.ink)
            Text(sub).font(.caption2).foregroundStyle(theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing[2])
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: theme.radiusCard)
            .strokeBorder(accent ? theme.accent2 : .clear, lineWidth: 2))
    }

    private func volumeK(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v / 1000) : String(Int(v))
    }
    private var dateString: String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: .now).uppercased()
    }
}

#Preview {
    let m = ActiveWorkoutModel(exerciseRepo: MockExerciseRepository(),
                               historyRepo: MockHistoryRepository(),
                               sessionWriter: MockSessionWriter())
    m.startWorkout(SampleData.workout); m.beginSets()
    m.logSet(reps: 12, weight: 100); m.afterRest(); m.logSet(reps: 10, weight: 110)
    return SummaryView(model: m).environment(Theme())
}
```

- [ ] **Step 2: Delete the now-empty stub file**

```bash
rm Pulse/Features/ActiveWorkout/_Stubs.swift
```

- [ ] **Step 3: Add UI test for AC16–17 (summary populated + Done returns to Today)**

```swift
    func testSummaryShowsAndDoneReturnsToTabBar() {
        let app = launch()
        app.buttons["today.startWorkout"].tap()
        app.buttons["pre.begin"].tap()
        // log everything: log, skip rest, repeat, until summary appears
        for _ in 0..<20 {
            if app.otherElements["activeFlow.phase.summary"].exists { break }
            if app.buttons["active.log"].exists { app.buttons["active.log"].tap() }
            if app.buttons["rest.skip"].exists { app.buttons["rest.skip"].tap() }
        }
        XCTAssertTrue(app.otherElements["summary.root"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["summary.log"].exists)
        app.buttons["summary.done"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 3))
    }
```

- [ ] **Step 4: Generate + run the FULL test suite (unit + UI)**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: all `WorkoutStepTests`, `ActiveWorkoutMocksTests`, `PRMathTests`, `ActiveWorkoutModelTests`, and `ActiveWorkoutFlowTests` green; `BUILD SUCCEEDED`/`TEST SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/ActiveWorkout/SummaryView.swift PulseUITests/ActiveWorkoutFlowTests.swift
git rm Pulse/Features/ActiveWorkout/_Stubs.swift
git commit -m "feat: SummaryView receipt + full active-flow wiring (BAK-14)"
```

---

## Task 12: Theme-parity snapshot/verification + PR

**Files:**
- (No new source) — verification + PR.

- [ ] **Step 1: Add a Mint-palette UI test (AC19) to `ActiveWorkoutFlowTests.swift`**

Launch with a launch argument that forces the Mint palette, then assert the active phase still renders its key elements (token-driven, no hardcoded colors). Add to `AppShell` an env-gated palette override:

In `AppShell.init` (guarded):
```swift
init() {
    if ProcessInfo.processInfo.arguments.contains("-uiTestMint") {
        UserDefaults.standard.set(Palette.mint.rawValue, forKey: "pulse-pal")
    }
}
```

Test:
```swift
    func testRendersInMintPalette() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestMint"]
        app.launch()
        app.buttons["today.startWorkout"].tap()
        app.buttons["pre.begin"].tap()
        XCTAssertTrue(app.otherElements["activeFlow.phase.active"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["active.log"].exists)
    }
```

- [ ] **Step 2: Run the full suite once more**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 3: Commit + push + open PR (⏸ confirm with the user before pushing)**

```bash
git add Pulse/App/AppShell.swift PulseUITests/ActiveWorkoutFlowTests.swift
git commit -m "test: Mint-palette parity for active flow (BAK-14)"
git push -u origin feature/BAK-14-workout-active-flow
gh pr create --fill --base main
```
Expected: PR opened, CI green. Then run `code-reviewer` + `/security-review` per the workflow gates.

---

## Self-Review notes

- **AC coverage:** AC1–2 (Task 6 UI tests + Task 4 unit), AC3 (Task 1 `buildSteps`), AC4–6 (Task 4 unit + Task 8 UI), AC7–8 (Task 4 unit + Task 9 UI), AC9 (Task 4 `skipSet`), AC10 (Task 4 unit + Task 10 UI), AC11 (Task 4 unit + Task 8 UI), AC12 (Task 8 failure rendering), AC13 (Task 4 label map + Task 8 pill), AC14 (Task 8 rep schedule), AC15 (Task 8 partner peek), AC16 (Task 4 summary + Task 11 UI), AC17 (Task 4 `endWorkout` + Task 6/11 UI), AC18 (Task 5 transition), AC19 (Task 12 Mint test).
- **Product decisions honored:** kg-only copy + ±2.5 kg steppers + `WeightFormat` helper (Task 3/8); Epley PR derived from history baseline (Task 3/4); failure logs `reps:0,weight:0` excluded from volume/PR (Task 4); skip-on-final is no-op clamp (Task 4); rest = constant 90 s (Task 4); native `.sheet` + detents + 26pt radius (Task 5/10).
- **Repository-only data access:** every data read goes through `WorkoutRepository`/`ExerciseRepository`/`HistoryRepository`/`SessionWriter` mocks; the model never touches Supabase (Task 2).
- **Downstream exposure:** the model publishes `phase`, `currentStep`/`nextStep`, absolute `restEndsAt`, and `doneSteps.count / steps.count` for the future Live Activity (Task 4).
- **TDD vs view assembly:** logic (Tasks 1–4) is strict failing-test-first; views (Tasks 5–11) are concrete SwiftUI + `#Preview` + XCUITest assertions on `accessibilityIdentifier`s.
- **Theme tokens only:** all views read `Theme`; the Mint test guards parity (Task 12).
- **XcodeGen:** every task that adds files runs `xcodegen generate`; the `.xcodeproj` is never hand-edited.
- **Dependencies on BAK-7 helpers** (`Lockup`, `PulseButtonStyle`, `Stepper2`/`StepperField`, sheet styling): noted inline; substitute local layout-only views if a helper is absent.
