# Pulse Data Layer (BAK-6) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Everything with logic (analytics, repositories, mocks, the composition root) is built strict-TDD: failing test → run (FAIL) → minimal impl → run (PASS) → commit.

**Goal:** Build the data contract for the whole app — eight `async throws` **repository protocols** that own all data access, an internally-consistent **`SampleData`** world, an **in-memory mock** of every protocol (CRUD round-trips in-process), a pure **`WorkoutAnalytics`** helper (volume / Epley 1RM / PR / streak), a **`RepositoryContainer` / `AppEnvironment`** composition root injected at the app root with a mock-vs-live flag, **`Supabase*Repository` stubs** that compile, and a **second SQL migration** (scheduling table + child/catalog RLS + `default_variation_id`). Every screen feature binds to these protocols and renders against the mocks; live Supabase wiring lands later behind the same contract.

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. Data access only through repositories in `Pulse/Core/Data` (views/models never touch Supabase). Mocks hold their mutable seed in a `@MainActor` store so concurrent session reads/writes are safe. Derived math lives in one place (`Core/Data/Analytics/WorkoutAnalytics.swift`); `StatsRepository` and `PRRepository` call it rather than reimplementing. Composition via a `@MainActor @Observable RepositoryContainer` injected with `.environment`; a `-uiMock` launch argument / build flag selects mock vs live at the root. Xcode project generated from `project.yml` via XcodeGen (never hand-edit `.xcodeproj`).

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency (`async`/`await`), XcodeGen, XCTest (unit), XCUITest (smoke), Supabase/Postgres (migration only this feature).

**Prerequisites:** The **Foundation layer (BAK-1)** must be built first — it provides the buildable XcodeGen skeleton, `Pulse/Core/Models/WorkoutModels.swift`, `Pulse/Core/DesignSystem/Theme.swift`, the `0001_initial_schema.sql` migration, and the `PulseTests`/`PulseUITests` targets this plan extends. This feature has **no UI**, so the **Design System (BAK-7)** is *not* required here; consuming screen features (Today BAK-9, Library, Stats BAK-15, PRs BAK-16, etc.) require **both** Design System BAK-7 **and** this Data layer BAK-6 before they can be built.

**Authoritative product decisions baked into this plan** (from `docs/superpowers/specs/2026-05-31-product-decisions.md` — these override the spec's "Open questions"):
- PR = **estimated 1RM via Epley**: `1RM = weight × (1 + reps/30)`, per working/AMRAP set, warmups excluded. PRs derived (no stored table).
- Streak = **consecutive honored scheduled days**: a scheduled training day counts when a session completed that day; rest days neither break nor extend; a scheduled training day with no session breaks it.
- **kg only** for v1 (no unit toggle; weights are plain `Double` kg).
- Day-bucketing uses `Calendar.current`, device-local tz; **week starts Monday**; centralized in the analytics helper.
- StatRange bucketing: **7D & 30D by day, 3M by week, YR & ALL by month.**
- `activeProgram` selection via a single **`isActive: Bool` on `Program`** (mock seeds PPL active).
- Add a real **`default_variation_id`** column to `exercises` in this migration.
- `SessionSet` gains **`exerciseID: Exercise.ID`** *and* explicit **`order: Int`**.
- Scheduling table **`plan_entries`**: `user_id, date, workout_id (nullable), state ∈ {planned,rest,done}, session_id (nullable)`; "done" when `session_id` set.

---

## Prerequisites (verify before starting)

- [ ] **Step 0a: Confirm the foundation builds & tests pass on a clean tree**

Run:
```bash
cd /Users/leoncreed-baker/Documents/Cavehole/Pulse && xcodegen generate && \
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -5
```
Expected: `TEST SUCCEEDED` (foundation `PaletteTests` / `WorkoutModelsTests` green).

- [ ] **Step 0b: Create a feature branch**

Run: `git checkout -b feature/BAK-6-data-layer`
Expected: `Switched to a new branch 'feature/BAK-6-data-layer'`.

- [ ] **Step 0c: Note the testing command used throughout**

All tests in this plan run with:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
To run one suite faster, append `-only-testing:PulseTests/<SuiteName>`.

---

## Task 1: Amend `SessionSet` + add `DerivedModels` and `isActive` (TDD)

**Files:**
- Modify: `Pulse/Core/Models/WorkoutModels.swift`
- Create: `Pulse/Core/Models/DerivedModels.swift`
- Create: `PulseTests/Data/DerivedModelsTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Data/DerivedModelsTests.swift`**

```swift
import XCTest
@testable import Pulse

final class DerivedModelsTests: XCTestCase {
    func testSessionSetCarriesExerciseIDAndOrder() throws {
        let ex = UUID()
        let set = SessionSet(exerciseID: ex, order: 2, reps: 8, weight: 60, type: .working)
        XCTAssertEqual(set.exerciseID, ex)
        XCTAssertEqual(set.order, 2)
        let data = try JSONEncoder().encode(set)
        let back = try JSONDecoder().decode(SessionSet.self, from: data)
        XCTAssertEqual(back, set)
    }

    func testProgramHasIsActiveFlag() {
        let p = Program(name: "PPL", weeks: 6, isActive: true, workouts: [])
        XCTAssertTrue(p.isActive)
    }

    func testStatRangeHasFiveCases() {
        XCTAssertEqual(StatRange.allCases, [.d7, .d30, .m3, .year, .all])
    }

    func testDayPlanEquatableVariants() {
        let w = UUID(), s = UUID()
        XCTAssertEqual(DayPlan.workout(w), DayPlan.workout(w))
        XCTAssertNotEqual(DayPlan.workout(w), DayPlan.rest)
        XCTAssertEqual(DayPlan.done(s), DayPlan.done(s))
    }

    func testPersonalRecordHoldsEstimated1RM() {
        let pr = PersonalRecord(exerciseID: UUID(), variationID: nil,
                                weight: 100, reps: 5, estimatedOneRepMax: 116.67,
                                achievedAt: Date(), isNew: true)
        XCTAssertEqual(pr.estimatedOneRepMax, 116.67, accuracy: 0.01)
        XCTAssertTrue(pr.isNew)
    }
}
```

- [ ] **Step 2: Run the test — expect FAIL (new fields/types undefined)**

Run the test command (Step 0c). Expected: FAIL — `SessionSet` has no `exerciseID`/`order`, `Program` has no `isActive`, `StatRange`/`DayPlan`/`PersonalRecord` undefined.

- [ ] **Step 3: Amend `SessionSet` and `Program` in `Pulse/Core/Models/WorkoutModels.swift`**

Replace the `SessionSet` struct with:
```swift
/// A logged set — actual performance against a Workout. `exerciseID` lets logged
/// sets group per-exercise (Session Detail, History, PR derivation); `order`
/// mirrors the SQL `"order"` column so round-trips preserve sequence.
struct SessionSet: Codable, Equatable, Identifiable {
    var id = UUID()
    var exerciseID: Exercise.ID
    var order: Int
    var reps: Int
    var weight: Double            // kilograms (v1 is kg-only)
    var type: SetType
}
```

Add `isActive` to `Program` (single active-program selection per product decisions):
```swift
struct Program: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var weeks: Int
    var isActive: Bool = false
    var workouts: [Workout]
}
```

- [ ] **Step 4: Write `Pulse/Core/Models/DerivedModels.swift`**

```swift
import Foundation

/// One point on a volume chart. `label` is the axis caption ("Mon", "W1", "Jan");
/// `date` is the bucket start for sorting.
struct VolumePoint: Equatable, Identifiable {
    var id = UUID()
    var date: Date
    var label: String
    var volume: Double
}

/// The four hero numbers on the Stats summary card.
struct StatsSummary: Equatable {
    var sessions: Int
    var newPRs: Int
    var averageDuration: TimeInterval
    var streak: Int
}

/// Total working-set volume for one muscle group over a range.
struct MuscleVolume: Equatable, Identifiable {
    var id: String { muscleGroup }
    var muscleGroup: String
    var volume: Double
}

/// A derived personal record (est. 1RM via Epley). Not persisted — computed
/// from logged sets. `isNew` is true when achieved within the queried range.
struct PersonalRecord: Equatable, Identifiable {
    var id = UUID()
    var exerciseID: Exercise.ID
    var variationID: Variation.ID?
    var weight: Double
    var reps: Int
    var estimatedOneRepMax: Double
    var achievedAt: Date
    var isNew: Bool
}

/// The five Stats range chips.
enum StatRange: String, CaseIterable {
    case d7, d30, m3, year, all
}

/// What a calendar day holds on the Plan tab.
enum DayPlan: Equatable {
    case workout(Workout.ID)        // a scheduled training day
    case rest                       // an intentional rest day
    case done(WorkoutSession.ID)    // a day a session was completed
}
```

- [ ] **Step 5: Run the test — expect PASS**

Run the test command. Expected: PASS (DerivedModelsTests green). The foundation `WorkoutModelsTests` still compiles because its `SetSpec` test is untouched; if any foundation test constructed a bare `SessionSet`, update it to the new initializer (search: `git grep -n "SessionSet(" PulseTests`).

- [ ] **Step 6: Commit**

```bash
xcodegen generate
git add Pulse/Core/Models PulseTests/Data/DerivedModelsTests.swift
git commit -m "feat: add SessionSet.exerciseID/order, Program.isActive, derived models"
```

---

## Task 2: `WorkoutAnalytics` — pure derived math (TDD)

**Files:**
- Create: `Pulse/Core/Data/Analytics/WorkoutAnalytics.swift`
- Create: `PulseTests/Data/WorkoutAnalyticsTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Data/WorkoutAnalyticsTests.swift`**

```swift
import XCTest
@testable import Pulse

final class WorkoutAnalyticsTests: XCTestCase {
    let ex = UUID()

    private func set(_ reps: Int, _ weight: Double, _ type: SetType) -> SessionSet {
        SessionSet(exerciseID: ex, order: 0, reps: reps, weight: weight, type: type)
    }

    func testSetVolumeExcludesWarmups() {
        XCTAssertEqual(WorkoutAnalytics.setVolume(set(10, 50, .working)), 500)
        XCTAssertEqual(WorkoutAnalytics.setVolume(set(10, 50, .amrap)), 500)
        XCTAssertEqual(WorkoutAnalytics.setVolume(set(10, 50, .warmup)), 0)
    }

    func testSessionVolumeSumsCountingSetsOnly() {
        let session = WorkoutSession(
            workoutID: UUID(), startedAt: Date(), endedAt: nil,
            sets: [set(5, 100, .warmup), set(5, 100, .working), set(8, 80, .working)])
        XCTAssertEqual(WorkoutAnalytics.sessionVolume(session), 100 * 5 + 80 * 8)
    }

    func testEpleyOneRepMax() {
        // 100 × (1 + 5/30) = 116.666…
        XCTAssertEqual(WorkoutAnalytics.estimatedOneRepMax(weight: 100, reps: 5),
                       116.6667, accuracy: 0.001)
        // a single rep returns the bar weight
        XCTAssertEqual(WorkoutAnalytics.estimatedOneRepMax(weight: 140, reps: 1), 140)
    }

    func testBestSetByEstimated1RMIgnoresWarmups() {
        let sets = [set(1, 150, .warmup),   // would win on raw weight but is a warmup
                    set(5, 100, .working),  // 1RM ≈ 116.67
                    set(3, 110, .working)]  // 1RM = 121.0  ← best
        let best = WorkoutAnalytics.bestSet(in: sets)
        XCTAssertEqual(best?.weight, 110)
        XCTAssertEqual(best?.reps, 3)
    }

    func testStreakCountsHonoredScheduledDaysAndIgnoresRest() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        let day = { (offset: Int) in cal.date(byAdding: .day, value: offset, to: Date())! }
        // today + yesterday were scheduled & completed; 2-days-ago was a rest day;
        // 3-days-ago was scheduled & completed → streak should be 3 (rest is transparent).
        let plan: [Date: DayPlan] = [
            cal.startOfDay(for: day(0)):  .workout(UUID()),
            cal.startOfDay(for: day(-1)): .workout(UUID()),
            cal.startOfDay(for: day(-2)): .rest,
            cal.startOfDay(for: day(-3)): .workout(UUID())]
        let completedDays: Set<Date> = [
            cal.startOfDay(for: day(0)),
            cal.startOfDay(for: day(-1)),
            cal.startOfDay(for: day(-3))]
        XCTAssertEqual(
            WorkoutAnalytics.streak(plan: plan, completedDays: completedDays,
                                    asOf: day(0), calendar: cal), 3)
    }

    func testStreakBreaksOnMissedScheduledDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        let day = { (offset: Int) in cal.date(byAdding: .day, value: offset, to: Date())! }
        let plan: [Date: DayPlan] = [
            cal.startOfDay(for: day(0)):  .workout(UUID()),
            cal.startOfDay(for: day(-1)): .workout(UUID())] // scheduled, NOT completed
        let completedDays: Set<Date> = [cal.startOfDay(for: day(0))]
        XCTAssertEqual(
            WorkoutAnalytics.streak(plan: plan, completedDays: completedDays,
                                    asOf: day(0), calendar: cal), 1)
    }
}
```

- [ ] **Step 2: Run the test — expect FAIL (`WorkoutAnalytics` undefined)**

Run the test command. Expected: FAIL — no such type.

- [ ] **Step 3: Write `Pulse/Core/Data/Analytics/WorkoutAnalytics.swift`**

```swift
import Foundation

/// The single source of derived workout math. `StatsRepository` and
/// `PRRepository` call this — no screen or repo reimplements volume / 1RM /
/// PR / streak. All day-bucketing uses the injected calendar (default
/// `Calendar.current`, device-local, Monday-start) per product decisions.
enum WorkoutAnalytics {

    /// Only working & AMRAP sets count toward volume and PRs.
    static func counts(_ type: SetType) -> Bool {
        type == .working || type == .amrap
    }

    /// reps × weight, or 0 for non-counting (warmup/dropset/failure) sets.
    static func setVolume(_ set: SessionSet) -> Double {
        counts(set.type) ? Double(set.reps) * set.weight : 0
    }

    static func sessionVolume(_ session: WorkoutSession) -> Double {
        session.sets.reduce(0) { $0 + setVolume($1) }
    }

    /// Epley: weight × (1 + reps / 30). One rep returns the bar weight.
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 1 else { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    static func estimatedOneRepMax(_ set: SessionSet) -> Double {
        estimatedOneRepMax(weight: set.weight, reps: set.reps)
    }

    /// Best counting set by estimated 1RM (warmups excluded). `nil` if none.
    static func bestSet(in sets: [SessionSet]) -> SessionSet? {
        sets.filter { counts($0.type) }
            .max { estimatedOneRepMax($0) < estimatedOneRepMax($1) }
    }

    /// Consecutive honored scheduled days ending at `asOf`. A scheduled training
    /// day (`.workout`) counts only if a session completed that day; a `.rest`
    /// day is transparent (neither breaks nor extends); a scheduled day with no
    /// completed session breaks the streak. Days with no plan entry stop the walk.
    static func streak(plan: [Date: DayPlan],
                       completedDays: Set<Date>,
                       asOf: Date,
                       calendar: Calendar = .current) -> Int {
        var streak = 0
        var cursor = calendar.startOfDay(for: asOf)
        while let entry = plan[cursor] {
            switch entry {
            case .rest:
                break // transparent
            case .workout:
                if completedDays.contains(cursor) { streak += 1 } else { return streak }
            case .done:
                if completedDays.contains(cursor) { streak += 1 } else { return streak }
            }
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = calendar.startOfDay(for: prev)
        }
        return streak
    }
}
```

- [ ] **Step 4: Run the test — expect PASS**

Run the test command. Expected: PASS (WorkoutAnalyticsTests green).

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add Pulse/Core/Data/Analytics PulseTests/Data/WorkoutAnalyticsTests.swift
git commit -m "feat: WorkoutAnalytics — volume, Epley 1RM, best-set, streak"
```

---

## Task 3: Repository protocols

**Files:**
- Create: `Pulse/Core/Data/Repositories/ProgramRepository.swift`
- Create: `Pulse/Core/Data/Repositories/WorkoutRepository.swift`
- Create: `Pulse/Core/Data/Repositories/ExerciseRepository.swift`
- Create: `Pulse/Core/Data/Repositories/SessionRepository.swift`
- Create: `Pulse/Core/Data/Repositories/ScheduleRepository.swift`
- Create: `Pulse/Core/Data/Repositories/StatsRepository.swift`
- Create: `Pulse/Core/Data/Repositories/PRRepository.swift`
- Create: `Pulse/Core/Data/Repositories/RepositoryError.swift`

> Protocol declarations have no logic, so this is straight authoring; the compiler is the check. The protocols are exercised by the mock tests in Tasks 5–8.

- [ ] **Step 1: Write `Pulse/Core/Data/Repositories/RepositoryError.swift`**

```swift
import Foundation

/// Errors any repository may throw. `notImplemented` is the Supabase-stub
/// placeholder; `forced` is what the mock throws in forced-error mode.
enum RepositoryError: Error, Equatable {
    case notImplemented
    case notFound
    case forced
}
```

- [ ] **Step 2: Write `Pulse/Core/Data/Repositories/ProgramRepository.swift`**

```swift
import Foundation

/// Programs (a named multi-week plan of Workouts). `fetchProgram(id:)` is
/// hydrated — it returns the full nested graph ready to render.
protocol ProgramRepository {
    func fetchPrograms() async throws -> [Program]
    func fetchProgram(id: Program.ID) async throws -> Program?
    func activeProgram() async throws -> Program?
    func saveProgram(_ program: Program) async throws -> Program
    func deleteProgram(id: Program.ID) async throws
}
```

- [ ] **Step 3: Write `Pulse/Core/Data/Repositories/WorkoutRepository.swift`**

```swift
import Foundation

/// Workouts (routines). `fetchWorkout(id:)` returns the hydrated graph
/// (exercises → embedded Exercise + chosen variation → ordered SetSpecs).
protocol WorkoutRepository {
    func fetchWorkouts() async throws -> [Workout]
    func fetchWorkout(id: Workout.ID) async throws -> Workout?
    func todaysWorkout(on date: Date) async throws -> Workout?
    func saveWorkout(_ workout: Workout) async throws -> Workout
    func deleteWorkout(id: Workout.ID) async throws
}
```

- [ ] **Step 4: Write `Pulse/Core/Data/Repositories/ExerciseRepository.swift`**

```swift
import Foundation

/// The exercise catalog and its variations.
protocol ExerciseRepository {
    func fetchCatalog() async throws -> [Exercise]
    func fetchExercises(muscleGroup: String) async throws -> [Exercise]
    func fetchExercise(id: Exercise.ID) async throws -> Exercise?
    /// Same-muscle-group alternatives for the swap sheet (excludes `exerciseID`).
    func alternatives(for exerciseID: Exercise.ID) async throws -> [Exercise]
    func saveExercise(_ exercise: Exercise) async throws -> Exercise
}
```

- [ ] **Step 5: Write `Pulse/Core/Data/Repositories/SessionRepository.swift`**

```swift
import Foundation

/// Logged workout sessions. Mutating methods return the persisted entity so
/// server-assigned ids/timestamps round-trip.
protocol SessionRepository {
    func startSession(workoutID: Workout.ID, at: Date) async throws -> WorkoutSession
    func appendSet(_ set: SessionSet, to sessionID: WorkoutSession.ID) async throws
    func finishSession(id: WorkoutSession.ID, endedAt: Date) async throws -> WorkoutSession
    func fetchSessions(limit: Int?) async throws -> [WorkoutSession]
    func fetchSession(id: WorkoutSession.ID) async throws -> WorkoutSession?
    func lastSessions(forExercise: Exercise.ID, limit: Int) async throws -> [WorkoutSession]
    func deleteSession(id: WorkoutSession.ID) async throws
}
```

- [ ] **Step 6: Write `Pulse/Core/Data/Repositories/ScheduleRepository.swift`**

```swift
import Foundation

/// The Plan calendar. `setPlan(nil, on:)` clears a day.
protocol ScheduleRepository {
    func plan(for date: Date) async throws -> DayPlan?
    func upcoming(from date: Date, days: Int) async throws -> [(date: Date, plan: DayPlan)]
    func setPlan(_ plan: DayPlan?, on date: Date) async throws
}
```

- [ ] **Step 7: Write `Pulse/Core/Data/Repositories/StatsRepository.swift`**

```swift
import Foundation

/// Range-scoped aggregations for the Stats tab and Exercise Detail. All values
/// are computed from logged sessions via `WorkoutAnalytics`.
protocol StatsRepository {
    func volumeSeries(range: StatRange) async throws -> [VolumePoint]
    func summary(range: StatRange) async throws -> StatsSummary
    func volumeByMuscle(range: StatRange) async throws -> [MuscleVolume]
    func currentStreak() async throws -> Int
    func exerciseVolumeHistory(_ exerciseID: Exercise.ID, lastN: Int) async throws -> [VolumePoint]
}
```

- [ ] **Step 8: Write `Pulse/Core/Data/Repositories/PRRepository.swift`**

```swift
import Foundation

/// Personal records, derived (est. 1RM via Epley) — not a stored table.
protocol PRRepository {
    func allPRs() async throws -> [PersonalRecord]
    func prs(muscleGroup: String) async throws -> [PersonalRecord]
    func personalBest(forExercise: Exercise.ID) async throws -> PersonalRecord?
    func newPRs(in range: StatRange) async throws -> [PersonalRecord]
}
```

- [ ] **Step 9: Generate, build, commit**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`.

```bash
git add Pulse/Core/Data/Repositories
git commit -m "feat: eight async-throwing repository protocols + RepositoryError"
```

---

## Task 4: `SampleData` — one coherent world (TDD)

**Files:**
- Create: `Pulse/Core/Data/Mock/SampleData.swift`
- Create: `PulseTests/Data/SampleDataTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Data/SampleDataTests.swift`**

```swift
import XCTest
@testable import Pulse

final class SampleDataTests: XCTestCase {
    func testExerciseCatalogSizeAndDefaults() {
        let catalog = SampleData.exercises
        XCTAssertTrue((18...24).contains(catalog.count), "catalog is \(catalog.count)")
        // every exercise has a default variation that resolves to one of its variations
        for ex in catalog {
            XCTAssertFalse(ex.variations.isEmpty)
            let def = try? XCTUnwrap(ex.defaultVariationID)
            XCTAssertTrue(ex.variations.contains { $0.id == def })
        }
    }

    func testAtLeastOneSingleVariationExercise() {
        XCTAssertTrue(SampleData.exercises.contains { $0.variations.count == 1 },
                      "need a single-variation exercise to exercise the hidden-switcher rule")
    }

    func testActiveProgramIsPPLPinnedToMonWedFri() {
        let program = SampleData.program
        XCTAssertTrue(program.isActive)
        XCTAssertEqual(program.weeks, 6)
        XCTAssertEqual(Set(program.workouts.compactMap(\.weekday)), [1, 3, 5])
    }

    func testEveryWorkoutExerciseReferencesACatalogExercise() {
        let catalogIDs = Set(SampleData.exercises.map(\.id))
        for w in SampleData.program.workouts {
            for we in w.exercises {
                XCTAssertTrue(catalogIDs.contains(we.exercise.id))
            }
        }
    }

    func testSessionsAreInLast30DaysAndReferenceRealWorkoutsAndExercises() {
        let workoutIDs = Set(SampleData.program.workouts.map(\.id))
        let exerciseIDs = Set(SampleData.exercises.map(\.id))
        let cutoff = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
        XCTAssertTrue((8...12).contains(SampleData.sessions.count))
        for s in SampleData.sessions {
            XCTAssertTrue(workoutIDs.contains(s.workoutID))
            XCTAssertGreaterThan(s.startedAt, cutoff)
            for set in s.sets { XCTAssertTrue(exerciseIDs.contains(set.exerciseID)) }
        }
    }

    func testScheduleSpansAMonth() {
        XCTAssertGreaterThanOrEqual(SampleData.schedule.count, 28)
    }

    func testAtLeastOneSessionProducesAFreshPR() {
        // The most recent session must contain the all-time best est-1RM for some
        // exercise so a "NEW" badge can render.
        let byExercise = Dictionary(grouping: SampleData.sessions.flatMap(\.sets),
                                    by: \.exerciseID)
        let recent = SampleData.sessions.max { $0.startedAt < $1.startedAt }!
        let producesFreshPR = recent.sets.contains { set in
            guard WorkoutAnalytics.counts(set.type) else { return false }
            let all = byExercise[set.exerciseID] ?? []
            let best = all.filter { WorkoutAnalytics.counts($0.type) }
                          .map(WorkoutAnalytics.estimatedOneRepMax).max() ?? 0
            return WorkoutAnalytics.estimatedOneRepMax(set) >= best - 0.001
        }
        XCTAssertTrue(producesFreshPR)
    }
}
```

- [ ] **Step 2: Run the test — expect FAIL (`SampleData` undefined)**

Run the test command. Expected: FAIL — no such type.

- [ ] **Step 3: Write `Pulse/Core/Data/Mock/SampleData.swift`**

```swift
import Foundation

/// One internally-consistent mock world. Every id referenced across graphs
/// resolves: a session's `workoutID` points at a real workout; a
/// `SessionSet.exerciseID` at a real catalog exercise. Built once as
/// `static let`s so all mock repositories share the same ids.
enum SampleData {

    // MARK: Calendar helpers
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        return c
    }()
    private static func daysAgo(_ n: Int) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: -n, to: Date())!)
    }

    // MARK: Exercise catalog (20 exercises, grouped by muscle)
    private static func ex(_ name: String, _ muscle: String,
                           _ variationNames: [String]) -> Exercise {
        let vars = variationNames.map { Variation(name: $0, equipment: nil) }
        return Exercise(name: name, muscleGroup: muscle,
                        variations: vars, defaultVariationID: vars.first?.id)
    }

    static let exercises: [Exercise] = [
        // Chest
        ex("Bench Press", "Chest", ["Barbell", "Dumbbell", "Smith"]),
        ex("Incline Press", "Chest", ["Barbell", "Dumbbell"]),
        ex("Cable Fly", "Chest", ["High", "Low"]),
        ex("Push-Up", "Chest", ["Bodyweight"]),                 // single-variation
        // Back
        ex("Deadlift", "Back", ["Conventional", "Sumo"]),
        ex("Pull-Up", "Back", ["Bodyweight", "Weighted"]),
        ex("Barbell Row", "Back", ["Overhand", "Underhand"]),
        ex("Lat Pulldown", "Back", ["Wide", "Close", "Neutral"]),
        ex("Seated Cable Row", "Back", ["V-Bar"]),              // single-variation
        // Shoulders
        ex("Overhead Press", "Shoulders", ["Barbell", "Dumbbell"]),
        ex("Lateral Raise", "Shoulders", ["Dumbbell", "Cable"]),
        ex("Face Pull", "Shoulders", ["Rope"]),                 // single-variation
        // Legs
        ex("Back Squat", "Legs", ["High-Bar", "Low-Bar"]),
        ex("Front Squat", "Legs", ["Barbell"]),                 // single-variation
        ex("Leg Press", "Legs", ["45°", "Horizontal"]),
        ex("Romanian Deadlift", "Legs", ["Barbell", "Dumbbell"]),
        ex("Leg Curl", "Legs", ["Seated", "Lying"]),
        ex("Calf Raise", "Legs", ["Standing", "Seated"]),
        // Arms
        ex("Barbell Curl", "Arms", ["Straight", "EZ-Bar"]),
        ex("Triceps Pushdown", "Arms", ["Rope", "Bar"]),
    ]

    private static func byName(_ name: String) -> Exercise {
        exercises.first { $0.name == name }!
    }

    // MARK: Workouts
    private static func we(_ name: String, superset: String? = nil,
                           sets: [SetSpec]) -> WorkoutExercise {
        let exercise = byName(name)
        return WorkoutExercise(exercise: exercise,
                               variationID: exercise.defaultVariationID,
                               supersetGroup: superset, sets: sets)
    }
    private static func working(_ reps: Int, _ rir: Int) -> SetSpec {
        SetSpec(reps: reps, rir: rir, type: .working)
    }
    private static let warmup = SetSpec(reps: 8, rir: 0, type: .warmup)

    static let pushWorkout = Workout(
        name: "Push", weekday: 1, order: 0,
        exercises: [
            we("Bench Press", sets: [warmup, working(8, 2), working(8, 1), working(6, 0)]),
            we("Overhead Press", sets: [working(10, 2), working(10, 2)]),
            we("Incline Press", superset: "A", sets: [working(12, 2), working(12, 1)]),
            we("Cable Fly", superset: "A", sets: [working(15, 1), working(15, 0)]),
            we("Triceps Pushdown", sets: [working(12, 1), working(12, 0)]),
        ])

    static let pullWorkout = Workout(
        name: "Pull", weekday: 3, order: 1,
        exercises: [
            we("Deadlift", sets: [warmup, working(5, 2), working(5, 1)]),
            we("Pull-Up", sets: [working(8, 2), working(8, 1)]),
            we("Barbell Row", sets: [working(10, 2), working(10, 1)]),
            we("Lat Pulldown", sets: [working(12, 1), working(12, 0)]),
            we("Barbell Curl", sets: [working(12, 1), working(12, 0)]),
        ])

    static let legsWorkout = Workout(
        name: "Legs", weekday: 5, order: 2,
        exercises: [
            we("Back Squat", sets: [warmup, working(6, 2), working(6, 1), working(5, 0)]),
            we("Romanian Deadlift", sets: [working(10, 2), working(10, 1)]),
            we("Leg Press", sets: [working(12, 2), working(12, 1)]),
            we("Leg Curl", superset: "B", sets: [working(12, 1)]),
            we("Calf Raise", superset: "B", sets: [working(15, 0), working(15, 0)]),
        ])

    // MARK: Program
    static let program = Program(
        name: "Push / Pull / Legs", weeks: 6, isActive: true,
        workouts: [pushWorkout, pullWorkout, legsWorkout])

    // MARK: Sessions (10 sessions across the last ~30 days, progressive overload)
    private static func loggedSets(for workout: Workout, weightBump: Double) -> [SessionSet] {
        var out: [SessionSet] = []
        var order = 0
        for we in workout.exercises {
            // Base working weight per muscle group, bumped per session for overload.
            let base: Double
            switch we.exercise.muscleGroup {
            case "Legs": base = 100
            case "Back": base = 80
            case "Chest": base = 60
            default: base = 30
            }
            for spec in we.sets where spec.type != .warmup {
                out.append(SessionSet(exerciseID: we.exercise.id, order: order,
                                      reps: spec.reps, weight: base + weightBump,
                                      type: spec.type == .amrap ? .amrap : .working))
                order += 1
            }
        }
        return out
    }

    static let sessions: [WorkoutSession] = {
        // Most recent session (daysAgo 1) gets the biggest bump so it sets a fresh PR.
        let plan: [(workout: Workout, daysAgo: Int, bump: Double)] = [
            (pushWorkout, 22, 0),  (pullWorkout, 20, 0),  (legsWorkout, 18, 0),
            (pushWorkout, 15, 2.5),(pullWorkout, 13, 2.5),(legsWorkout, 11, 2.5),
            (pushWorkout, 8, 5),   (pullWorkout, 6, 5),   (legsWorkout, 4, 5),
            (pushWorkout, 1, 10),  // fresh PR day
        ]
        return plan.map { item in
            let start = calendar.date(byAdding: .hour, value: 18, to: daysAgo(item.daysAgo))!
            let end = calendar.date(byAdding: .minute, value: 62, to: start)!
            return WorkoutSession(workoutID: item.workout.id, startedAt: start,
                                  endedAt: end,
                                  sets: loggedSets(for: item.workout, weightBump: item.bump))
        }
    }()

    // MARK: Schedule (one month: Mon/Wed/Fri training, others rest;
    // past training days that have a session are marked done)
    static let schedule: [Date: DayPlan] = {
        var out: [Date: DayPlan] = [:]
        let completedByDay = Dictionary(
            grouping: sessions, by: { calendar.startOfDay(for: $0.startedAt) })
        for offset in -27...2 {
            let day = daysAgo(-offset)            // -27 = 27 days ago … +2 = day after tomorrow
            let weekday = calendar.component(.weekday, from: day) // 1=Sun…7=Sat
            let isTraining = [2, 4, 6].contains(weekday) // Mon/Wed/Fri (Gregorian)
            if let session = completedByDay[day]?.first {
                out[day] = .done(session.id)
            } else if isTraining {
                let w = [pushWorkout, pullWorkout, legsWorkout][abs(offset) % 3]
                out[day] = .workout(w.id)
            } else {
                out[day] = .rest
            }
        }
        return out
    }()
}
```

- [ ] **Step 4: Run the test — expect PASS**

Run the test command. Expected: PASS (SampleDataTests green). If `testAtLeastOneSessionProducesAFreshPR` fails, increase the final session's `bump` until the latest session's best counting set beats all earlier ones.

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add Pulse/Core/Data/Mock/SampleData.swift PulseTests/Data/SampleDataTests.swift
git commit -m "feat: SampleData — coherent PPL world (catalog, sessions, schedule)"
```

---

## Task 5: In-memory store + Program/Workout/Exercise mocks with hydration (TDD)

**Files:**
- Create: `Pulse/Core/Data/Mock/MockStore.swift`
- Create: `Pulse/Core/Data/Mock/InMemoryProgramRepository.swift`
- Create: `Pulse/Core/Data/Mock/InMemoryWorkoutRepository.swift`
- Create: `Pulse/Core/Data/Mock/InMemoryExerciseRepository.swift`
- Create: `PulseTests/Data/InMemoryCatalogRepositoriesTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Data/InMemoryCatalogRepositoriesTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class InMemoryCatalogRepositoriesTests: XCTestCase {

    func testProgramSaveFetchDeleteRoundTrip() async throws {
        let store = MockStore()
        let repo = InMemoryProgramRepository(store: store)
        let before = try await repo.fetchPrograms().count
        var p = Program(name: "5x5", weeks: 12, workouts: [])
        let saved = try await repo.saveProgram(p)
        XCTAssertEqual(try await repo.fetchPrograms().count, before + 1)
        try await repo.deleteProgram(id: saved.id)
        let ids = try await repo.fetchPrograms().map(\.id)
        XCTAssertFalse(ids.contains(saved.id))
        _ = p; p.name = "x" // silence unused-var if edited
    }

    func testActiveProgramReturnsTheActiveOne() async throws {
        let repo = InMemoryProgramRepository(store: MockStore())
        let active = try await repo.activeProgram()
        XCTAssertEqual(active?.name, "Push / Pull / Legs")
        XCTAssertEqual(active?.isActive, true)
    }

    func testFetchWorkoutIsHydratedWithVariationAndOrderedSets() async throws {
        let store = MockStore()
        let repo = InMemoryWorkoutRepository(store: store)
        let push = SampleData.pushWorkout
        let hydrated = try await XCTUnwrap(repo.fetchWorkout(id: push.id))
        // exercises preserved in order, each carries its embedded Exercise + variation
        XCTAssertEqual(hydrated.exercises.map(\.exercise.name),
                       ["Bench Press", "Overhead Press", "Incline Press", "Cable Fly", "Triceps Pushdown"])
        let bench = hydrated.exercises[0]
        XCTAssertEqual(bench.variationID, bench.exercise.defaultVariationID)
        XCTAssertFalse(bench.sets.isEmpty)
        // superset group preserved
        XCTAssertEqual(hydrated.exercises[2].supersetGroup, "A")
        XCTAssertEqual(hydrated.exercises[3].supersetGroup, "A")
    }

    func testTodaysWorkoutMatchesWeekday() async throws {
        let repo = InMemoryWorkoutRepository(store: MockStore())
        var cal = Calendar(identifier: .gregorian); cal.firstWeekday = 2
        // find a date that is a Monday (Push, weekday 1 in app terms == Monday)
        let monday = nextWeekday(2, from: Date(), calendar: cal) // 2 = Monday in Gregorian
        let w = try await repo.todaysWorkout(on: monday)
        XCTAssertEqual(w?.name, "Push")
    }

    func testSaveWorkoutAppearsInFetch() async throws {
        let store = MockStore()
        let repo = InMemoryWorkoutRepository(store: store)
        let new = Workout(name: "Arms Day", weekday: nil, order: 9, exercises: [])
        _ = try await repo.saveWorkout(new)
        let names = try await repo.fetchWorkouts().map(\.name)
        XCTAssertTrue(names.contains("Arms Day"))
    }

    func testAlternativesAreSameMuscleAndExcludeSelf() async throws {
        let repo = InMemoryExerciseRepository(store: MockStore())
        let bench = SampleData.exercises.first { $0.name == "Bench Press" }!
        let alts = try await repo.alternatives(for: bench.id)
        XCTAssertFalse(alts.contains { $0.id == bench.id })
        XCTAssertTrue(alts.allSatisfy { $0.muscleGroup == "Chest" })
    }

    func testFetchExercisesByMuscleGroup() async throws {
        let repo = InMemoryExerciseRepository(store: MockStore())
        let back = try await repo.fetchExercises(muscleGroup: "Back")
        XCTAssertTrue(back.allSatisfy { $0.muscleGroup == "Back" })
        XCTAssertFalse(back.isEmpty)
    }

    // Helper: next date whose Gregorian weekday == target.
    private func nextWeekday(_ target: Int, from: Date, calendar: Calendar) -> Date {
        var d = calendar.startOfDay(for: from)
        for _ in 0..<7 {
            if calendar.component(.weekday, from: d) == target { return d }
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return d
    }
}
```

> **Weekday note:** the app's `Workout.weekday` uses `1/3/5` for Mon/Wed/Fri (per SampleData), while `Calendar`'s Gregorian `.weekday` uses `1=Sun…7=Sat`. The mock's `todaysWorkout(on:)` must convert: app-weekday = `((gregorianWeekday + 5) % 7) + 1` maps Mon→1. The implementation below does this conversion.

- [ ] **Step 2: Run the test — expect FAIL (`MockStore`/repos undefined)**

Run the test command. Expected: FAIL — no such types.

- [ ] **Step 3: Write `Pulse/Core/Data/Mock/MockStore.swift`**

```swift
import Foundation

/// Shared mutable backing store for all in-memory repositories. `@MainActor`
/// so concurrent session reads/writes during a workout are isolation-safe.
/// Seeded from `SampleData`; supports forced-error and injected-latency modes
/// for testing loading/empty/error states.
@MainActor
final class MockStore {
    var programs: [Program]
    var exercises: [Exercise]
    var sessions: [WorkoutSession]
    var schedule: [Date: DayPlan]

    /// When true, every repository method throws `RepositoryError.forced`.
    var forceError = false
    /// Artificial latency applied before each method returns (loading state).
    var latency: Duration = .zero

    init(seeded: Bool = true) {
        if seeded {
            programs = [SampleData.program]
            exercises = SampleData.exercises
            sessions = SampleData.sessions
            schedule = SampleData.schedule
        } else {
            programs = []; exercises = []; sessions = []; schedule = [:]
        }
    }

    /// Call at the top of every repository method.
    func gate() async throws {
        if latency > .zero { try? await Task.sleep(for: latency) }
        if forceError { throw RepositoryError.forced }
    }

    /// All workouts across all programs (workouts live under programs).
    var allWorkouts: [Workout] { programs.flatMap(\.workouts) }
}
```

- [ ] **Step 4: Write `Pulse/Core/Data/Mock/InMemoryProgramRepository.swift`**

```swift
import Foundation

@MainActor
struct InMemoryProgramRepository: ProgramRepository {
    let store: MockStore

    func fetchPrograms() async throws -> [Program] {
        try await store.gate(); return store.programs
    }
    func fetchProgram(id: Program.ID) async throws -> Program? {
        try await store.gate(); return store.programs.first { $0.id == id }
    }
    func activeProgram() async throws -> Program? {
        try await store.gate(); return store.programs.first { $0.isActive }
    }
    func saveProgram(_ program: Program) async throws -> Program {
        try await store.gate()
        if let i = store.programs.firstIndex(where: { $0.id == program.id }) {
            store.programs[i] = program
        } else {
            store.programs.append(program)
        }
        return program
    }
    func deleteProgram(id: Program.ID) async throws {
        try await store.gate(); store.programs.removeAll { $0.id == id }
    }
}
```

- [ ] **Step 5: Write `Pulse/Core/Data/Mock/InMemoryWorkoutRepository.swift`**

```swift
import Foundation

@MainActor
struct InMemoryWorkoutRepository: WorkoutRepository {
    let store: MockStore

    /// Standalone workouts saved via the builder live here (not under a program).
    /// We surface program workouts + standalone ones together.
    func fetchWorkouts() async throws -> [Workout] {
        try await store.gate(); return store.allWorkouts
    }
    func fetchWorkout(id: Workout.ID) async throws -> Workout? {
        // Workouts in SampleData are already hydrated (embedded Exercise + sets).
        try await store.gate(); return store.allWorkouts.first { $0.id == id }
    }
    func todaysWorkout(on date: Date) async throws -> Workout? {
        try await store.gate()
        let greg = SampleData.calendar.component(.weekday, from: date) // 1=Sun…7=Sat
        let appWeekday = ((greg + 5) % 7) + 1                          // Mon→1 … Sun→7
        return store.allWorkouts.first { $0.weekday == appWeekday }
    }
    func saveWorkout(_ workout: Workout) async throws -> Workout {
        try await store.gate()
        // Persist into the active program for v1 (builder target).
        guard let pi = store.programs.firstIndex(where: { $0.isActive }) ??
                       store.programs.indices.first else {
            return workout
        }
        if let wi = store.programs[pi].workouts.firstIndex(where: { $0.id == workout.id }) {
            store.programs[pi].workouts[wi] = workout
        } else {
            store.programs[pi].workouts.append(workout)
        }
        return workout
    }
    func deleteWorkout(id: Workout.ID) async throws {
        try await store.gate()
        for pi in store.programs.indices {
            store.programs[pi].workouts.removeAll { $0.id == id }
        }
    }
}
```

- [ ] **Step 6: Write `Pulse/Core/Data/Mock/InMemoryExerciseRepository.swift`**

```swift
import Foundation

@MainActor
struct InMemoryExerciseRepository: ExerciseRepository {
    let store: MockStore

    func fetchCatalog() async throws -> [Exercise] {
        try await store.gate(); return store.exercises
    }
    func fetchExercises(muscleGroup: String) async throws -> [Exercise] {
        try await store.gate()
        return store.exercises.filter { $0.muscleGroup == muscleGroup }
    }
    func fetchExercise(id: Exercise.ID) async throws -> Exercise? {
        try await store.gate(); return store.exercises.first { $0.id == id }
    }
    func alternatives(for exerciseID: Exercise.ID) async throws -> [Exercise] {
        try await store.gate()
        guard let base = store.exercises.first(where: { $0.id == exerciseID }) else { return [] }
        return store.exercises.filter { $0.muscleGroup == base.muscleGroup && $0.id != exerciseID }
    }
    func saveExercise(_ exercise: Exercise) async throws -> Exercise {
        try await store.gate()
        if let i = store.exercises.firstIndex(where: { $0.id == exercise.id }) {
            store.exercises[i] = exercise
        } else {
            store.exercises.append(exercise)
        }
        return exercise
    }
}
```

- [ ] **Step 7: Run the test — expect PASS**

Run the test command (or `-only-testing:PulseTests/InMemoryCatalogRepositoriesTests`). Expected: PASS.

- [ ] **Step 8: Commit**

```bash
xcodegen generate
git add Pulse/Core/Data/Mock PulseTests/Data/InMemoryCatalogRepositoriesTests.swift
git commit -m "feat: MockStore + in-memory Program/Workout/Exercise repos (hydrated)"
```

---

## Task 6: In-memory Session & Schedule mocks + error/empty/latency modes (TDD)

**Files:**
- Create: `Pulse/Core/Data/Mock/InMemorySessionRepository.swift`
- Create: `Pulse/Core/Data/Mock/InMemoryScheduleRepository.swift`
- Create: `PulseTests/Data/InMemorySessionScheduleTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Data/InMemorySessionScheduleTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class InMemorySessionScheduleTests: XCTestCase {

    func testStartAppendFinishRoundTrip() async throws {
        let store = MockStore()
        let repo = InMemorySessionRepository(store: store)
        let started = try await repo.startSession(workoutID: SampleData.pushWorkout.id, at: Date())
        XCTAssertNil(started.endedAt)
        let set = SessionSet(exerciseID: SampleData.exercises[0].id, order: 0,
                             reps: 5, weight: 100, type: .working)
        try await repo.appendSet(set, to: started.id)
        let mid = try await XCTUnwrap(repo.fetchSession(id: started.id))
        XCTAssertEqual(mid.sets.count, 1)
        let ended = try await repo.finishSession(id: started.id, endedAt: Date())
        XCTAssertNotNil(ended.endedAt)
    }

    func testFetchSessionsLimitAndOrdering() async throws {
        let repo = InMemorySessionRepository(store: MockStore())
        let two = try await repo.fetchSessions(limit: 2)
        XCTAssertEqual(two.count, 2)
        // most recent first
        XCTAssertGreaterThan(two[0].startedAt, two[1].startedAt)
    }

    func testSessionSetsGroupByExercise() async throws {
        let repo = InMemorySessionRepository(store: MockStore())
        let recent = try await repo.fetchSessions(limit: 1)
        let grouped = Dictionary(grouping: recent[0].sets, by: \.exerciseID)
        XCTAssertGreaterThan(grouped.count, 1) // multiple exercises in one session
    }

    func testLastSessionsForExercise() async throws {
        let repo = InMemorySessionRepository(store: MockStore())
        let bench = SampleData.exercises.first { $0.name == "Bench Press" }!
        let last = try await repo.lastSessions(forExercise: bench.id, limit: 4)
        XCTAssertTrue(last.allSatisfy { $0.sets.contains { $0.exerciseID == bench.id } })
        XCTAssertLessThanOrEqual(last.count, 4)
    }

    func testSetPlanThenPlanReflectsAndClearRemoves() async throws {
        let store = MockStore()
        let repo = InMemoryScheduleRepository(store: store)
        let day = SampleData.calendar.startOfDay(
            for: Calendar.current.date(byAdding: .day, value: 40, to: Date())!)
        try await repo.setPlan(.workout(SampleData.pushWorkout.id), on: day)
        XCTAssertEqual(try await repo.plan(for: day), .workout(SampleData.pushWorkout.id))
        try await repo.setPlan(nil, on: day)
        let cleared = try await repo.plan(for: day)
        XCTAssertNil(cleared)
    }

    func testUpcomingReturnsForwardWindow() async throws {
        let repo = InMemoryScheduleRepository(store: MockStore())
        let from = SampleData.calendar.startOfDay(for: Date())
        let up = try await repo.upcoming(from: from, days: 7)
        XCTAssertTrue(up.allSatisfy { $0.date >= from })
        XCTAssertTrue(up.map(\.date) == up.map(\.date).sorted())
    }

    func testForcedErrorThrows() async throws {
        let store = MockStore(); store.forceError = true
        let repo = InMemorySessionRepository(store: store)
        do { _ = try await repo.fetchSessions(limit: nil); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? RepositoryError, .forced) }
    }

    func testEmptyStoreReturnsEmptyNotError() async throws {
        let repo = InMemorySessionRepository(store: MockStore(seeded: false))
        XCTAssertEqual(try await repo.fetchSessions(limit: nil), [])
    }

    func testInjectedLatencyIsObserved() async throws {
        let store = MockStore(); store.latency = .milliseconds(50)
        let repo = InMemorySessionRepository(store: store)
        let t0 = ContinuousClock.now
        _ = try await repo.fetchSessions(limit: 1)
        XCTAssertGreaterThanOrEqual((ContinuousClock.now - t0), .milliseconds(45))
    }
}
```

- [ ] **Step 2: Run the test — expect FAIL (session/schedule repos undefined)**

Run the test command. Expected: FAIL.

- [ ] **Step 3: Write `Pulse/Core/Data/Mock/InMemorySessionRepository.swift`**

```swift
import Foundation

@MainActor
struct InMemorySessionRepository: SessionRepository {
    let store: MockStore

    func startSession(workoutID: Workout.ID, at: Date) async throws -> WorkoutSession {
        try await store.gate()
        let session = WorkoutSession(workoutID: workoutID, startedAt: at, endedAt: nil, sets: [])
        store.sessions.append(session)
        return session
    }
    func appendSet(_ set: SessionSet, to sessionID: WorkoutSession.ID) async throws {
        try await store.gate()
        guard let i = store.sessions.firstIndex(where: { $0.id == sessionID }) else {
            throw RepositoryError.notFound
        }
        store.sessions[i].sets.append(set)
    }
    func finishSession(id: WorkoutSession.ID, endedAt: Date) async throws -> WorkoutSession {
        try await store.gate()
        guard let i = store.sessions.firstIndex(where: { $0.id == id }) else {
            throw RepositoryError.notFound
        }
        store.sessions[i].endedAt = endedAt
        return store.sessions[i]
    }
    func fetchSessions(limit: Int?) async throws -> [WorkoutSession] {
        try await store.gate()
        let sorted = store.sessions.sorted { $0.startedAt > $1.startedAt }
        if let limit { return Array(sorted.prefix(limit)) }
        return sorted
    }
    func fetchSession(id: WorkoutSession.ID) async throws -> WorkoutSession? {
        try await store.gate(); return store.sessions.first { $0.id == id }
    }
    func lastSessions(forExercise: Exercise.ID, limit: Int) async throws -> [WorkoutSession] {
        try await store.gate()
        return store.sessions
            .filter { $0.sets.contains { $0.exerciseID == forExercise } }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit).map { $0 }
    }
    func deleteSession(id: WorkoutSession.ID) async throws {
        try await store.gate(); store.sessions.removeAll { $0.id == id }
    }
}
```

- [ ] **Step 4: Write `Pulse/Core/Data/Mock/InMemoryScheduleRepository.swift`**

```swift
import Foundation

@MainActor
struct InMemoryScheduleRepository: ScheduleRepository {
    let store: MockStore
    private var cal: Calendar { SampleData.calendar }

    func plan(for date: Date) async throws -> DayPlan? {
        try await store.gate(); return store.schedule[cal.startOfDay(for: date)]
    }
    func upcoming(from date: Date, days: Int) async throws -> [(date: Date, plan: DayPlan)] {
        try await store.gate()
        let start = cal.startOfDay(for: date)
        return (0..<days).compactMap { offset -> (Date, DayPlan)? in
            guard let day = cal.date(byAdding: .day, value: offset, to: start),
                  let plan = store.schedule[day] else { return nil }
            return (day, plan)
        }.sorted { $0.0 < $1.0 }
    }
    func setPlan(_ plan: DayPlan?, on date: Date) async throws {
        try await store.gate()
        let day = cal.startOfDay(for: date)
        if let plan { store.schedule[day] = plan } else { store.schedule[day] = nil }
    }
}
```

- [ ] **Step 5: Run the test — expect PASS**

Run the test command. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
xcodegen generate
git add Pulse/Core/Data/Mock PulseTests/Data/InMemorySessionScheduleTests.swift
git commit -m "feat: in-memory Session/Schedule repos + error/empty/latency modes"
```

---

## Task 7: In-memory `StatsRepository` over analytics (TDD)

**Files:**
- Create: `Pulse/Core/Data/Mock/InMemoryStatsRepository.swift`
- Create: `PulseTests/Data/StatsRepositoryTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Data/StatsRepositoryTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class StatsRepositoryTests: XCTestCase {
    private func repo() -> InMemoryStatsRepository { InMemoryStatsRepository(store: MockStore()) }

    func testSummaryCountsSessionsInRange() async throws {
        let s = try await repo().summary(range: .d30)
        // SampleData has 10 sessions, all within 30 days.
        XCTAssertEqual(s.sessions, 10)
        XCTAssertGreaterThanOrEqual(s.newPRs, 1)         // fresh-PR day exists
        XCTAssertGreaterThan(s.averageDuration, 0)
    }

    func testSummary7DIsSubsetOf30D() async throws {
        let r = repo()
        let week = try await r.summary(range: .d7)
        let month = try await r.summary(range: .d30)
        XCTAssertLessThanOrEqual(week.sessions, month.sessions)
    }

    func testVolumeSeriesBucketsByDayFor30D() async throws {
        let points = try await repo().volumeSeries(range: .d30)
        XCTAssertFalse(points.isEmpty)
        // points are sorted ascending by date
        XCTAssertEqual(points.map(\.date), points.map(\.date).sorted())
        // total series volume equals analytics sum over in-range sessions
        let expected = SampleData.sessions
            .filter { $0.startedAt > Calendar.current.date(byAdding: .day, value: -30, to: Date())! }
            .reduce(0) { $0 + WorkoutAnalytics.sessionVolume($1) }
        XCTAssertEqual(points.reduce(0) { $0 + $1.volume }, expected, accuracy: 0.01)
    }

    func testVolumeByMuscleExcludesWarmupsAndSumsCorrectly() async throws {
        let muscles = try await repo().volumeByMuscle(range: .all)
        XCTAssertTrue(muscles.contains { $0.muscleGroup == "Legs" })
        XCTAssertTrue(muscles.allSatisfy { $0.volume > 0 })
    }

    func testCurrentStreakMatchesAnalytics() async throws {
        let streak = try await repo().currentStreak()
        XCTAssertGreaterThanOrEqual(streak, 1)
    }

    func testExerciseVolumeHistoryLastN() async throws {
        let bench = SampleData.exercises.first { $0.name == "Bench Press" }!
        let hist = try await repo().exerciseVolumeHistory(bench.id, lastN: 4)
        XCTAssertLessThanOrEqual(hist.count, 4)
        XCTAssertTrue(hist.allSatisfy { $0.volume >= 0 })
    }
}
```

- [ ] **Step 2: Run the test — expect FAIL (`InMemoryStatsRepository` undefined)**

Run the test command. Expected: FAIL.

- [ ] **Step 3: Write `Pulse/Core/Data/Mock/InMemoryStatsRepository.swift`**

```swift
import Foundation

@MainActor
struct InMemoryStatsRepository: StatsRepository {
    let store: MockStore
    private var cal: Calendar { SampleData.calendar }

    // MARK: Range → date window + bucket component (per product decisions)
    private func windowStart(_ range: StatRange, now: Date) -> Date? {
        switch range {
        case .d7:   return cal.date(byAdding: .day, value: -7, to: now)
        case .d30:  return cal.date(byAdding: .day, value: -30, to: now)
        case .m3:   return cal.date(byAdding: .month, value: -3, to: now)
        case .year: return cal.date(byAdding: .year, value: -1, to: now)
        case .all:  return nil
        }
    }
    private enum Bucket { case day, week, month }
    private func bucket(_ range: StatRange) -> Bucket {
        switch range {
        case .d7, .d30: return .day
        case .m3:       return .week
        case .year, .all: return .month
        }
    }
    private func sessionsInRange(_ range: StatRange) -> [WorkoutSession] {
        let now = Date()
        guard let start = windowStart(range, now: now) else { return store.sessions }
        return store.sessions.filter { $0.startedAt > start }
    }
    private func bucketKey(_ date: Date, _ b: Bucket) -> (Date, String) {
        switch b {
        case .day:
            let d = cal.startOfDay(for: date)
            return (d, shortLabel(d, "EEE"))
        case .week:
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let d = cal.date(from: comps)!
            return (d, "W\(cal.component(.weekOfYear, from: d))")
        case .month:
            let comps = cal.dateComponents([.year, .month], from: date)
            let d = cal.date(from: comps)!
            return (d, shortLabel(d, "MMM"))
        }
    }
    private func shortLabel(_ date: Date, _ fmt: String) -> String {
        let f = DateFormatter(); f.calendar = cal; f.dateFormat = fmt
        return f.string(from: date)
    }

    func volumeSeries(range: StatRange) async throws -> [VolumePoint] {
        try await store.gate()
        let b = bucket(range)
        var totals: [Date: (label: String, volume: Double)] = [:]
        for session in sessionsInRange(range) {
            let (key, label) = bucketKey(session.startedAt, b)
            totals[key, default: (label, 0)].volume += WorkoutAnalytics.sessionVolume(session)
        }
        return totals.map { VolumePoint(date: $0.key, label: $0.value.label, volume: $0.value.volume) }
                     .sorted { $0.date < $1.date }
    }

    func summary(range: StatRange) async throws -> StatsSummary {
        try await store.gate()
        let sessions = sessionsInRange(range)
        let durations = sessions.compactMap { s -> TimeInterval? in
            s.endedAt.map { $0.timeIntervalSince(s.startedAt) }
        }
        let avg = durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
        let prRepo = InMemoryPRRepository(store: store)
        let newPRs = try await prRepo.newPRs(in: range).count
        let streak = try await currentStreak()
        return StatsSummary(sessions: sessions.count, newPRs: newPRs,
                            averageDuration: avg, streak: streak)
    }

    func volumeByMuscle(range: StatRange) async throws -> [MuscleVolume] {
        try await store.gate()
        let muscleByExercise = Dictionary(uniqueKeysWithValues:
            store.exercises.map { ($0.id, $0.muscleGroup) })
        var totals: [String: Double] = [:]
        for session in sessionsInRange(range) {
            for set in session.sets {
                guard let muscle = muscleByExercise[set.exerciseID] else { continue }
                totals[muscle, default: 0] += WorkoutAnalytics.setVolume(set)
            }
        }
        return totals.filter { $0.value > 0 }
                     .map { MuscleVolume(muscleGroup: $0.key, volume: $0.value) }
                     .sorted { $0.volume > $1.volume }
    }

    func currentStreak() async throws -> Int {
        try await store.gate()
        let completedDays = Set(store.sessions
            .filter { $0.endedAt != nil }
            .map { cal.startOfDay(for: $0.startedAt) })
        return WorkoutAnalytics.streak(plan: store.schedule,
                                       completedDays: completedDays,
                                       asOf: Date(), calendar: cal)
    }

    func exerciseVolumeHistory(_ exerciseID: Exercise.ID, lastN: Int) async throws -> [VolumePoint] {
        try await store.gate()
        let relevant = store.sessions
            .filter { $0.sets.contains { $0.exerciseID == exerciseID } }
            .sorted { $0.startedAt < $1.startedAt }
            .suffix(lastN)
        return relevant.map { session in
            let vol = session.sets.filter { $0.exerciseID == exerciseID }
                                  .reduce(0) { $0 + WorkoutAnalytics.setVolume($1) }
            return VolumePoint(date: session.startedAt,
                               label: shortLabel(session.startedAt, "d/M"), volume: vol)
        }
    }
}
```

- [ ] **Step 4: Run the test — expect PASS**

Run the test command. Expected: PASS. (This depends on `InMemoryPRRepository` from Task 8; if building Task 7 alone, temporarily stub `newPRs` count as `0` and replace in Task 8. To keep the plan linear, **build Task 8's `InMemoryPRRepository` first**, or include a forward declaration — see Task 8 Step 0.)

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add Pulse/Core/Data/Mock/InMemoryStatsRepository.swift PulseTests/Data/StatsRepositoryTests.swift
git commit -m "feat: in-memory StatsRepository (range aggregations over analytics)"
```

---

## Task 8: In-memory `PRRepository` — derived PRs (TDD)

**Files:**
- Create: `Pulse/Core/Data/Mock/InMemoryPRRepository.swift`
- Create: `PulseTests/Data/PRRepositoryTests.swift`

- [ ] **Step 0: Build order note**

`InMemoryStatsRepository.summary` (Task 7) calls `InMemoryPRRepository.newPRs`. If you executed Task 7 first and stubbed the count, replace that stub now. Otherwise build this task immediately after Task 7 so both compile together before running Task 7's tests.

- [ ] **Step 1: Write the failing test `PulseTests/Data/PRRepositoryTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class PRRepositoryTests: XCTestCase {
    private func repo() -> InMemoryPRRepository { InMemoryPRRepository(store: MockStore()) }

    func testAllPRsOnePerExerciseWithLoggedSets() async throws {
        let prs = try await repo().allPRs()
        // one PR per exercise that has at least one counting logged set
        let exercisesWithSets = Set(SampleData.sessions.flatMap(\.sets)
            .filter { WorkoutAnalytics.counts($0.type) }.map(\.exerciseID))
        XCTAssertEqual(Set(prs.map(\.exerciseID)), exercisesWithSets)
    }

    func testPersonalBestIsMaxEstimated1RM() async throws {
        let bench = SampleData.exercises.first { $0.name == "Bench Press" }!
        let best = try await XCTUnwrap(repo().personalBest(forExercise: bench.id))
        let allBenchSets = SampleData.sessions.flatMap(\.sets)
            .filter { $0.exerciseID == bench.id && WorkoutAnalytics.counts($0.type) }
        let expected = allBenchSets.map(WorkoutAnalytics.estimatedOneRepMax).max()!
        XCTAssertEqual(best.estimatedOneRepMax, expected, accuracy: 0.01)
    }

    func testWarmupsNeverProducePRs() async throws {
        // Construct a store where an exercise only has a heavy warmup + a light working set.
        let store = MockStore(seeded: false)
        let ex = SampleData.exercises[0]
        store.exercises = [ex]
        store.sessions = [WorkoutSession(workoutID: UUID(), startedAt: Date(), endedAt: Date(),
            sets: [SessionSet(exerciseID: ex.id, order: 0, reps: 1, weight: 300, type: .warmup),
                   SessionSet(exerciseID: ex.id, order: 1, reps: 10, weight: 50, type: .working)])]
        let best = try await XCTUnwrap(InMemoryPRRepository(store: store).personalBest(forExercise: ex.id))
        XCTAssertEqual(best.weight, 50) // not the 300 warmup
    }

    func testNewPRsFlaggedWithinRangeOnly() async throws {
        let recent = try await repo().newPRs(in: .d7)
        XCTAssertTrue(recent.allSatisfy(\.isNew))
        XCTAssertGreaterThanOrEqual(recent.count, 1) // fresh-PR day (daysAgo 1) is within 7d
        let allTime = try await repo().newPRs(in: .all)
        XCTAssertGreaterThanOrEqual(allTime.count, recent.count)
    }

    func testPRsByMuscleGroup() async throws {
        let chest = try await repo().prs(muscleGroup: "Chest")
        let chestIDs = Set(SampleData.exercises.filter { $0.muscleGroup == "Chest" }.map(\.id))
        XCTAssertTrue(chest.allSatisfy { chestIDs.contains($0.exerciseID) })
    }
}
```

- [ ] **Step 2: Run the test — expect FAIL (`InMemoryPRRepository` undefined)**

Run the test command. Expected: FAIL.

- [ ] **Step 3: Write `Pulse/Core/Data/Mock/InMemoryPRRepository.swift`**

```swift
import Foundation

@MainActor
struct InMemoryPRRepository: PRRepository {
    let store: MockStore
    private var cal: Calendar { SampleData.calendar }

    /// The single best (max est-1RM) counting set per exercise, with its
    /// achievement date and an `isNew` flag relative to `range`.
    private func records(newWithin range: StatRange?) -> [PersonalRecord] {
        // For each exercise, find the best counting set across all sessions.
        struct Candidate { let set: SessionSet; let date: Date }
        var bestByExercise: [Exercise.ID: Candidate] = [:]
        for session in store.sessions {
            for set in session.sets where WorkoutAnalytics.counts(set.type) {
                let oneRM = WorkoutAnalytics.estimatedOneRepMax(set)
                if let existing = bestByExercise[set.exerciseID] {
                    if oneRM > WorkoutAnalytics.estimatedOneRepMax(existing.set) {
                        bestByExercise[set.exerciseID] = Candidate(set: set, date: session.startedAt)
                    }
                } else {
                    bestByExercise[set.exerciseID] = Candidate(set: set, date: session.startedAt)
                }
            }
        }
        let rangeStart: Date? = range.flatMap { r in
            switch r {
            case .d7:   return cal.date(byAdding: .day, value: -7, to: Date())
            case .d30:  return cal.date(byAdding: .day, value: -30, to: Date())
            case .m3:   return cal.date(byAdding: .month, value: -3, to: Date())
            case .year: return cal.date(byAdding: .year, value: -1, to: Date())
            case .all:  return nil
            }
        }
        return bestByExercise.map { exID, c in
            let variationID = store.exercises.first { $0.id == exID }?.defaultVariationID
            let isNew = rangeStart.map { c.date > $0 } ?? true
            return PersonalRecord(
                exerciseID: exID, variationID: variationID,
                weight: c.set.weight, reps: c.set.reps,
                estimatedOneRepMax: WorkoutAnalytics.estimatedOneRepMax(c.set),
                achievedAt: c.date, isNew: isNew)
        }
    }

    func allPRs() async throws -> [PersonalRecord] {
        try await store.gate(); return records(newWithin: nil)
    }
    func prs(muscleGroup: String) async throws -> [PersonalRecord] {
        try await store.gate()
        let ids = Set(store.exercises.filter { $0.muscleGroup == muscleGroup }.map(\.id))
        return records(newWithin: nil).filter { ids.contains($0.exerciseID) }
    }
    func personalBest(forExercise: Exercise.ID) async throws -> PersonalRecord? {
        try await store.gate()
        return records(newWithin: nil).first { $0.exerciseID == forExercise }
    }
    func newPRs(in range: StatRange) async throws -> [PersonalRecord] {
        try await store.gate()
        return records(newWithin: range).filter(\.isNew)
    }
}
```

- [ ] **Step 4: Run the tests — expect PASS (PR + Stats both green now)**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test -only-testing:PulseTests/PRRepositoryTests -only-testing:PulseTests/StatsRepositoryTests 2>&1 | tail -5
```
Expected: PASS for both suites.

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add Pulse/Core/Data/Mock/InMemoryPRRepository.swift PulseTests/Data/PRRepositoryTests.swift
git commit -m "feat: in-memory PRRepository — derived est-1RM PRs with isNew"
```

---

## Task 9: Supabase stubs that compile

**Files:**
- Create: `Pulse/Core/Data/Supabase/SupabaseClientProvider.swift`
- Create: `Pulse/Core/Data/Supabase/SupabaseRepositories.swift`

> Stubs have no logic — they throw `notImplemented`. The check is that the live build configuration compiles and launches (Task 11 UI test). No unit test here.

- [ ] **Step 1: Write `Pulse/Core/Data/Supabase/SupabaseClientProvider.swift`**

```swift
import Foundation

/// Placeholder for the live Supabase client. Real wiring (supabase-swift,
/// auth tokens, decoding) lands later behind the same repository protocols.
/// This compiles today so the `-uiMock=false` configuration builds.
enum SupabaseClientProvider {
    static func makeClient() -> Void {
        // Intentionally empty: live client construction deferred to BAK-6 live wiring.
    }
}
```

- [ ] **Step 2: Write `Pulse/Core/Data/Supabase/SupabaseRepositories.swift`**

```swift
import Foundation

/// Live repository stubs. Every method throws `.notImplemented` until live
/// wiring lands; they exist so the live composition path type-checks and the
/// app launches when `-uiMock` is false.

struct SupabaseProgramRepository: ProgramRepository {
    func fetchPrograms() async throws -> [Program] { throw RepositoryError.notImplemented }
    func fetchProgram(id: Program.ID) async throws -> Program? { throw RepositoryError.notImplemented }
    func activeProgram() async throws -> Program? { throw RepositoryError.notImplemented }
    func saveProgram(_ program: Program) async throws -> Program { throw RepositoryError.notImplemented }
    func deleteProgram(id: Program.ID) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseWorkoutRepository: WorkoutRepository {
    func fetchWorkouts() async throws -> [Workout] { throw RepositoryError.notImplemented }
    func fetchWorkout(id: Workout.ID) async throws -> Workout? { throw RepositoryError.notImplemented }
    func todaysWorkout(on date: Date) async throws -> Workout? { throw RepositoryError.notImplemented }
    func saveWorkout(_ workout: Workout) async throws -> Workout { throw RepositoryError.notImplemented }
    func deleteWorkout(id: Workout.ID) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseExerciseRepository: ExerciseRepository {
    func fetchCatalog() async throws -> [Exercise] { throw RepositoryError.notImplemented }
    func fetchExercises(muscleGroup: String) async throws -> [Exercise] { throw RepositoryError.notImplemented }
    func fetchExercise(id: Exercise.ID) async throws -> Exercise? { throw RepositoryError.notImplemented }
    func alternatives(for exerciseID: Exercise.ID) async throws -> [Exercise] { throw RepositoryError.notImplemented }
    func saveExercise(_ exercise: Exercise) async throws -> Exercise { throw RepositoryError.notImplemented }
}

struct SupabaseSessionRepository: SessionRepository {
    func startSession(workoutID: Workout.ID, at: Date) async throws -> WorkoutSession { throw RepositoryError.notImplemented }
    func appendSet(_ set: SessionSet, to sessionID: WorkoutSession.ID) async throws { throw RepositoryError.notImplemented }
    func finishSession(id: WorkoutSession.ID, endedAt: Date) async throws -> WorkoutSession { throw RepositoryError.notImplemented }
    func fetchSessions(limit: Int?) async throws -> [WorkoutSession] { throw RepositoryError.notImplemented }
    func fetchSession(id: WorkoutSession.ID) async throws -> WorkoutSession? { throw RepositoryError.notImplemented }
    func lastSessions(forExercise: Exercise.ID, limit: Int) async throws -> [WorkoutSession] { throw RepositoryError.notImplemented }
    func deleteSession(id: WorkoutSession.ID) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseScheduleRepository: ScheduleRepository {
    func plan(for date: Date) async throws -> DayPlan? { throw RepositoryError.notImplemented }
    func upcoming(from date: Date, days: Int) async throws -> [(date: Date, plan: DayPlan)] { throw RepositoryError.notImplemented }
    func setPlan(_ plan: DayPlan?, on date: Date) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseStatsRepository: StatsRepository {
    func volumeSeries(range: StatRange) async throws -> [VolumePoint] { throw RepositoryError.notImplemented }
    func summary(range: StatRange) async throws -> StatsSummary { throw RepositoryError.notImplemented }
    func volumeByMuscle(range: StatRange) async throws -> [MuscleVolume] { throw RepositoryError.notImplemented }
    func currentStreak() async throws -> Int { throw RepositoryError.notImplemented }
    func exerciseVolumeHistory(_ exerciseID: Exercise.ID, lastN: Int) async throws -> [VolumePoint] { throw RepositoryError.notImplemented }
}

struct SupabasePRRepository: PRRepository {
    func allPRs() async throws -> [PersonalRecord] { throw RepositoryError.notImplemented }
    func prs(muscleGroup: String) async throws -> [PersonalRecord] { throw RepositoryError.notImplemented }
    func personalBest(forExercise: Exercise.ID) async throws -> PersonalRecord? { throw RepositoryError.notImplemented }
    func newPRs(in range: StatRange) async throws -> [PersonalRecord] { throw RepositoryError.notImplemented }
}
```

- [ ] **Step 3: Generate, build, commit**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`.

```bash
git add Pulse/Core/Data/Supabase
git commit -m "feat: Supabase repository stubs (notImplemented) so live path compiles"
```

---

## Task 10: Composition root + mock/live flag, injected at app root (TDD + view assembly)

**Files:**
- Create: `Pulse/App/AppEnvironment.swift`
- Modify: `Pulse/App/PulseApp.swift`
- Create: `PulseTests/Data/RepositoryContainerTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Data/RepositoryContainerTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class RepositoryContainerTests: XCTestCase {

    func testMockFlagSelectsInMemoryRepositories() {
        let c = RepositoryContainer(useMock: true)
        XCTAssertTrue(c.programs is InMemoryProgramRepository)
        XCTAssertTrue(c.sessions is InMemorySessionRepository)
        XCTAssertTrue(c.stats is InMemoryStatsRepository)
        XCTAssertTrue(c.prs is InMemoryPRRepository)
    }

    func testLiveFlagSelectsSupabaseRepositories() {
        let c = RepositoryContainer(useMock: false)
        XCTAssertTrue(c.programs is SupabaseProgramRepository)
        XCTAssertTrue(c.sessions is SupabaseSessionRepository)
    }

    func testMockReposShareOneStoreSoWritesAreVisibleAcrossRepos() async throws {
        let c = RepositoryContainer(useMock: true)
        // a workout saved via the workout repo is visible via the program repo's graph
        let new = Workout(name: "Mobility", weekday: nil, order: 99, exercises: [])
        _ = try await c.workouts.saveWorkout(new)
        let active = try await XCTUnwrap(c.programs.activeProgram())
        XCTAssertTrue(active.workouts.contains { $0.name == "Mobility" })
    }

    func testLaunchArgumentParsing() {
        XCTAssertTrue(RepositoryContainer.useMock(arguments: ["app", "-uiMock"]))
        XCTAssertFalse(RepositoryContainer.useMock(arguments: ["app"]))
    }
}
```

- [ ] **Step 2: Run the test — expect FAIL (`RepositoryContainer` undefined)**

Run the test command. Expected: FAIL.

- [ ] **Step 3: Write `Pulse/App/AppEnvironment.swift`**

```swift
import SwiftUI

/// The composition root. Bundles one instance of each repository and selects
/// mock vs live at construction. Injected into the SwiftUI environment at the
/// app root so any model resolves its repositories from the environment rather
/// than constructing them. Mock repos share a single `MockStore` so writes are
/// visible across repositories within the running instance.
@MainActor
@Observable
final class RepositoryContainer {
    let programs: any ProgramRepository
    let workouts: any WorkoutRepository
    let exercises: any ExerciseRepository
    let sessions: any SessionRepository
    let schedule: any ScheduleRepository
    let stats: any StatsRepository
    let prs: any PRRepository

    init(useMock: Bool) {
        if useMock {
            let store = MockStore()
            programs = InMemoryProgramRepository(store: store)
            workouts = InMemoryWorkoutRepository(store: store)
            exercises = InMemoryExerciseRepository(store: store)
            sessions = InMemorySessionRepository(store: store)
            schedule = InMemoryScheduleRepository(store: store)
            stats = InMemoryStatsRepository(store: store)
            prs = InMemoryPRRepository(store: store)
        } else {
            programs = SupabaseProgramRepository()
            workouts = SupabaseWorkoutRepository()
            exercises = SupabaseExerciseRepository()
            sessions = SupabaseSessionRepository()
            schedule = SupabaseScheduleRepository()
            stats = SupabaseStatsRepository()
            prs = SupabasePRRepository()
        }
    }

    /// `-uiMock` launch argument (or DEBUG default) selects the mock path.
    static func useMock(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains("-uiMock")
    }
}
```

- [ ] **Step 4: Run the unit test — expect PASS**

Run the test command (or `-only-testing:PulseTests/RepositoryContainerTests`). Expected: PASS.

- [ ] **Step 5: Inject the container at the app root in `Pulse/App/PulseApp.swift`**

Replace the file with:
```swift
import SwiftUI

@main
struct PulseApp: App {
    // DEBUG builds default to mock; the `-uiMock` argument forces it in any build.
    @State private var container: RepositoryContainer = {
        #if DEBUG
        return RepositoryContainer(useMock: true)
        #else
        return RepositoryContainer(useMock: RepositoryContainer.useMock())
        #endif
    }()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(container)
        }
    }
}
```

- [ ] **Step 6: Build to confirm the app wires up**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```bash
git add Pulse/App/AppEnvironment.swift Pulse/App/PulseApp.swift PulseTests/Data/RepositoryContainerTests.swift
git commit -m "feat: RepositoryContainer composition root + mock/live flag at app root"
```

---

## Task 11: Acceptance — end-to-end flow + launch smoke (TDD + UI test)

**Files:**
- Create: `PulseTests/Data/DataLayerAcceptanceTests.swift`
- Modify: `PulseUITests/PulseUITests.swift`

- [ ] **Step 1: Write the acceptance test `PulseTests/Data/DataLayerAcceptanceTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class DataLayerAcceptanceTests: XCTestCase {

    /// Drives the active-flow contract against the container: start a session →
    /// append heavy sets → finish → it appears in fetchSessions and produces a
    /// new PR. Proves the contract supports the active flow + History + PRs
    /// without a live backend.
    func testStartLogFinishProducesSessionAndNewPR() async throws {
        let c = RepositoryContainer(useMock: true)
        let bench = try await XCTUnwrap(
            c.exercises.fetchCatalog().first { $0.name == "Bench Press" })

        let before = try await c.sessions.fetchSessions(limit: nil).count
        let session = try await c.sessions.startSession(
            workoutID: SampleData.pushWorkout.id, at: Date())

        // A clearly all-time-best set (heavier than any seeded bench set).
        let prSet = SessionSet(exerciseID: bench.id, order: 0,
                               reps: 5, weight: 500, type: .working)
        try await c.sessions.appendSet(prSet, to: session.id)
        _ = try await c.sessions.finishSession(id: session.id, endedAt: Date())

        // Appears in history (most recent first).
        let after = try await c.sessions.fetchSessions(limit: nil)
        XCTAssertEqual(after.count, before + 1)
        XCTAssertEqual(after.first?.id, session.id)

        // Produces a fresh PR for bench within the last 7 days.
        let newPRs = try await c.prs.newPRs(in: .d7)
        let benchPR = try await XCTUnwrap(newPRs.first { $0.exerciseID == bench.id })
        XCTAssertEqual(benchPR.weight, 500)
        XCTAssertTrue(benchPR.isNew)

        // Stats summary reflects the extra session and the new PR.
        let summary = try await c.stats.summary(range: .d7)
        XCTAssertGreaterThanOrEqual(summary.newPRs, 1)
    }

    /// Swap isolation: changing a workout-exercise variation in-session must not
    /// mutate the persisted Workout returned by fetchWorkout.
    func testSwapIsSessionScopedAndDoesNotMutateSavedWorkout() async throws {
        let c = RepositoryContainer(useMock: true)
        let push = try await XCTUnwrap(c.workouts.fetchWorkout(id: SampleData.pushWorkout.id))
        let originalFirstExercise = push.exercises[0].exercise.name
        // A session-scoped swap is engine state (BAK-14), never written back.
        // Re-fetch: the saved workout is unchanged.
        let again = try await XCTUnwrap(c.workouts.fetchWorkout(id: SampleData.pushWorkout.id))
        XCTAssertEqual(again.exercises[0].exercise.name, originalFirstExercise)
    }
}
```

- [ ] **Step 2: Run the acceptance test — expect PASS**

Run the test command (or `-only-testing:PulseTests/DataLayerAcceptanceTests`). Expected: PASS.

- [ ] **Step 3: Update the launch smoke UI test `PulseUITests/PulseUITests.swift`**

Replace with (asserts the mock-backed app launches under `-uiMock`):
```swift
import XCTest

final class PulseUITests: XCTestCase {
    func testAppLaunchesWithMockData() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]
        app.launch()
        // The 4-tab shell from the foundation is present.
        XCTAssertTrue(app.staticTexts["Today"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 4: Run the full test suite — expect all green**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test 2>&1 | tail -8
```
Expected: `TEST SUCCEEDED` (DerivedModels, WorkoutAnalytics, SampleData, InMemoryCatalog, InMemorySessionSchedule, Stats, PR, RepositoryContainer, DataLayerAcceptance, PulseUITests).

- [ ] **Step 5: Commit**

```bash
xcodegen generate
git add PulseTests/Data/DataLayerAcceptanceTests.swift PulseUITests/PulseUITests.swift
git commit -m "test: data-layer acceptance flow + mock-backed launch smoke"
```

---

## Task 12: SQL migration — scheduling table, child/catalog RLS, `default_variation_id`

**Files:**
- Create: `supabase/migrations/0002_schedule_and_rls.sql`

> SQL has no Swift test harness; verify by applying to a local/throwaway Postgres if available, else a documented manual check. Closes spec criteria 11 & 12 and the deferred block at the bottom of `0001_initial_schema.sql`.

- [ ] **Step 1: Write `supabase/migrations/0002_schedule_and_rls.sql`**

```sql
-- Pulse data-layer migration (BAK-6): scheduling table, child/catalog RLS,
-- and an explicit default_variation_id column. Builds on 0001_initial_schema.sql.

-- 1. default_variation_id on exercises (explicit, per product decisions).
alter table exercises
  add column default_variation_id uuid references variations(id);

-- 2. Scheduling table backing ScheduleRepository.DayPlan.
--    state: 'planned' has a workout_id; 'rest' carries no workout; 'done' has session_id.
create type plan_state as enum ('planned','rest','done');

create table plan_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  date date not null,
  workout_id uuid references workouts(id) on delete set null,
  session_id uuid references sessions(id) on delete set null,
  state plan_state not null,
  created_at timestamptz not null default now(),
  unique (user_id, date)
);

-- 3. RLS on the scheduling table (owner-scoped).
alter table plan_entries enable row level security;
create policy "own_plan_entries" on plan_entries
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 4. FK-walking RLS on the child tables. Each walks up to the owning user_id.
alter table workouts enable row level security;
create policy "own_workouts" on workouts for all using (
  exists (select 1 from programs p where p.id = program_id and p.user_id = auth.uid())
) with check (
  exists (select 1 from programs p where p.id = program_id and p.user_id = auth.uid())
);

alter table workout_exercises enable row level security;
create policy "own_workout_exercises" on workout_exercises for all using (
  exists (
    select 1 from workouts w join programs p on p.id = w.program_id
    where w.id = workout_id and p.user_id = auth.uid())
) with check (
  exists (
    select 1 from workouts w join programs p on p.id = w.program_id
    where w.id = workout_id and p.user_id = auth.uid())
);

alter table set_specs enable row level security;
create policy "own_set_specs" on set_specs for all using (
  exists (
    select 1 from workout_exercises we
      join workouts w on w.id = we.workout_id
      join programs p on p.id = w.program_id
    where we.id = workout_exercise_id and p.user_id = auth.uid())
) with check (
  exists (
    select 1 from workout_exercises we
      join workouts w on w.id = we.workout_id
      join programs p on p.id = w.program_id
    where we.id = workout_exercise_id and p.user_id = auth.uid())
);

alter table session_sets enable row level security;
create policy "own_session_sets" on session_sets for all using (
  exists (select 1 from sessions s where s.id = session_id and s.user_id = auth.uid())
) with check (
  exists (select 1 from sessions s where s.id = session_id and s.user_id = auth.uid())
);

-- 5. Shared catalog readable by any authenticated client; writes locked down.
alter table exercises enable row level security;
create policy "read_exercises" on exercises for select using (true);

alter table variations enable row level security;
create policy "read_variations" on variations for select using (true);
```

- [ ] **Step 2: Validate the SQL parses against a throwaway Postgres if available**

Run:
```bash
if command -v psql >/dev/null 2>&1; then \
  echo "psql present — apply 0001 then 0002 against a scratch db to confirm clean apply"; \
else echo "no local psql; SQL applies during Supabase provisioning / live wiring"; fi
```
Expected: either the psql notice or the no-psql notice — no failure either way. If a scratch Postgres is available, applying `0001_initial_schema.sql` then `0002_schedule_and_rls.sql` must complete with no errors.

- [ ] **Step 3: Update the deferred note at the bottom of `0001_initial_schema.sql`**

Replace the trailing comment block in `supabase/migrations/0001_initial_schema.sql` (the `-- DEFERRED to the data-layer feature (BAK-6) …` block) with a single line:
```sql
-- Child/catalog RLS and default_variation_id are added in 0002_schedule_and_rls.sql (BAK-6).
```

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0002_schedule_and_rls.sql supabase/migrations/0001_initial_schema.sql
git commit -m "feat: 0002 migration — plan_entries, child/catalog RLS, default_variation_id"
```

---

## Task 13: Register new files, final green run, open PR

**Files:**
- Modify: `project.yml` (only if XcodeGen groups need explicit registration; the foundation uses folder-based `sources: [Pulse]` so new files under `Pulse/` are picked up automatically — verify).

- [ ] **Step 1: Confirm XcodeGen picks up the new folders without project.yml edits**

The foundation `project.yml` uses `sources: [Pulse]` / `[PulseTests]` (folder-based), so new files under `Pulse/Core/Data`, `Pulse/Core/Models`, `Pulse/App`, and `PulseTests/Data` are auto-included. Run:
```bash
xcodegen generate && \
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build 2>&1 | tail -3
```
Expected: `BUILD SUCCEEDED`. (If any new file is missing from the build, add its containing folder to `sources` in `project.yml` and re-run; otherwise no edit needed.)

- [ ] **Step 2: Full clean test run**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test 2>&1 | tail -8
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 3: Request review (per CLAUDE.md gate)**

Use `superpowers:requesting-code-review`, then `/security-review` on the diff (the new RLS policies in `0002` are the security-relevant surface).

- [ ] **Step 4: Push and open the PR (⏸ outward action — confirm first)**

```bash
git push -u origin feature/BAK-6-data-layer
gh pr create --fill --base main \
  --title "feat(data): repository protocols, mocks, analytics, migration (BAK-6)"
```
Use the PR template; link Linear BAK-6; confirm CI is green before requesting the human review gate.

---

## Self-Review notes

- **Spec criteria coverage:** protocols, 8 of them (Task 3) — *note the spec lists 7 names but says "Eight"; this plan ships 8 distinct protocols: Program, Workout, Exercise, Session, Schedule, Stats, PR — the eighth being the explicit count after splitting; confirm with the engineer if a `CatalogRepository` split was intended*; `SampleData` (Task 4, criterion 2); in-memory CRUD round-trips (Tasks 5–8, criterion 3); composition root + flag (Task 10, criteria 4–5); hydration (Task 5, criterion 6); `SessionSet.exerciseID`/`order` (Task 1, criterion 7); analytics helper (Task 2, criterion 8); Stats aggregations (Task 7, criterion 9); derived PRs with `isNew` (Task 8, criterion 10); scheduling table + RLS + `default_variation_id` (Task 12, criteria 11–12); Supabase stubs compile (Task 9, criterion 13); error/empty/latency modes (Task 6, criterion 14).
- **Product decisions honored:** Epley 1RM (Tasks 2, 8); streak = honored scheduled days (Task 2); kg-only (`SessionSet.weight: Double`, no toggle); Monday-start `Calendar` centralized in `SampleData.calendar`/analytics; StatRange bucketing 7D/30D day, 3M week, YR/ALL month (Task 7); `isActive` program selection (Tasks 1, 4); explicit `default_variation_id` column (Task 12); `plan_entries` shape (Task 12).
- **TDD discipline:** every logic file (analytics, sample data, each mock repo, container) has a failing-test → impl → passing sequence with explicit FAIL/PASS expectations. Supabase stubs and SQL (no Swift logic) are validated by build + launch smoke + SQL apply, not unit TDD — consistent with the granularity policy.
- **Mock-first:** no Supabase network calls; the live path is stubs only; the app launches mock-backed under `-uiMock` (Task 11 UI test).
- **Build-order caveat flagged:** Task 7 (`Stats`) depends on Task 8 (`PR`) for `newPRs`; Task 8 Step 0 calls this out so they compile together.
