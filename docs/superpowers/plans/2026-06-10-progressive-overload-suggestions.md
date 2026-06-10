# Progressive-Overload Suggestions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** During an active workout, compute a suggested weight × reps for each working set from the user's last performance of that exercise (double-progression rule), pre-seed the steppers with it, and surface a dismiss-free informational pill + rationale in `ActiveSetView`. Gate on `autoProgressWeight`; when off, fall back to "repeat last session". No history → no suggestion (steppers seed from `SetSpec`/planned weight as today).

**Architecture:** A pure, I/O-free engine `suggestProgression(_:)` in `Pulse/Core/Workout/ProgressionSuggestion.swift` holds the rule and is fully unit-tested against the 5 spec cases. `ActiveWorkoutModel` gains `progressionSuggestion(forStep:)` which pulls the most recent `[SessionSet]` for the step's exercise from the injected `historyRepo`, matches the relevant prior set (by set index / `order`, falling back to the top working set), and calls the engine. The current suggestion is cached on the model so `seedReps`/`seedWeight` reflect it (accepting is the default, zero friction) and the rationale is exposed for display. `ActiveSetView` renders an informational `SUGGESTED · …` pill (Geist Mono) next to the existing `↻ History` chip.

**Tech Stack:** SwiftUI, iOS 17+, MVVM + `@Observable`, Swift Concurrency. Data only via the existing `HistoryRepository` protocol — never Supabase directly. kg-only (v1), default increment 2.5 kg. Theme tokens only; no hardcoded colors/spacing. Unit tests via `xcodebuild test … -only-testing:PulseTests/…` (the UI-test runner is broken on this toolchain — gate on `PulseTests` only; visual checks go to the manual checklist).

---

## File Structure

```
Pulse/
  Core/
    Workout/
      ProgressionSuggestion.swift        # NEW — pure engine: ProgressionInput, ProgressionSuggestion, suggestProgression(_:)
    Models/
      WorkoutModels.swift                # unchanged (read-only reference: SetSpec, SessionSet, SetType)
    Data/
      Mocks/
        ActiveWorkoutMocks.swift         # EDIT — add a deterministic history mock that "met target" for the model test
  Features/
    ActiveWorkout/
      ActiveWorkoutModel.swift           # EDIT — autoProgress flag, suggestion cache, progressionSuggestion(forStep:), seed wiring, rationale
      ActiveSetView.swift                # EDIT — SUGGESTED pill + rationale caption next to the History chip
  App/
    AppShell.swift                       # EDIT (optional, final task) — pass the real autoProgress flag through
PulseTests/
  ActiveWorkout/
    ProgressionSuggestionTests.swift     # NEW — 5 spec unit cases for the pure engine
    ActiveWorkoutModelTests.swift        # EDIT — model integration cases (suggestion → seeds, fallback)
```

### Grounding notes (read before starting; from spec + code)

- **`SessionSet` has NO `variationID`.** Fields are `id, exerciseID, order, reps, weight, type` (`Pulse/Core/Models/WorkoutModels.swift`). The history repo keys on `exerciseID` only: `HistoryRepository.recentSets(exerciseID:) async throws -> [SessionSet]`. So matching prior performance is **by exercise + set index** (`order`), with a fallback to the top working set. The spec mentions "exercise/variation" but the model has no variation dimension — match on exercise only. **(Spec gap — noted; resolved by matching on exercise + set index.)**
- `SetSpec` = `{ id, reps, rir, type }`. `reps` is the planned target rep count. `type` ∈ `.working/.warmup/.dropset/.failure/.amrap`.
- `ActiveWorkoutModel.init(exerciseRepo:historyRepo:sessionWriter:)`. `seedReps`/`seedWeight` are computed: `seedReps = currentSet?.reps ?? 0`; `seedWeight = ActiveWorkoutSample.plannedWeight(exIdx:setIdx:)`.
- `WorkoutStep` exposes `exIdx` and `setIdx`. `currentStep` / `currentExercise` / `currentSet` exist (the latter two `private`).
- `logSet(reps:weight:)` builds `SessionSet(exerciseID:order:reps:weight:type:)` using `order: stepIdx`. Suggestions only apply to working sets; warmup/dropset/failure/amrap keep today's behavior.
- `UserSettings.autoProgressWeight: Bool` (default `true`) currently drives no logic and is **not** injected into `ActiveWorkoutModel`. We add an `autoProgress` init param defaulting to `true` so all existing call sites keep compiling; `AppShell` can pass the real flag in the final task.
- `WeightFormat.kg(_:)` → e.g. `"62.5 kg"` (trims `.0`). Reuse it for the pill — do not re-implement formatting.
- Suggestions only matter while a suggestion exists; the rule is purely reps-completion based (no RPE/RIR) per the non-goals.

---

## Task 1 — Pure engine `suggestProgression` (5 spec cases)

Implements the double-progression rule with zero I/O. This is the heart of the feature and is fully covered by the spec's unit acceptance criteria 1–5.

**Files:**
- `PulseTests/ActiveWorkout/ProgressionSuggestionTests.swift` (new)
- `Pulse/Core/Workout/ProgressionSuggestion.swift` (new)
- `project.yml` / `xcodegen` — new files under existing globbed source roots are picked up automatically; run `xcodegen generate` if the file does not appear in the target.

### Steps

- [ ] Write the failing test file `PulseTests/ActiveWorkout/ProgressionSuggestionTests.swift` covering all 5 cases:

```swift
import XCTest
@testable import Pulse

final class ProgressionSuggestionTests: XCTestCase {

    private func target(reps: Int) -> SetSpec { SetSpec(reps: reps, rir: 2, type: .working) }
    private func set(_ reps: Int, _ weight: Double) -> SessionSet {
        SessionSet(exerciseID: UUID(), order: 0, reps: reps, weight: weight, type: .working)
    }

    // Spec AC1 — no history → nil.
    func testNoHistoryReturnsNil() {
        let input = ProgressionInput(target: target(reps: 8), lastSets: [],
                                     increment: 2.5, autoProgress: true)
        XCTAssertNil(suggestProgression(input))
    }

    // Spec AC2 — hit target last time, autoProgress on → weight + increment, reps == target.
    func testHitTargetAddsIncrement() {
        let input = ProgressionInput(target: target(reps: 8),
                                     lastSets: [set(8, 60)],
                                     increment: 2.5, autoProgress: true)
        let s = try XCTUnwrap(suggestProgression(input))
        XCTAssertEqual(s.weight, 62.5, accuracy: 0.001)
        XCTAssertEqual(s.reps, 8)
        XCTAssertEqual(s.rationale, "Hit all reps last time → +2.5 kg")
    }

    // Beating target (more reps than planned) also progresses.
    func testBeatTargetAddsIncrement() {
        let input = ProgressionInput(target: target(reps: 8),
                                     lastSets: [set(10, 60)],
                                     increment: 2.5, autoProgress: true)
        let s = try XCTUnwrap(suggestProgression(input))
        XCTAssertEqual(s.weight, 62.5, accuracy: 0.001)
        XCTAssertEqual(s.reps, 8)
    }

    // Spec AC3 — missed target last time → same weight, reps == target.
    func testMissedTargetHoldsWeight() {
        let input = ProgressionInput(target: target(reps: 8),
                                     lastSets: [set(6, 60)],
                                     increment: 2.5, autoProgress: true)
        let s = try XCTUnwrap(suggestProgression(input))
        XCTAssertEqual(s.weight, 60, accuracy: 0.001)
        XCTAssertEqual(s.reps, 8)
        XCTAssertEqual(s.rationale, "Missed target last time → hold weight")
    }

    // Spec AC4 — autoProgress off → repeat last weight × last reps.
    func testAutoProgressOffRepeatsLast() {
        let input = ProgressionInput(target: target(reps: 8),
                                     lastSets: [set(6, 60)],
                                     increment: 2.5, autoProgress: false)
        let s = try XCTUnwrap(suggestProgression(input))
        XCTAssertEqual(s.weight, 60, accuracy: 0.001)
        XCTAssertEqual(s.reps, 6)
        XCTAssertEqual(s.rationale, "Repeat last session")
    }

    // Spec AC5 — increment is configurable (5.0 → +5.0).
    func testIncrementIsConfigurable() {
        let input = ProgressionInput(target: target(reps: 8),
                                     lastSets: [set(8, 60)],
                                     increment: 5.0, autoProgress: true)
        let s = try XCTUnwrap(suggestProgression(input))
        XCTAssertEqual(s.weight, 65, accuracy: 0.001)
        XCTAssertEqual(s.rationale, "Hit all reps last time → +5 kg")
    }
}
```

- [ ] Run it, expect **FAIL to build** (types/function do not exist yet):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/ProgressionSuggestionTests 2>&1 | tail -20`
- [ ] Create `Pulse/Core/Workout/ProgressionSuggestion.swift` with the minimal implementation:

```swift
import Foundation

/// Inputs to the (pure) progression rule. No I/O — `lastSets` is the caller's
/// already-fetched history slice for one exercise's most recent session.
struct ProgressionInput {
    let target: SetSpec            // planned reps/type for this set
    let lastSets: [SessionSet]     // same exercise, most recent session (may be empty)
    let increment: Double          // kg step for this movement (default 2.5)
    let autoProgress: Bool
}

/// A suggested load to pre-seed the steppers, with a short human rationale.
struct ProgressionSuggestion: Equatable {
    let weight: Double
    let reps: Int
    let rationale: String
}

/// Double-progression rule (v1, reps-completion based — no RPE/RIR):
/// - No history → `nil` (caller seeds from `SetSpec`/planned weight as today).
/// - `autoProgress == false` → repeat last weight × last reps ("Repeat last session").
/// - Last set met/beat target reps → +1 increment at target reps
///   ("Hit all reps last time → +<inc> kg").
/// - Last set missed target reps → same weight at target reps
///   ("Missed target last time → hold weight").
func suggestProgression(_ input: ProgressionInput) -> ProgressionSuggestion? {
    guard let last = input.lastSets.first else { return nil }

    if !input.autoProgress {
        return ProgressionSuggestion(weight: last.weight, reps: last.reps,
                                     rationale: "Repeat last session")
    }

    if last.reps >= input.target.reps {
        let bumped = last.weight + input.increment
        let incLabel = WeightFormat.kgNumeral(input.increment)
        return ProgressionSuggestion(weight: bumped, reps: input.target.reps,
                                     rationale: "Hit all reps last time → +\(incLabel) kg")
    }

    return ProgressionSuggestion(weight: last.weight, reps: input.target.reps,
                                 rationale: "Missed target last time → hold weight")
}
```

  Note: `WeightFormat.kgNumeral` trims `.0` so `2.5 → "2.5"` and `5.0 → "5"` (matches the test expectation `"+5 kg"`). The caller (Task 2) is responsible for selecting which prior set is `lastSets.first` — the engine just reads the first element.

- [ ] If the file is not in the target, run `xcodegen generate`.
- [ ] Run the test, expect **PASS** (all 6 methods green):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/ProgressionSuggestionTests 2>&1 | tail -20`
- [ ] Commit:
  `git add Pulse/Core/Workout/ProgressionSuggestion.swift PulseTests/ActiveWorkout/ProgressionSuggestionTests.swift project.yml`
  `git commit -m "feat(active): pure double-progression suggestion engine [BAK-35]"`

---

## Task 2 — Model wiring: `progressionSuggestion(forStep:)`, seed integration, rationale

`ActiveWorkoutModel` queries `historyRepo` for the step's exercise, picks the matching prior set (by set index `order`, fallback to top working set by weight), runs the engine, caches the result, and feeds `seedReps`/`seedWeight`. History is async, so the suggestion is loaded into a cache keyed by step index and the seeds read from that cache synchronously.

**Files:**
- `PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift` (edit — add integration cases)
- `Pulse/Core/Data/Mocks/ActiveWorkoutMocks.swift` (edit — add a "met target" deterministic mock)
- `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` (edit)

### Steps

- [ ] Add a deterministic history mock to `Pulse/Core/Data/Mocks/ActiveWorkoutMocks.swift` whose top working set matches the sample bench target (so the test asserts a clean +increment). Append:

```swift
/// History where the most-recent session hit the working target at a known
/// weight — used to assert `progressionSuggestion` bumps by the increment.
struct MetTargetHistoryRepository: HistoryRepository {
    func recentSets(exerciseID: Exercise.ID) async throws -> [SessionSet] {
        // bench set index 1 is a working set planned at 12 reps; "met" → 12 @ 60.
        [SessionSet(exerciseID: exerciseID, order: 0, reps: 15, weight: 40, type: .warmup),
         SessionSet(exerciseID: exerciseID, order: 1, reps: 12, weight: 60, type: .working),
         SessionSet(exerciseID: exerciseID, order: 2, reps: 10, weight: 60, type: .working),
         SessionSet(exerciseID: exerciseID, order: 3, reps: 8,  weight: 60, type: .working)]
    }
}
```

- [ ] Add failing model tests to `PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift`:

```swift
    // Spec AC6 — progressionSuggestion(forStep:) bumps by increment after a session
    // that met targets (via a history mock).
    func testProgressionSuggestionBumpsAfterMetTarget() async {
        let m = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MetTargetHistoryRepository(),
            sessionWriter: MockSessionWriter(),
            autoProgress: true)
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
        m.skipSet() // step 0 is bench warmup → step 1 (working, target 12 reps)
        await m.loadSuggestion(forStepIndex: m.stepIdx)
        let s = try? XCTUnwrap(m.currentSuggestion)
        XCTAssertEqual(s?.weight, 62.5, accuracy: 0.001) // 60 + 2.5
        XCTAssertEqual(s?.reps, 12)
        // Spec AC7 — seeds reflect the suggestion when present.
        XCTAssertEqual(m.seedWeight, 62.5, accuracy: 0.001)
        XCTAssertEqual(m.seedReps, 12)
    }

    // Spec AC7 — no history → no suggestion → seeds fall back to SetSpec / planned weight.
    func testNoSuggestionFallsBackToPlannedSeeds() async {
        let m = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: EmptyHistoryRepository(),
            sessionWriter: MockSessionWriter(),
            autoProgress: true)
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
        m.skipSet() // → step 1 (bench working, planned 60 kg, 12 reps)
        await m.loadSuggestion(forStepIndex: m.stepIdx)
        XCTAssertNil(m.currentSuggestion)
        XCTAssertEqual(m.seedWeight, 60, accuracy: 0.001)   // ActiveWorkoutSample.plannedWeight(1,*)
        XCTAssertEqual(m.seedReps, 12)                      // SetSpec.reps
    }

    // Warmup sets get no suggestion even with history.
    func testWarmupStepHasNoSuggestion() async {
        let m = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MetTargetHistoryRepository(),
            sessionWriter: MockSessionWriter(),
            autoProgress: true)
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets() // step 0 = warmup
        await m.loadSuggestion(forStepIndex: m.stepIdx)
        XCTAssertNil(m.currentSuggestion)
    }
```

  And add a tiny empty-history mock near the others in `ActiveWorkoutMocks.swift`:

```swift
/// History repo with nothing logged yet — drives the "no suggestion" path.
struct EmptyHistoryRepository: HistoryRepository {
    func recentSets(exerciseID: Exercise.ID) async throws -> [SessionSet] { [] }
}
```

- [ ] Run, expect **FAIL to build** (`autoProgress:` param, `loadSuggestion`, `currentSuggestion` don't exist):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/ActiveWorkoutModelTests 2>&1 | tail -25`

- [ ] Edit `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift`. Add the `autoProgress` stored property + init param (default keeps existing call sites valid):

```swift
    // progression
    /// Mirrors `UserSettings.autoProgressWeight`. Default true so existing call
    /// sites compile; `AppShell` passes the persisted value (Task 4).
    private let autoProgress: Bool
    /// Default kg increment for v1 (single value; per-movement is an Open Question).
    private let progressionIncrement: Double = 2.5
    /// Suggestion for the current step, loaded async from history. `nil` until
    /// loaded or when no suggestion applies (no history / non-working set).
    private(set) var currentSuggestion: ProgressionSuggestion?
```

  Update the initializer:

```swift
    init(exerciseRepo: SwapAlternativesProviding,
         historyRepo: HistoryRepository,
         sessionWriter: SessionWriter,
         autoProgress: Bool = true) {
        self.exerciseRepo = exerciseRepo
        self.historyRepo = historyRepo
        self.sessionWriter = sessionWriter
        self.autoProgress = autoProgress
    }
```

- [ ] Clear the cached suggestion whenever the session (re)starts, so a stale suggestion never leaks across workouts. In `startWorkout(_:)` add alongside the other resets:

```swift
        currentSuggestion = nil
```

- [ ] Add the suggestion machinery to the "derived UI state" / progression area of the model. The pure-matching helper is split out so it is independently testable and the async method stays thin:

```swift
    // MARK: - progression

    /// Pick the prior `SessionSet` that best represents "last time" for a given
    /// planned set index: prefer the working set logged at the same `order`,
    /// else fall back to the heaviest working set in the slice. Returns the
    /// chosen set in a single-element array shaped for `ProgressionInput`.
    /// Pure + internal so it can be unit-tested without async/history.
    func matchingLastSets(_ history: [SessionSet], setIndex: Int) -> [SessionSet] {
        let working = history.filter { $0.type == .working }
        guard !working.isEmpty else { return [] }
        if let atIndex = working.first(where: { $0.order == setIndex }) {
            return [atIndex]
        }
        if let top = working.max(by: { $0.weight < $1.weight }) {
            return [top]
        }
        return []
    }

    /// Compute the suggestion for a step without touching state — pure given the
    /// fetched history. Returns `nil` for non-working sets or when the engine
    /// declines (no history).
    func suggestion(forStep step: WorkoutStep, history: [SessionSet]) -> ProgressionSuggestion? {
        let ex = workout.exercises[step.exIdx]
        guard step.setIdx < ex.sets.count else { return nil }
        let spec = ex.sets[step.setIdx]
        guard spec.type == .working else { return nil }  // suggestions are working-set only
        let last = matchingLastSets(history, setIndex: step.setIdx)
        return suggestProgression(ProgressionInput(target: spec,
                                                   lastSets: last,
                                                   increment: progressionIncrement,
                                                   autoProgress: autoProgress))
    }

    /// Fetch history for the step's exercise and cache the resulting suggestion.
    /// Call this when the active set appears / the step changes.
    func loadSuggestion(forStepIndex i: Int) async {
        guard steps.indices.contains(i) else { currentSuggestion = nil; return }
        let step = steps[i]
        let exID = workout.exercises[step.exIdx].exercise.id
        let history = (try? await historyRepo.recentSets(exerciseID: exID)) ?? []
        currentSuggestion = suggestion(forStep: step, history: history)
    }
```

- [ ] Make the seeds prefer the cached suggestion, falling back to today's planned values. Replace the two `seedReps`/`seedWeight` computed properties:

```swift
    /// Stepper seeds (kg) — prefer the loaded progression suggestion, else the
    /// planned `SetSpec` / sample weight as before.
    var seedReps: Int { currentSuggestion?.reps ?? (currentSet?.reps ?? 0) }
    var seedWeight: Double {
        currentSuggestion?.weight
            ?? ActiveWorkoutSample.plannedWeight(exIdx: currentStep.exIdx, setIdx: currentStep.setIdx)
    }
```

- [ ] Run the model tests, expect **PASS**:
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/ActiveWorkoutModelTests 2>&1 | tail -25`
- [ ] Commit:
  `git add Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift Pulse/Core/Data/Mocks/ActiveWorkoutMocks.swift PulseTests/ActiveWorkout/ActiveWorkoutModelTests.swift`
  `git commit -m "feat(active): wire progression suggestion into model seeds [BAK-35]"`

---

## Task 3 — `ActiveSetView`: SUGGESTED pill + rationale, load on appear

Render an informational pill (Geist Mono / monospaced) beneath the action chips when a suggestion exists; hidden when none. Trigger `loadSuggestion` on appear and on step change, then re-seed the local `reps`/`weight` so the pill and steppers agree.

**Files:**
- `Pulse/Features/ActiveWorkout/ActiveSetView.swift` (edit)

### Steps

- [ ] In `ActiveSetView.body`, insert the pill between `actionChips` and `heroCard`, and load the suggestion on appear/step-change. Update the body and the `onChange` so the seed read happens *after* the async load. Replace the `body` with:

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            topBar
            progressSegments
            exerciseHeader
            actionChips
            if let s = model.currentSuggestion { suggestionPill(s) }
            heroCard
            if !isFailure { steppers }
            if exercise.supersetGroup != nil { partnerPeek }
            Spacer()
            footer
        }
        .padding(theme.spacing[5])
        .task(id: model.stepIdx) {
            await model.loadSuggestion(forStepIndex: model.stepIdx)
            reps = model.seedReps
            weight = model.seedWeight
        }
    }
```

  Note: `.task(id:)` replaces the old `.onChange(of: model.stepIdx, initial: true)` block — it runs on first appearance and re-runs whenever `stepIdx` changes, awaiting the history fetch before reading the (now suggestion-aware) seeds. Remove the old `.onChange` modifier.

- [ ] Add the pill view. It uses Theme tokens only (`inkFaint` border, `inkSoft` caption, `accent2` highlight numeral, `surface` fill) and `WeightFormat.kg` for the load:

```swift
    /// Informational progression pill — the steppers are already pre-seeded with
    /// this value, so the pill is read-only (lowest friction, per spec). Mono
    /// label per the design system; sits next to the History chip.
    private func suggestionPill(_ s: ProgressionSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("SUGGESTED · \(WeightFormat.kg(s.weight)) × \(s.reps)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(theme.accent2)
            Text(s.rationale)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusChip))
        .overlay(RoundedRectangle(cornerRadius: theme.radiusChip).strokeBorder(theme.inkFaint, lineWidth: 1))
        .accessibilityIdentifier("active.suggestionPill")
    }
```

  Confirm `theme.radiusChip` exists (the existing `StepperField` uses it). If a different radius token is preferred, use `theme.radius` family — never a hardcoded number.

- [ ] Build the app target to confirm it compiles (no UI test — runner is broken):
  `xcodebuild build -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -15`
- [ ] Commit:
  `git add Pulse/Features/ActiveWorkout/ActiveSetView.swift`
  `git commit -m "feat(active): show SUGGESTED progression pill on active set [BAK-35]"`

---

## Task 4 — Pass the persisted `autoProgressWeight` from the app shell (optional integration)

The engine and model honor `autoProgress`, but `AppShell` still constructs the model with the default `true`. Wire the real setting so the "off" branch (repeat last session) is reachable in the running app. Keep this small — if reading settings synchronously at shell init is awkward, default to `true` and load on appear is acceptable; do not expand scope into settings plumbing.

**Files:**
- `Pulse/App/AppShell.swift` (edit)

### Steps

- [ ] Inspect how `AppShell` / `AppEnvironment` already expose settings (e.g. `UserSettings` from `SettingsRepository`). If a synchronous default is readily available, pass it:

```swift
        let session = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MockHistoryRepository(),
            sessionWriter: MockSessionWriter(),
            autoProgress: UserSettings.default.autoProgressWeight)
```

  If settings are only available async, leave the default `true` and add a `// TODO(BAK-35): pass persisted autoProgressWeight once settings load is wired into the shell` — and note it in the PR. Do not block the feature on settings plumbing.
- [ ] Build:
  `xcodebuild build -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -15`
- [ ] Commit (only if a change was made):
  `git add Pulse/App/AppShell.swift`
  `git commit -m "feat(active): pass autoProgressWeight into the workout session [BAK-35]"`

---

## Task 5 — Full gate + self-review against the spec

**Files:** none (verification).

### Steps

- [ ] Run the full unit gate, expect **PASS**:
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests 2>&1 | tail -30`
- [ ] Re-read the spec's acceptance criteria and confirm coverage:
  - AC1 no history → nil — `ProgressionSuggestionTests.testNoHistoryReturnsNil`.
  - AC2 hit target, autoProgress on → +increment, reps == target — `testHitTargetAddsIncrement` (+ beat-target variant).
  - AC3 missed target → same weight, reps == target — `testMissedTargetHoldsWeight`.
  - AC4 autoProgress off → repeat last weight × reps — `testAutoProgressOffRepeatsLast`.
  - AC5 increment configurable — `testIncrementIsConfigurable`.
  - AC6 model returns +increment after a met-target session via mock — `testProgressionSuggestionBumpsAfterMetTarget`.
  - AC7 seeds reflect suggestion when present, else `SetSpec` — `testProgressionSuggestionBumpsAfterMetTarget` + `testNoSuggestionFallsBackToPlannedSeeds`.
  - AC8 pill shown when a suggestion exists, hidden when none — manual checklist (UI runner broken).
- [ ] Confirm no hardcoded colors/spacing in `ActiveSetView` (Theme tokens + `WeightFormat` only), Geist Mono (`.monospaced`) on the `SUGGESTED` label, kg-only.

---

## Manual verification checklist

(UI test runner is broken on this toolchain — verify these by hand in the simulator, gate CI on `-only-testing:PulseTests`.)

- [ ] Launch the app, start the sample workout, advance past the bench warmup to the first **working** set. A pill reading `SUGGESTED · 62.5 kg × 12` (with the default `MockHistoryRepository`, top working set 62.5 → met-target path) appears between the action chips and the hero card.
- [ ] The weight/reps steppers are pre-seeded to the suggested values (steppers match the pill) — accepting requires zero taps.
- [ ] The rationale caption under the pill reads one of: "Hit all reps last time → +2.5 kg", "Missed target last time → hold weight", or "Repeat last session" (when autoProgress is off), matching the scenario.
- [ ] Tapping a stepper `−`/`+` overrides the seed freely; the pill stays put (informational, not dismissed).
- [ ] A warmup / failure / amrap / dropset set shows **no** pill and seeds from the planned `SetSpec` as before.
- [ ] With history empty (e.g. a brand-new exercise / `EmptyHistoryRepository` build), no pill appears and the steppers seed from the planned weight (60 kg / 12 reps on bench set 1).
- [ ] Pill label renders in Geist Mono (monospaced), the load numeral uses `accent2`, the rationale uses `inkSoft`; nothing hardcoded — switch You → Palette between Coastal and Mint and confirm the pill recolors.
- [ ] Advancing to the next set re-loads the suggestion (no stale value from the previous step); the pill/seed update as the step changes.

---

## Spec gaps found (resolved inline)

1. **`SessionSet` has no `variationID`.** The spec and the parent task describe matching "exercise/variation", but `SessionSet` only carries `exerciseID` and `HistoryRepository.recentSets` keys on `exerciseID` alone. Resolved by matching on **exercise + set index** (`order`), with a fallback to the **top working set by weight** — exactly the spec's recommended Open-Question answer ("match by set index, fall back to top working set"). No variation dimension is used.
2. **`autoProgressWeight` is not injected into `ActiveWorkoutModel`.** It lives on `UserSettings` and drives no logic today. Resolved by adding an `autoProgress` init param (default `true`, so existing call sites and previews keep compiling) and an optional Task 4 to pass the persisted flag from `AppShell`. The "off" rule is fully unit-tested regardless.
3. **History fetch is async but seeds are read synchronously.** Resolved with a cached `currentSuggestion` populated by `loadSuggestion(forStepIndex:)` from a `.task(id: model.stepIdx)` in the view; seeds read the cache. The cache is cleared in `startWorkout` to avoid cross-session leakage.
4. **Increment-label formatting.** `"+2.5 kg"` vs `"+5 kg"` requires trimming `.0`; reused `WeightFormat.kgNumeral` rather than re-implementing, keeping a single source of truth for kg display.
