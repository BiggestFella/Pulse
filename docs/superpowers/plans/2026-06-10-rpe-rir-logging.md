# RPE/RIR Per-Set Logging + Deload Signal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture an optional **RIR** (Reps In Reserve) per logged working set during the active session, persist it through every layer (model → SQL → Supabase repos → InMemory mocks), surface it as `@RIR n` in History/Session Detail and Exercise Detail, and compute a pure, advisory **deload signal** from recent RIR trends shown as a dismissible banner. Logging without touching the selector stores `nil`; legacy rows read as `nil`.

**Architecture:** SwiftUI iOS 17+, MVVM + `@Observable`. Domain structs live in `Pulse/Core/Models/WorkoutModels.swift`; all data access goes through repository protocols in `Pulse/Core/Data` (views/models never touch Supabase). The active session is driven by `ActiveWorkoutModel`; logged sets persist via the flow-local `SessionWriter` and the canonical `SessionRepository`. The deload heuristic is a **pure free function** in `Pulse/Core/Workout/FatigueSignal.swift` with no I/O. Design system: `Theme` tokens only; the `@RIR n` and selector labels use Geist Mono (`.pulseStyle(.rowSub)` / `PulseFont.mono`).

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency, XCTest (PulseTests), XcodeGen project, Supabase (Postgres + RLS). Test gate: `-only-testing:PulseTests` (the UI-test runner is broken on Xcode 26.5/iOS 26.5 — device/visual checks are a manual checklist, not automated).

---

## File Structure

```
Pulse/
  Core/
    Models/
      WorkoutModels.swift            (MODIFY — add `var rir: Int? = nil` to SessionSet)
    Workout/
      FatigueSignal.swift            (NEW — DeloadSuggestion + deloadSuggestion(...))
    Data/
      Mock/
        SampleData.swift             (MODIFY — seed some RIR onto sample sets, keep some nil)
        InMemorySessionRepository.swift (no change — appends SessionSet whole; rir rides along)
      Mocks/
        ActiveWorkoutMocks.swift     (MockSessionWriter already stores whole session; no change)
      Supabase/
        SupabaseRepositories.swift   (MODIFY — document rir column mapping on SessionRepository stub)
  Features/
    ActiveWorkout/
      ActiveWorkoutModel.swift       (MODIFY — logSet(reps:weight:rir:), rir default nil)
      ActiveSetView.swift            (MODIFY — optional RIR selector for working/amrap sets)
    History/
      SessionDetailModel.swift       (MODIFY — append "@RIR n" to detail line when present)
      SessionDetailView.swift        (no change — renders the model's detail string)
    ExerciseDetail/
      ExerciseDetailModel.swift      (MODIFY — repLine carries "@RIR n"; or add rirLine)
      ExerciseDetailView.swift       (no change — renders model's repLine)
    Today/
      TodayModel.swift               (MODIFY — expose deloadSuggestion + dismiss)
      TodayView.swift                (MODIFY — render dismissible DeloadBanner)
      DeloadBanner.swift             (NEW — the advisory banner view)

PulseTests/
  WorkoutModelsTests.swift           (MODIFY — SessionSet rir Codable round-trip)
  ActiveWorkout/
    SessionSetPersistenceTests.swift (NEW — InMemory repo round-trip + legacy nil)
    FatigueSignalTests.swift         (NEW — deloadSuggestion heuristic cases)

supabase/
  migrations/
    0003_session_set_rir.sql         (NEW — ALTER TABLE session_sets ADD COLUMN rir)
```

**Migration numbering (verified on this branch):** The highest **committed** migration on `docs/bak-33-37-feature-specs` is `0002_schedule_and_rls.sql` (`git ls-files supabase/migrations/` returns only `0001` and `0002`). The working tree also contains an **untracked** `0005_seed_exercise_catalog.sql` from a sibling branch — per instructions we ignore uncommitted higher numbers and number after the highest committed migration, so this new file is **`0003_session_set_rir.sql`**.
> ⚠️ **Dependency note:** If `0005_seed_exercise_catalog.sql` (and any `0003`/`0004` it implies) land on `main` before this branch merges, renumber this migration to one past the new highest committed number and rebase. The `ALTER TABLE session_sets ADD COLUMN rir` is order-independent of the seed/catalog migrations, so only the filename prefix needs to change.

---

## Task 1 — Add `rir` to `SessionSet` (model + Codable round-trip)

Add `var rir: Int? = nil` to the logged-set model so older call sites and rows compile/migrate cleanly. Optional + defaulted means every existing `SessionSet(...)` initializer call keeps compiling and `nil` means "not recorded".

**Files:** `Pulse/Core/Models/WorkoutModels.swift`, `PulseTests/WorkoutModelsTests.swift`

- [ ] Add a failing test to `PulseTests/WorkoutModelsTests.swift` proving `rir` round-trips both present and absent:

```swift
func testSessionSetCodableRoundTripWithRIR() throws {
    let original = SessionSet(exerciseID: UUID(), order: 0, reps: 8,
                              weight: 100, type: .working, rir: 1)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(SessionSet.self, from: data)
    XCTAssertEqual(decoded, original)
    XCTAssertEqual(decoded.rir, 1)
}

func testSessionSetCodableRoundTripWithoutRIR() throws {
    let original = SessionSet(exerciseID: UUID(), order: 0, reps: 8,
                              weight: 100, type: .working)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(SessionSet.self, from: data)
    XCTAssertNil(decoded.rir)
    XCTAssertEqual(decoded, original)
}
```

- [ ] Run (expected **FAIL** — `SessionSet` has no `rir` param, won't compile):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/WorkoutModelsTests`
- [ ] Minimal impl — add the field to `SessionSet` in `WorkoutModels.swift`:

```swift
struct SessionSet: Codable, Equatable, Identifiable {
    var id = UUID()
    var exerciseID: Exercise.ID
    var order: Int
    var reps: Int
    var weight: Double            // kilograms (v1 is kg-only)
    var type: SetType
    /// Reps In Reserve at this set's completion. `nil` = not recorded (legacy
    /// rows and the fast log path that never opens the selector). Matches the
    /// planned `SetSpec.rir` vocabulary (RIR, not RPE).
    var rir: Int? = nil
}
```

> Note: synthesized `Codable` omits a `nil` optional from JSON only with custom keys; the default synthesis **does** round-trip `nil` correctly (encodes `null` / decodes missing-or-null to `nil`). The "absent" test asserts `decoded.rir == nil` for either encoding, so synthesis is sufficient — no custom `CodingKeys` needed.

- [ ] Run (expected **PASS**): same command as above.
- [ ] Commit:
  `git add Pulse/Core/Models/WorkoutModels.swift PulseTests/WorkoutModelsTests.swift && git commit -m "feat(models): add optional rir to SessionSet [BAK-36]"`

---

## Task 2 — Thread `rir` through the InMemory repository (persistence round-trip)

`InMemorySessionRepository.appendSet(_:to:)` already appends a whole `SessionSet`, so `rir` rides along with no code change — but we must **lock that behaviour with a test** and prove legacy-shaped sets (no `rir`) read back as `nil`. This is the unit-level stand-in for the Supabase round-trip (Task 3's live write is manual).

**Files:** `PulseTests/ActiveWorkout/SessionSetPersistenceTests.swift` (NEW)

- [ ] Create the failing test file (fails to compile until Task 1 lands; if Task 1 is committed it will compile but we still author it test-first for the persistence contract):

```swift
import XCTest
@testable import Pulse

@MainActor
final class SessionSetPersistenceTests: XCTestCase {
    private func makeRepo() -> (InMemorySessionRepository, MockStore) {
        let store = MockStore()
        store.sessions = []   // isolate from seeded sample sessions
        return (InMemorySessionRepository(store: store), store)
    }

    func testAppendedSetPreservesRIRThroughReadBack() async throws {
        let (repo, _) = makeRepo()
        let session = try await repo.startSession(workoutID: UUID(), at: .now)
        let exID = UUID()
        try await repo.appendSet(
            SessionSet(exerciseID: exID, order: 0, reps: 8, weight: 100,
                       type: .working, rir: 2),
            to: session.id)

        let read = try await repo.fetchSession(id: session.id)
        XCTAssertEqual(read?.sets.first?.rir, 2)
    }

    func testLegacyShapedSetReadsBackAsNilRIR() async throws {
        let (repo, _) = makeRepo()
        let session = try await repo.startSession(workoutID: UUID(), at: .now)
        // No `rir:` argument — the fast log path / legacy construction.
        try await repo.appendSet(
            SessionSet(exerciseID: UUID(), order: 0, reps: 10, weight: 80,
                       type: .working),
            to: session.id)

        let read = try await repo.fetchSession(id: session.id)
        XCTAssertNil(read?.sets.first?.rir)
    }
}
```

- [ ] Run (expected **PASS** if Task 1 committed; the point is to pin the contract). If it does not pass, fix `InMemorySessionRepository`/`MockStore` so the whole set (incl. `rir`) is stored and returned:
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/SessionSetPersistenceTests`
- [ ] (If the assertion above already passes with no production change, that is the expected outcome — `appendSet` stores the struct verbatim. Add a one-line comment in `InMemorySessionRepository.appendSet` noting `rir` is preserved by value so a future refactor doesn't drop it.)
- [ ] Seed RIR into sample data so the surfacing UI and banner have data to show. In `Pulse/Core/Data/Mock/SampleData.swift`, `loggedSets(for:weightBump:)`, tag the **working** sets with a descending RIR pattern (recent sessions grind harder so the banner can demo). Replace the append with:

```swift
for spec in we.sets where spec.type != .warmup {
    let resolvedType: SetType = spec.type == .amrap ? .amrap : .working
    // Demo signal: heavier bump → lower RIR (harder). nil for the very first
    // batch so "legacy / untagged" rows coexist with tagged ones.
    let rir: Int? = weightBump == 0 ? nil : max(0, 3 - Int(weightBump / 2.5))
    out.append(SessionSet(exerciseID: we.exercise.id, order: order,
                          reps: spec.reps, weight: base + weightBump,
                          type: resolvedType, rir: rir))
    order += 1
}
```

- [ ] Run the full PulseTests suite to confirm nothing else regressed:
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests`
- [ ] Commit:
  `git add PulseTests/ActiveWorkout/SessionSetPersistenceTests.swift Pulse/Core/Data/Mock/SampleData.swift Pulse/Core/Data/Mock/InMemorySessionRepository.swift && git commit -m "test(data): pin SessionSet rir round-trip through InMemory repo; seed sample RIR [BAK-36]"`

---

## Task 3 — SQL migration + Supabase mapping (manual/integration note)

Add the nullable column to the logged-set table. There is **no live Supabase row encoder yet** — `SupabaseSessionRepository` in `SupabaseRepositories.swift` is a stub (`throw RepositoryError.notImplemented`), and `SessionSet` is mapped to/from Supabase via its synthesized `Codable` conformance (the SQL `"order"` column is the existing precedent for column naming). So this task is: (a) the migration, and (b) documenting the column mapping on the stub so whoever implements live wiring maps `rir` ↔ the new column. The real Postgres write/read is a **manual/integration check** (see the Manual verification checklist) — Supabase live calls are not unit-tested.

**Files:** `supabase/migrations/0003_session_set_rir.sql` (NEW), `Pulse/Core/Data/Supabase/SupabaseRepositories.swift`

- [ ] Create `supabase/migrations/0003_session_set_rir.sql` with the full SQL:

```sql
-- Add optional Reps-In-Reserve to logged sets (BAK-36).
-- Nullable: legacy rows and fast-logged sets carry NULL = "not recorded".
-- `smallint` is ample (RIR is 0..~5); CHECK keeps it non-negative.
-- Mirrors `SessionSet.rir: Int?` in Pulse/Core/Models/WorkoutModels.swift and
-- the existing `set_specs.rir` (planned-side) column from 0001_initial_schema.sql.
alter table session_sets
  add column rir smallint null check (rir is null or rir >= 0);

comment on column session_sets.rir is
  'Reps In Reserve at set completion; NULL = not recorded. Maps to SessionSet.rir.';
```

- [ ] Document the mapping on the live stub so the future live writer threads `rir`. In `Pulse/Core/Data/Supabase/SupabaseRepositories.swift`, above `struct SupabaseSessionRepository`, add:

```swift
/// Live session persistence (stub until wiring lands). When implemented,
/// `SessionSet` rows map column-for-column: `exercise_id`, `reps`, `weight`,
/// `type`, `"order"` (quoted reserved word), and the nullable `rir` smallint
/// added in migration 0003_session_set_rir.sql. `SessionSet.rir == nil`
/// round-trips as SQL NULL; rows predating 0003 decode to `rir == nil`.
```

- [ ] There is no Swift unit test for the migration or the stub (no live calls in CI). Verify the SQL parses locally if the Supabase CLI is available (optional, manual):
  `supabase db reset` or `supabase migration up` against a local dev DB — see Manual verification checklist. Do **not** add this to the CI gate.
- [ ] Run the build to confirm the comment edit compiles:
  `xcodebuild build -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16'`
- [ ] Commit:
  `git add supabase/migrations/0003_session_set_rir.sql Pulse/Core/Data/Supabase/SupabaseRepositories.swift && git commit -m "feat(data): session_sets.rir migration + Supabase column mapping note [BAK-36]"`

---

## Task 4 — Capture UI: `logSet(reps:weight:rir:)` + optional RIR selector

Thread an optional `rir:` (default `nil`) into the model's log path so the fast path is unchanged, then add a compact RIR chip row in `ActiveSetView` shown only for working/amrap sets. Tapping a chip sets the value; logging without tapping stores `nil`.

**Files:** `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift`, `Pulse/Features/ActiveWorkout/ActiveSetView.swift`, `PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift`

- [ ] Add a failing test to `PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift` proving the logged set captures `rir`, and that the default path stays `nil`:

```swift
@MainActor
func testLogSetCapturesRIRWhenProvided() {
    let model = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                                   historyRepo: MockHistoryRepository(),
                                   sessionWriter: MockSessionWriter())
    model.startWorkout(ActiveWorkoutSample.workout)
    model.beginSets()
    model.logSet(reps: 8, weight: 100, rir: 1)
    XCTAssertEqual(model.loggedSets[0]?.rir, 1)
}

@MainActor
func testLogSetDefaultsRIRToNil() {
    let model = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                                   historyRepo: MockHistoryRepository(),
                                   sessionWriter: MockSessionWriter())
    model.startWorkout(ActiveWorkoutSample.workout)
    model.beginSets()
    model.logSet(reps: 8, weight: 100)   // fast path — no rir argument
    XCTAssertNil(model.loggedSets[0]?.rir)
}
```

- [ ] Run (expected **FAIL** — `logSet` has no `rir:` parameter):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/ActiveWorkoutModelTests`
- [ ] Minimal impl — update `logSet` in `ActiveWorkoutModel.swift` to accept an optional `rir`:

```swift
func logSet(reps: Int, weight: Double, rir: Int? = nil, now: Date = .now) {
    guard !steps.isEmpty else { return }
    let step = steps[stepIdx]
    let type = currentSet?.type ?? .working
    let exID = workout.exercises[step.exIdx].exercise.id
    loggedSets[stepIdx] = SessionSet(exerciseID: exID, order: stepIdx,
                                     reps: reps, weight: weight, type: type,
                                     rir: rir)
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
```

- [ ] Run (expected **PASS**): same command as above.
- [ ] Add the selector UI to `ActiveSetView.swift`. Add a `@State` for the picked value, reset it when the step changes, render a compact chip row for working/amrap sets (not warmup/failure/dropset), and pass it into `logSet`. Add the state and reset:

```swift
@State private var reps: Int = 0
@State private var weight: Double = 0
@State private var rir: Int? = nil   // unset until the lifter taps a chip
```

In `.onChange(of: model.stepIdx, initial: true)` reset `rir` too:

```swift
.onChange(of: model.stepIdx, initial: true) { _, _ in
    reps = model.seedReps
    weight = model.seedWeight
    rir = nil
}
```

Add a computed flag and the selector view (Geist Mono labels, Theme tokens only):

```swift
/// RIR capture is offered only for effort-bearing sets; never for warmups,
/// to-failure (RIR is implicitly 0), or dropsets.
private var capturesRIR: Bool { setSpec.type == .working || setSpec.type == .amrap }

private var rirSelector: some View {
    VStack(alignment: .leading, spacing: 6) {
        Text("RIR (REPS IN RESERVE)")
            .pulseStyle(.rowSub)
            .foregroundStyle(theme.inkSoft)
        HStack(spacing: 6) {
            ForEach(RIRSelectorOption.all, id: \.self) { option in
                let selected = rir == option.value
                Button { rir = (selected ? nil : option.value) } label: {
                    Text(option.label)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(selected ? theme.onAccent : theme.ink)
                        .padding(.vertical, 6).padding(.horizontal, 12)
                        .background(selected ? theme.accent : .clear,
                                    in: Capsule())
                        .overlay(Capsule().strokeBorder(
                            selected ? .clear : theme.inkFaint, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("active.rir.\(option.value)")
            }
        }
    }
    .accessibilityIdentifier("active.rirSelector")
}
```

Add the option model at file scope (below the view), so `4+` clamps to 4:

```swift
/// RIR chips: 0,1,2,3 plus a "4+" bucket that stores 4.
private struct RIRSelectorOption: Hashable {
    let value: Int
    let label: String
    static let all: [RIRSelectorOption] = [
        .init(value: 0, label: "0"), .init(value: 1, label: "1"),
        .init(value: 2, label: "2"), .init(value: 3, label: "3"),
        .init(value: 4, label: "4+"),
    ]
}
```

Insert the selector into `body` after `steppers` (only when capturing), and pass `rir` to `logSet`:

```swift
if !isFailure { steppers }
if capturesRIR { rirSelector }
```

```swift
Button(model.logButtonLabel) { model.logSet(reps: reps, weight: weight, rir: rir) }
    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
    .frame(maxWidth: .infinity)
    .accessibilityIdentifier("active.log")
```

- [ ] Run the full suite to confirm no regressions (the view change has no new unit test — it is on the manual checklist because the UI runner is broken):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests`
- [ ] Commit:
  `git add Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift Pulse/Features/ActiveWorkout/ActiveSetView.swift PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift && git commit -m "feat(active): optional RIR selector + logSet(rir:) capture [BAK-36]"`

---

## Task 5 — Surface `@RIR n` in Session Detail and Exercise Detail

Render `@RIR n` on the set rows where present. Both detail screens derive their display strings in the `@Observable` model (`SessionDetailModel.detailString`, `ExerciseDetailModel.summarize`), so the change is in pure model logic — fully unit-testable — and the views render the model's string unchanged.

**Files:** `Pulse/Features/History/SessionDetailModel.swift`, `Pulse/Features/ExerciseDetail/ExerciseDetailModel.swift`, `PulseTests/ActiveWorkout/SessionSetPersistenceTests.swift` (extend, or a new `DetailRIRRenderingTests.swift`)

- [ ] Add a failing test (new file `PulseTests/History/DetailRIRRenderingTests.swift`) for the Session Detail detail string and the Exercise Detail rep line:

```swift
import XCTest
@testable import Pulse

@MainActor
final class DetailRIRRenderingTests: XCTestCase {
    func testSessionDetailLineAppendsAverageRIRWhenPresent() {
        let exID = UUID()
        let sets = [
            SessionSet(exerciseID: exID, order: 0, reps: 10, weight: 100, type: .working, rir: 2),
            SessionSet(exerciseID: exID, order: 1, reps: 8,  weight: 100, type: .working, rir: 1),
        ]
        let session = WorkoutSession(workoutID: UUID(), startedAt: .now, endedAt: nil, sets: sets)
        let rows = SessionDetailModel.logRows(
            for: session, workout: nil,
            nameByExercise: [exID: "Back Squat"], prIDs: [])
        // "10·8 @ 100kg · @RIR 1" (avg of 2 and 1 = 1.5 → rounded down to 1)
        XCTAssertTrue(rows.first?.detail.contains("@RIR 1") ?? false,
                      "got: \(rows.first?.detail ?? "nil")")
    }

    func testSessionDetailLineOmitsRIRWhenAllNil() {
        let exID = UUID()
        let sets = [SessionSet(exerciseID: exID, order: 0, reps: 10, weight: 100, type: .working)]
        let session = WorkoutSession(workoutID: UUID(), startedAt: .now, endedAt: nil, sets: sets)
        let rows = SessionDetailModel.logRows(
            for: session, workout: nil,
            nameByExercise: [exID: "Back Squat"], prIDs: [])
        XCTAssertFalse(rows.first?.detail.contains("RIR") ?? true)
    }
}
```

- [ ] Run (expected **FAIL** — no `@RIR` in the detail string yet):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/DetailRIRRenderingTests`
- [ ] Minimal impl in `SessionDetailModel.detailString(for:)`. Append `· @RIR n` (rounded-down average across counting sets that have a value) when at least one counting set is tagged. Replace the weighted-branch return so RIR is appended in both the weighted and reps-only cases:

```swift
/// "15·12·10·8 @ 140kg", or "To failure · N" when the set is to-failure,
/// or "N reps" when there's no weight. Appends "· @RIR n" when any counting
/// set carries a recorded RIR (average, floored).
private static func detailString(for sets: [SessionSet]) -> String {
    if let failure = sets.first(where: { $0.type == .failure }) {
        return "To failure · \(failure.reps)"
    }
    let counting = sets.filter { WorkoutAnalytics.counts($0.type) }
    let rirSuffix = averageRIRSuffix(counting)
    guard !counting.isEmpty else {
        if let first = sets.first { return "\(first.reps) reps" }
        return "—"
    }
    let reps = counting.map { String($0.reps) }.joined(separator: "·")
    let weight = counting.map(\.weight).max() ?? 0
    if weight == 0 { return "\(reps) reps" + rirSuffix }
    return "\(reps) @ \(trimmed(weight))kg" + rirSuffix
}

/// " · @RIR n" (floored average over tagged counting sets) or "" when none tagged.
private static func averageRIRSuffix(_ counting: [SessionSet]) -> String {
    let tagged = counting.compactMap(\.rir)
    guard !tagged.isEmpty else { return "" }
    let avg = tagged.reduce(0, +) / tagged.count   // integer floor
    return " · @RIR \(avg)"
}
```

- [ ] Add the same surfacing to Exercise Detail. In `ExerciseDetailModel.summarize(_:)`, fold a floored-average RIR into the rep line. Change `ExerciseSessionSummary.repLine` building so it appends `@RIR n` when tagged:

```swift
private func summarize(_ session: WorkoutSession) -> ExerciseSessionSummary {
    let sets = session.sets.filter { $0.exerciseID == exerciseID }
    let counting = sets.filter { WorkoutAnalytics.counts($0.type) }
    var repLine = counting.map { String($0.reps) }.joined(separator: " · ")
    let tagged = counting.compactMap(\.rir)
    if !tagged.isEmpty {
        repLine += "  @RIR \(tagged.reduce(0, +) / tagged.count)"
    }
    let topWeight = WorkoutAnalytics.topWorkingWeight(in: sets) ?? 0
    let volume = WorkoutAnalytics.volume(of: sets)
    return ExerciseSessionSummary(date: session.startedAt, repLine: repLine,
                                  topWeight: topWeight, volume: volume)
}
```

(The Exercise Detail view renders `"\(session.repLine) REPS"`; the `@RIR n` sits inside that Geist-Mono `.pulseStyle(.rowSub)` line — no view change needed. If a dedicated styled `@RIR` chip is desired later, that is a follow-up; v1 keeps it inline per DRY/YAGNI.)

- [ ] Run (expected **PASS**) and full suite:
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/DetailRIRRenderingTests`
  then `-only-testing:PulseTests`
- [ ] Commit:
  `git add Pulse/Features/History/SessionDetailModel.swift Pulse/Features/ExerciseDetail/ExerciseDetailModel.swift PulseTests/History/DetailRIRRenderingTests.swift && git commit -m "feat(detail): surface @RIR n in Session Detail and Exercise Detail rows [BAK-36]"`

---

## Task 6 — Pure `deloadSuggestion` engine (fully tested)

A pure, I/O-free heuristic in `Pulse/Core/Workout/FatigueSignal.swift`. Over the last N (default 6) sessions, look at the **top working set** per session (the counting set with the highest est-1RM, mirroring `WorkoutAnalytics.bestSet`), take its RIR when tagged, and if the average across the tagged top sets is ≤1 **and** at least `minTaggedSessions` (default 3) of those sessions are RIR-tagged, return a suggestion. Otherwise `nil` (no nagging on sparse or easy data).

**Files:** `Pulse/Core/Workout/FatigueSignal.swift` (NEW), `PulseTests/ActiveWorkout/FatigueSignalTests.swift` (NEW)

- [ ] Write the failing tests first in `PulseTests/ActiveWorkout/FatigueSignalTests.swift`:

```swift
import XCTest
@testable import Pulse

final class FatigueSignalTests: XCTestCase {
    private let exID = UUID()

    /// Build a session whose single top working set carries the given RIR.
    private func session(daysAgo: Int, rir: Int?, weight: Double = 100) -> WorkoutSession {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let set = SessionSet(exerciseID: exID, order: 0, reps: 5,
                             weight: weight, type: .working, rir: rir)
        return WorkoutSession(workoutID: UUID(), startedAt: start, endedAt: start, sets: [set])
    }

    func testConsistentlyLowRIROverNSessionsSuggestsDeload() {
        let sessions = (0..<6).map { session(daysAgo: $0 * 2, rir: 1) }
        let suggestion = deloadSuggestion(recentSessions: sessions)
        XCTAssertNotNil(suggestion)
    }

    func testMixedOrHighRIRReturnsNil() {
        let sessions = [3, 2, 3, 2, 3, 2].enumerated()
            .map { session(daysAgo: $0.offset * 2, rir: $0.element) }
        XCTAssertNil(deloadSuggestion(recentSessions: sessions))
    }

    func testBelowMinimumTaggedSessionsReturnsNil() {
        // Only 2 tagged sessions (both hard); rest untagged → not enough signal.
        let sessions = [
            session(daysAgo: 0, rir: 0), session(daysAgo: 2, rir: 1),
            session(daysAgo: 4, rir: nil), session(daysAgo: 6, rir: nil),
            session(daysAgo: 8, rir: nil), session(daysAgo: 10, rir: nil),
        ]
        XCTAssertNil(deloadSuggestion(recentSessions: sessions))
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(deloadSuggestion(recentSessions: []))
    }

    func testOnlyConsidersMostRecentNSessions() {
        // 6 recent hard sessions + 4 older easy ones; only the recent 6 count.
        let hard = (0..<6).map { session(daysAgo: $0, rir: 1) }
        let easyOlder = (0..<4).map { session(daysAgo: 30 + $0, rir: 4) }
        let suggestion = deloadSuggestion(recentSessions: hard + easyOlder)
        XCTAssertNotNil(suggestion)
    }
}
```

- [ ] Run (expected **FAIL** — file/function doesn't exist):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/FatigueSignalTests`
- [ ] Implement `Pulse/Core/Workout/FatigueSignal.swift` in full:

```swift
import Foundation

/// Advisory deload nudge derived from recent RIR trends. Display-only — never
/// mutates the program (auto-deload is an explicit non-goal). `nil` everywhere
/// means "no signal / not enough data".
struct DeloadSuggestion: Equatable {
    /// Floored average RIR across the recent tagged top working sets.
    let averageRIR: Int
    /// How many recent sessions contributed a tagged top set.
    let taggedSessionCount: Int
    /// Headline + body for the banner. Kept here so the view stays declarative.
    let title: String
    let message: String
}

/// Heuristic v1 (pure, no I/O). Over the most recent `window` sessions, take each
/// session's **top working set** (highest est-1RM among counting sets) and its
/// RIR when tagged. If at least `minTaggedSessions` of those are tagged AND the
/// floored average tagged RIR is ≤ `lowRIRThreshold` (consistently near failure),
/// return a suggestion; otherwise `nil` (no nagging on sparse or easy data).
///
/// - Parameters:
///   - recentSessions: any order; sorted newest-first internally.
///   - window: how many recent sessions to consider (default 6).
///   - minTaggedSessions: minimum tagged top sets required to fire (default 3).
///   - lowRIRThreshold: average at/below which we suggest a deload (default 1).
func deloadSuggestion(recentSessions: [WorkoutSession],
                      window: Int = 6,
                      minTaggedSessions: Int = 3,
                      lowRIRThreshold: Int = 1) -> DeloadSuggestion? {
    guard window > 0, minTaggedSessions > 0 else { return nil }

    let recent = recentSessions
        .sorted { $0.startedAt > $1.startedAt }
        .prefix(window)

    // Top working set's RIR per session, dropping sessions with no tagged top set.
    let topRIRs: [Int] = recent.compactMap { session in
        WorkoutAnalytics.bestSet(in: session.sets)?.rir
    }

    guard topRIRs.count >= minTaggedSessions else { return nil }

    let avg = topRIRs.reduce(0, +) / topRIRs.count   // integer floor
    guard avg <= lowRIRThreshold else { return nil }

    return DeloadSuggestion(
        averageRIR: avg,
        taggedSessionCount: topRIRs.count,
        title: "Hard stretch",
        message: "Your top sets have averaged RIR \(avg) over your last "
            + "\(topRIRs.count) sessions. Consider an easier week.")
}
```

> Note: `WorkoutAnalytics.bestSet(in:)` already filters to counting sets (`.working`/`.amrap`) and picks the highest est-1RM, so the heuristic reuses that single source of truth instead of re-implementing "top set" — DRY. The spec's "per muscle group" scoping is a tuning follow-up (Open Question 3); v1 is whole-session top-set, which is the simplest correct surface and keeps the function pure and testable.

- [ ] Run (expected **PASS**):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/FatigueSignalTests`
- [ ] Commit:
  `git add Pulse/Core/Workout/FatigueSignal.swift PulseTests/ActiveWorkout/FatigueSignalTests.swift && git commit -m "feat(workout): pure deloadSuggestion fatigue heuristic [BAK-36]"`

---

## Task 7 — Dismissible deload banner on Today

Wire the pure heuristic into `TodayModel` (computing it from recent sessions on load) and render a dismissible `DeloadBanner` at the top of `TodayView`. Dismiss is session-local (a flag in the model); persistence of dismissal across launches is a follow-up (YAGNI for v1).

**Files:** `Pulse/Features/Today/DeloadBanner.swift` (NEW), `Pulse/Features/Today/TodayModel.swift`, `Pulse/Features/Today/TodayView.swift`, `PulseTests/TodayModelTests.swift`

- [ ] Add a failing test to `PulseTests/TodayModelTests.swift` proving the model exposes a suggestion and that dismiss clears it. (Match the existing `TodayModel` init/repository shape used by the file's other tests — inject sessions via the same mock the suite already uses; if `TodayModel` does not currently receive sessions, add a `deloadSuggestion: DeloadSuggestion?` input to its load path. Confirm the exact repository injection point by reading `TodayModel.swift` first.)

```swift
@MainActor
func testDeloadBannerShowsThenDismisses() {
    // Arrange a model whose recent sessions trip the heuristic. Use the same
    // repository/mock pattern as the other TodayModel tests in this file.
    let model = TodayModel.makeWithHardRecentSessions()   // test helper / existing builder
    model.refreshDeloadSignal()                            // or set during load()
    XCTAssertNotNil(model.deloadSuggestion)
    model.dismissDeload()
    XCTAssertNil(model.deloadSuggestion)
}
```

- [ ] Run (expected **FAIL** — `deloadSuggestion`/`dismissDeload` don't exist):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/TodayModelTests`
- [ ] Minimal impl in `TodayModel.swift`. Add the stored state, a compute step folded into `load()`, and a dismiss. Because `TodayModel`'s repository is `MockTodayRepository`/`TodayRepository` (read `TodayModel.swift` for the exact protocol), source recent sessions from whichever repository the model already holds; if Today's repository does not expose sessions, inject a `SessionRepository` (or pass `[WorkoutSession]`) and compute once on load:

```swift
private(set) var deloadSuggestion: DeloadSuggestion?
private var deloadDismissed = false

/// Compute the advisory signal from recent sessions. Call at the end of load().
func refreshDeloadSignal(recentSessions: [WorkoutSession]) {
    guard !deloadDismissed else { deloadSuggestion = nil; return }
    deloadSuggestion = deloadSuggestion(recentSessions: recentSessions)
}

func dismissDeload() {
    deloadDismissed = true
    deloadSuggestion = nil
}
```

> If the local function name `deloadSuggestion(recentSessions:)` collides with the stored property `deloadSuggestion`, fully-qualify the call (`Pulse.deloadSuggestion(...)`) or rename the property to `deloadBanner`. Prefer renaming the **property** to `deloadBanner` to avoid the shadow — update the test and view accordingly.

- [ ] Create `Pulse/Features/Today/DeloadBanner.swift` — a dismissible advisory card, Theme tokens + Geist Mono eyebrow only:

```swift
import SwiftUI

/// Advisory, dismissible "consider a deload" banner. Display-only — it never
/// changes the program. Eyebrow uses Geist Mono via `.pulseStyle(.eyebrow)`.
struct DeloadBanner: View {
    @Environment(Theme.self) private var theme
    let suggestion: DeloadSuggestion
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing[2]) {
            VStack(alignment: .leading, spacing: theme.spacing[0]) {
                Text("FATIGUE")
                    .pulseStyle(.eyebrow)
                    .foregroundStyle(theme.inkSoft)
                Text(suggestion.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.ink)
                Text(suggestion.message)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button { onDismiss() } label: {
                Image(systemName: "xmark").foregroundStyle(theme.inkSoft)
            }
            .accessibilityIdentifier("today.deload.dismiss")
        }
        .padding(theme.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: theme.radiusCard)
            .strokeBorder(theme.accent2, lineWidth: 2))
        .accessibilityIdentifier("today.deloadBanner")
    }
}
```

- [ ] Render it at the top of the `loaded(skeleton:)` stack in `TodayView.swift`, above `greetingRow` (or directly under `topBar`):

```swift
VStack(alignment: .leading, spacing: 18) {
    topBar
    if let suggestion = model.deloadSuggestion {
        DeloadBanner(suggestion: suggestion) { model.dismissDeload() }
    }
    greetingRow
    TodayHeroCard(card: model.today) { model.startTodaysWorkout() }
    // ...
}
```

- [ ] Run (expected **PASS**) and the full suite:
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/TodayModelTests`
  then `-only-testing:PulseTests`
- [ ] Commit:
  `git add Pulse/Features/Today/DeloadBanner.swift Pulse/Features/Today/TodayModel.swift Pulse/Features/Today/TodayView.swift PulseTests/TodayModelTests.swift && git commit -m "feat(today): dismissible deload banner from fatigue signal [BAK-36]"`

---

## Manual verification checklist

The UI-test runner is broken on Xcode 26.5/iOS 26.5 (gate is `-only-testing:PulseTests`), so the following are **manual device/simulator checks** plus the one **integration check** against real Supabase. Run in the simulator with the mock path (`-uiMock`) unless noted.

### Capture UI (spec AC #4)
- [ ] Start a workout; on a **working** set the RIR selector (`0 1 2 3 4+`) appears below the steppers.
- [ ] On a **warmup**, **dropset**, or **to-failure** set the selector is **absent**.
- [ ] Tap "Log set" **without** touching the selector → the set logs and advances (fast path unaffected); the stored set's `rir` is `nil`.
- [ ] Tap a chip (e.g. `2`), then "Log set" → set logs with `rir == 2`; tapping the same chip again **deselects** it (back to `nil`).
- [ ] Changing set/step resets the selector to unset.

### Surfacing (spec AC #5)
- [ ] Open **Session Detail** for a session with tagged sets → the LOG row shows `… @RIR n`.
- [ ] Open a session with only untagged sets → **no** `RIR` text appears.
- [ ] Open **Exercise Detail** for an exercise with tagged history → the rep line shows `@RIR n`; untagged sessions show no RIR.
- [ ] Confirm the `@RIR n` text renders in Geist Mono (matches the surrounding `.rowSub`/eyebrow style) and uses Theme colors only.

### Deload banner (spec AC #6)
- [ ] With sample data seeded so recent top sets average RIR ≤1 across ≥3 tagged sessions, the **Today** screen shows the deload banner with the `accent2` border.
- [ ] Tap the dismiss (✕) → banner disappears and does not reappear during the session.
- [ ] With mixed/high RIR sample data (or fewer than 3 tagged sessions) the banner does **not** appear.

### Persistence — real Supabase round-trip (spec AC #3; integration, NOT in CI)
- [ ] Apply the migration to a dev Supabase project: `supabase migration up` (or `supabase db reset`). Confirm `session_sets.rir` exists as `smallint NULL` with the `>= 0` check and the column comment.
- [ ] Once live `SupabaseSessionRepository` wiring exists (or via a one-off SQL `insert`), write a `SessionSet` with `rir = 2`, read it back, and confirm the value survives the column mapping (`rir` ↔ `session_sets.rir`).
- [ ] Write a `SessionSet` with `rir == nil` → confirm it stores SQL `NULL`.
- [ ] **Legacy rows:** select a `session_sets` row inserted before migration `0003` (no `rir` written) → confirm it reads back as `rir == nil` in the decoded `SessionSet` (column is `NULL`).
- [ ] Re-confirm migration numbering: if `main` shipped a migration ≥ `0003` before merge, renumber this file to one past the highest committed prefix and rebase (the `ALTER TABLE` body is unchanged).

### Regression / build
- [ ] `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests` is green (all new + existing unit tests).
- [ ] `xcodebuild build -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16'` succeeds (no XcodeGen regen needed — no new target/membership; all new files land in existing folders already globbed by `project.yml`. If a new file is not picked up, run `xcodegen generate`).

---

## Spec coverage map

| Spec acceptance criterion | Covered by |
| --- | --- |
| AC #1 — `SessionSet` encodes/decodes with & without `rir` (nil round-trips) | Task 1 |
| AC #2 — `deloadSuggestion`: low RIR → suggestion; mixed/high → nil; below min count → nil | Task 6 |
| AC #3 — write/read session with RIR, value preserved; legacy rows read as nil | Task 2 (InMemory unit) + Task 3 + Manual checklist (live Supabase) |
| AC #4 — RIR selector appears for working sets; logging without it stores nil | Task 4 + Manual checklist |
| AC #5 — Logged RIR shows in Session Detail / Exercise Detail | Task 5 + Manual checklist |
| AC #6 — Deload banner appears under the heuristic and is dismissible | Task 7 + Manual checklist |
```
