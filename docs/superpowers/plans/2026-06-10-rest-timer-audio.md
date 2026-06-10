# Rest Timer Audio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the foreground rest timer audible. Play a distinct "get ready" cue 10s before rest ends and a "rest over" cue at 0, each paired with a haptic, gated by `UserSettings.soundOnRestEnd`. Never interrupt the user's background audio (Spotify / Apple Music / podcasts keep playing).

**Architecture:** A new `RestCuePlaying` protocol in `Pulse/Core/Workout/` with a real `RestCueService` (AVAudioSession `.playback` + `[.mixWithOthers, .duckOthers]`, two preloaded `AVAudioPlayer`s, `UINotificationFeedbackGenerator` / `UIImpactFeedbackGenerator`) and a `MockRestCueService` for tests. The service is injected into `ActiveWorkoutModel`. All cue-firing decisions are **edge-triggered inside the model** (a new `tick(now:)`), not in `RestView`, so the 0.2s `TimelineView` cadence and stray post-rest ticks can never double-fire. `RestView` calls `model.tick(now:)` each tick instead of computing `remaining` itself. Two short audio assets ship in `Pulse/Resources/Audio/` and are bundled via `project.yml` + `xcodegen generate`.

**Tech Stack:** SwiftUI (iOS 17+), Swift Concurrency, MVVM + `@Observable`. AVFoundation (`AVAudioSession`, `AVAudioPlayer`), UIKit haptics. XcodeGen project generation. Unit tests in the `PulseTests` target (XCTest). UI-test runner is broken on this machine — **all automated tests are `PulseTests` unit tests gated with `-only-testing:PulseTests`**; audio-session/device behaviour is verified manually.

---

## File Structure

### Created
- `Pulse/Core/Workout/RestCueService.swift` — `RestCuePlaying` protocol, real `RestCueService` (audio session + players + haptics), `NoopRestCueService` (default for previews/non-test call sites).
- `Pulse/Core/Data/Mocks/RestCueMocks.swift` — `MockRestCueService` recording `prepare()`/`warn()`/`end()`/`teardown()` call counts and order, for unit tests.
- `Pulse/Resources/Audio/rest-warn.caf` — single soft tick, ~0.3s (the T-10s "get ready" cue).
- `Pulse/Resources/Audio/rest-end.caf` — double chime, ~0.6s (the rest-over cue).
- `PulseTests/ActiveWorkout/RestCueFiringTests.swift` — unit tests for the model's edge-triggered firing against `MockRestCueService`.

### Modified
- `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` — inject `restCue: RestCuePlaying`; add `soundOnRestEnd: Bool`; add `private(set) var didWarn`; add `tick(now:)`; call `prepare()` in `startRest`, `warn()`/`end()`/`teardown()` from `tick`/`afterRest`; re-arm `didWarn` in `adjustRest`.
- `Pulse/Features/ActiveWorkout/RestView.swift` — call `model.tick(now:)` in the `TimelineView` closure (replaces the inline `remainingRest` call and the `onChange(afterRest)` trigger).
- `project.yml` — bundle `Pulse/Resources/Audio` as resources for the `Pulse` target.

### Untouched but relevant (read for context)
- `Pulse/Core/Models/ProfileModels.swift:57` — `UserSettings.soundOnRestEnd` (default `true`).
- `Pulse/Features/You/YouModel.swift:56` — `setSoundOnRest(_:)` (the toggle's writer; not wired to the model in v1 — see Spec Gaps).
- `Pulse/App/AppShell.swift:12` — the one production `ActiveWorkoutModel(...)` call site.

---

## Notes for the implementer

- **Branch / commits:** Conventional commits, each ending with `[BAK-33]`. Branch already exists for this work; do not touch production code outside the files listed.
- **Test gate (machine defect):** the UI-test runner crashes on Xcode 26.5/iOS 26.5. Run unit tests only, e.g.:
  ```
  xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' \
    -only-testing:PulseTests/RestCueFiringTests
  ```
  Pick whatever simulator name `xcrun simctl list devices available` shows; the command above is the template every test step uses.
- **Defaulting strategy:** `ActiveWorkoutModel.init` gains `restCue: RestCuePlaying = NoopRestCueService()` and `soundOnRestEnd: Bool = true` as the **last** params with defaults, so the 5 existing preview call sites and the `AppShell` call site compile unchanged. Tests pass `MockRestCueService` explicitly. This keeps the change DRY (no edits to preview sites) and YAGNI (no settings plumbing beyond the flag — see Spec Gaps).
- **Why `tick(now:)` and not "extend remainingRest":** `remainingRest(now:)` is a pure getter called from multiple places (`RestView` progress ring math, tests). Keeping it pure and adding a separate side-effecting `tick(now:)` avoids surprising callers. `tick` computes remaining, fires edge-triggered cues, returns `remaining` so the View still gets its value from one call.
- **Audio assets:** create real `.caf` files (don't commit empty placeholders — `AVAudioPlayer(contentsOf:)` must succeed). Generate them with `afconvert` from short system-style tones, e.g.:
  ```
  # warn: single 880Hz tick ~0.25s; end: two 660/990Hz chimes ~0.6s
  # (any short royalty-free tone works; keep them < 1s and quiet)
  ```
  If you only have a `.wav`/`.aiff`, convert: `afconvert -f caff -d LEI16@44100 in.wav Pulse/Resources/Audio/rest-warn.caf`. The exact tone is a product detail; correctness here = files exist, load into `AVAudioPlayer`, and play. Audibility is a manual-checklist item.

---

## Task 1 — Add the `MockRestCueService` (test double first)

TDD setup: we need the mock before we can write failing model tests. This task creates the protocol stub it conforms to and the mock; no behaviour yet.

**Files:**
- Create: `Pulse/Core/Workout/RestCueService.swift` (protocol only, this task)
- Create: `Pulse/Core/Data/Mocks/RestCueMocks.swift`

- [ ] Create `Pulse/Core/Workout/RestCueService.swift` with the protocol and a no-op default impl:
```swift
import Foundation

/// Plays the rest-timer audio + haptic cues. Injected into `ActiveWorkoutModel`
/// so cue firing is testable with a mock and the model never touches AVFoundation.
/// Mock-friendly per repo convention (protocol + real impl + mock).
protocol RestCuePlaying {
    /// Configure the audio session and preload players. Called when rest starts.
    func prepare()
    /// T-10s "get ready" cue: soft tick + light impact haptic.
    func warn()
    /// Rest-over cue: double chime + success notification haptic.
    func end()
    /// Deactivate the audio session when leaving the rest screen.
    func teardown()
}

/// Default no-op used by SwiftUI previews and any call site that doesn't supply
/// a real service. Keeps `ActiveWorkoutModel.init` ergonomic without pulling
/// AVFoundation into preview rendering.
struct NoopRestCueService: RestCuePlaying {
    func prepare() {}
    func warn() {}
    func end() {}
    func teardown() {}
}
```
- [ ] Create `Pulse/Core/Data/Mocks/RestCueMocks.swift`:
```swift
import Foundation
@testable import Pulse

/// Records cue calls in order for unit tests. Reference type so the model's
/// stored copy and the test's handle observe the same call log.
final class MockRestCueService: RestCuePlaying {
    enum Call: Equatable { case prepare, warn, end, teardown }
    private(set) var calls: [Call] = []

    var warnCount: Int { calls.filter { $0 == .warn }.count }
    var endCount: Int { calls.filter { $0 == .end }.count }
    var prepareCount: Int { calls.filter { $0 == .prepare }.count }
    var teardownCount: Int { calls.filter { $0 == .teardown }.count }

    func prepare() { calls.append(.prepare) }
    func warn() { calls.append(.warn) }
    func end() { calls.append(.end) }
    func teardown() { calls.append(.teardown) }
}
```
> `@testable import Pulse` here is only needed if the mock lives in a file compiled into the test target. `RestCuePlaying` is in the app target, so the mock file can be in either. Put it under `Pulse/Core/Data/Mocks/` (compiled into the app target, matching `ActiveWorkoutMocks.swift`) and **drop the `@testable import Pulse` line** — the protocol is already in-module there. Use this version instead:
```swift
import Foundation

/// Records cue calls in order for unit tests. Reference type so the model's
/// stored copy and the test's handle observe the same call log.
final class MockRestCueService: RestCuePlaying {
    enum Call: Equatable { case prepare, warn, end, teardown }
    private(set) var calls: [Call] = []

    var warnCount: Int { calls.filter { $0 == .warn }.count }
    var endCount: Int { calls.filter { $0 == .end }.count }
    var prepareCount: Int { calls.filter { $0 == .prepare }.count }
    var teardownCount: Int { calls.filter { $0 == .teardown }.count }

    func prepare() { calls.append(.prepare) }
    func warn() { calls.append(.warn) }
    func end() { calls.append(.end) }
    func teardown() { calls.append(.teardown) }
}
```
- [ ] Build the app target to confirm it compiles (no test yet):
```
xcodebuild build -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16'
```
  Expected: **BUILD SUCCEEDED**.
- [ ] Commit:
```
git add Pulse/Core/Workout/RestCueService.swift Pulse/Core/Data/Mocks/RestCueMocks.swift
git commit -m "feat(active): add RestCuePlaying protocol + mock [BAK-33]"
```

---

## Task 2 — Inject `restCue` + `soundOnRestEnd` into the model (no firing yet)

Wire the dependency through `init` with defaults so existing call sites are untouched, and add the `soundOnRestEnd` flag and `didWarn` state. No cue calls yet — that's Task 3+ (TDD: we add state, then test the firing behaviour against it).

**Files:**
- Modify: `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` (deps block ~L9-12, rest-state block ~L27-29, `init` ~L34-40)

- [ ] In `ActiveWorkoutModel.swift`, add to the dependencies block (after `sessionWriter` at ~L11):
```swift
    private let restCue: RestCuePlaying
```
- [ ] In the rest-state block (after `restEndsAt` at ~L29) add the gating flag and warn-armed state:
```swift
    /// Mirrors `UserSettings.soundOnRestEnd`. When false, no cues fire (rest still
    /// advances normally). Settable so the app shell can sync it from settings.
    var soundOnRestEnd: Bool
    /// Edge-trigger guard: true once `warn()` has fired for the current rest.
    /// Re-armed to false on `startRest` and on any `adjustRest` that pushes
    /// remaining back above the 10s warn threshold.
    private(set) var didWarn = false
```
- [ ] Update `init` (~L34-40) to accept and store the new params with defaults (keep them last so call sites compile):
```swift
    init(exerciseRepo: SwapAlternativesProviding,
         historyRepo: HistoryRepository,
         sessionWriter: SessionWriter,
         restCue: RestCuePlaying = NoopRestCueService(),
         soundOnRestEnd: Bool = true) {
        self.exerciseRepo = exerciseRepo
        self.historyRepo = historyRepo
        self.sessionWriter = sessionWriter
        self.restCue = restCue
        self.soundOnRestEnd = soundOnRestEnd
    }
```
- [ ] Build to confirm all existing call sites (`AppShell`, 5 previews, tests) still compile:
```
xcodebuild build -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16'
```
  Expected: **BUILD SUCCEEDED**.
- [ ] Commit:
```
git add Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift
git commit -m "feat(active): inject RestCuePlaying + soundOnRestEnd flag into model [BAK-33]"
```

---

## Task 3 — `prepare()` on rest start + `end()` on rest finish (AC: end cue, skip plays no end)

Covers Spec AC "audible cue when rest ends" and Spec firing rule "Skipping rest plays no end cue". TDD: write the two failing tests, then implement.

**Files:**
- Create: `PulseTests/ActiveWorkout/RestCueFiringTests.swift`
- Modify: `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` (`startRest` ~L103, `afterRest` ~L90-95)

### Write the failing tests
- [ ] Create `PulseTests/ActiveWorkout/RestCueFiringTests.swift` (matches `ActiveWorkoutModelTests` style — `XCTestCase`, `@testable import Pulse`, fixed `Date`s, helper factory):
```swift
import XCTest
@testable import Pulse

final class RestCueFiringTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_000)

    /// Builds a started model wired to a recording mock cue. `sound` toggles the
    /// gating flag. Returns both so tests can inspect the call log.
    private func make(sound: Bool = true) -> (ActiveWorkoutModel, MockRestCueService) {
        let cue = MockRestCueService()
        let m = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MockHistoryRepository(),
            sessionWriter: MockSessionWriter(),
            restCue: cue,
            soundOnRestEnd: sound)
        m.startWorkout(ActiveWorkoutSample.workout)
        m.beginSets()
        return (m, cue)
    }

    /// Drives the model into rest at `base` (step 0 bench warmup → rest).
    private func enterRest(_ m: ActiveWorkoutModel) {
        m.logSet(reps: 15, weight: 40, now: base)
        XCTAssertEqual(m.phase, .rest)
    }

    // Rest start preps the cue service.
    func testStartRestPreparesCue() {
        let (m, cue) = make()
        enterRest(m)
        XCTAssertEqual(cue.prepareCount, 1)
        XCTAssertEqual(cue.endCount, 0)
    }

    // Auto-finish at 0 fires exactly one end() then teardown().
    func testRestEndFiresEndThenTeardown() {
        let (m, cue) = make()
        enterRest(m)
        _ = m.tick(now: base.addingTimeInterval(90))   // remaining == 0
        XCTAssertEqual(cue.endCount, 1)
        XCTAssertEqual(cue.teardownCount, 1)
        XCTAssertEqual(m.phase, .active)
    }

    // "Skip rest" mid-rest plays NO end cue but still tears down the session.
    func testSkipRestPlaysNoEndButTearsDown() {
        let (m, cue) = make()
        enterRest(m)
        m.afterRest()                                   // user tapped Skip while remaining > 0
        XCTAssertEqual(cue.endCount, 0)
        XCTAssertEqual(cue.teardownCount, 1)
        XCTAssertEqual(m.phase, .active)
    }
}
```
- [ ] Run — expect **FAIL** (model has no `tick(now:)`, and `afterRest`/`startRest` don't call the cue yet; likely a compile failure on `m.tick`):
```
xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PulseTests/RestCueFiringTests
```
  Expected: **TEST FAILED** (compile error: value of type 'ActiveWorkoutModel' has no member 'tick').

### Implement
- [ ] In `ActiveWorkoutModel.swift`, make `startRest` prepare the cue and arm the warn (replace the one-line `startRest` at ~L103):
```swift
    private func startRest(now: Date) {
        restEndsAt = now.addingTimeInterval(restTotal)
        didWarn = false
        restCue.prepare()
    }
```
- [ ] Add a `tick(now:)` that owns edge-triggered firing. Place it just below `remainingRest(now:)` (~L114). It returns `remaining` so `RestView` reads it from one call:
```swift
    /// Called every `TimelineView` tick while resting. Computes remaining time,
    /// fires the warn cue once at <= 10s and the end transition at <= 0, and
    /// returns the remaining seconds for the view. Edge-triggering lives here
    /// (not the view) so the 0.2s cadence and stray ticks can't double-fire.
    @discardableResult
    func tick(now: Date = .now) -> TimeInterval {
        let remaining = remainingRest(now: now)
        guard phase == .rest else { return remaining }
        if remaining <= 10, !didWarn {
            didWarn = true
            if soundOnRestEnd { restCue.warn() }
        }
        if remaining <= 0 {
            afterRest()
        }
        return remaining
    }
```
- [ ] Update `afterRest` (~L90-95) so the **auto-finish at 0** plays `end()` while **Skip does not**. The distinction: when `tick` calls `afterRest` at `remaining <= 0` we want the end cue; when the user taps Skip (remaining > 0) we don't. Drive this off remaining time, computed inside `afterRest`, so a single guarded path covers both and stays idempotent:
```swift
    /// Rest finished (auto at 0) or "Skip rest" — advance, clamp, back to active.
    /// Guarded so a stray `TimelineView` tick after we've left rest is a no-op.
    /// Plays the end cue only on a natural finish (remaining <= 0); Skip is silent.
    func afterRest() {
        guard phase == .rest else { return }
        let ended = remainingRest() <= 0
        if ended, soundOnRestEnd { restCue.end() }
        restCue.teardown()
        stepIdx = min(stepIdx + 1, steps.count - 1)
        restEndsAt = nil
        phase = .active
    }
```
> Note: `afterRest()` has a default `now = .now` indirectly via `remainingRest()`. In `tick(now:)` the call to `afterRest()` happens right after we computed `remaining <= 0`, but `afterRest` re-reads `remainingRest(now: .now)`. In tests we drive time explicitly via `tick(now:)`, and the natural-finish branch needs `afterRest` to see `remaining <= 0`. To keep this deterministic, change `afterRest` to take `now`:
```swift
    func afterRest(now: Date = .now) {
        guard phase == .rest else { return }
        let ended = remainingRest(now: now) <= 0
        if ended, soundOnRestEnd { restCue.end() }
        restCue.teardown()
        stepIdx = min(stepIdx + 1, steps.count - 1)
        restEndsAt = nil
        phase = .active
    }
```
  And in `tick`, call `afterRest(now: now)`:
```swift
        if remaining <= 0 {
            afterRest(now: now)
        }
```
  `RestView`'s "Skip rest" / forward buttons call `model.afterRest()` (defaulting `now = .now`, remaining still > 0 → silent). Existing `ActiveWorkoutModelTests` call `m.afterRest()` with no arg — still valid because the param has a default. Verify the existing test `testAfterRestAdvancesAndClampsAtLast` still passes (those afterRest calls have `restEndsAt == base+90` but `now == .now` far in the future → `remaining == 0` → would fire `end()` on the mock... but those tests use the **default `NoopRestCueService`**, so no assertion breaks). Confirmed safe.
- [ ] Run the new tests — expect **PASS**:
```
xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PulseTests/RestCueFiringTests
```
  Expected: **TEST SUCCEEDED** (3 tests).
- [ ] Run the existing model tests to confirm no regression:
```
xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PulseTests/ActiveWorkoutModelTests
```
  Expected: **TEST SUCCEEDED**.
- [ ] Commit:
```
git add Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift PulseTests/ActiveWorkout/RestCueFiringTests.swift
git commit -m "feat(active): fire end cue on natural rest finish, silent on skip [BAK-33]"
```

---

## Task 4 — Warn cue at T-10s, fired exactly once (AC: warn once at ≤10s)

Covers Spec AC "one `warn()` at ≤10s remaining" and Spec firing rule "warn at remaining<=10 once". The warn logic already lives in `tick` from Task 3; this task adds the tests that lock it down (and a stray-tick guard test).

**Files:**
- Modify: `PulseTests/ActiveWorkout/RestCueFiringTests.swift`

- [ ] Add to `RestCueFiringTests`:
```swift
    // From a 90s rest, exactly one warn() at <= 10s and exactly one end() at 0.
    func testOneWarnAtTenSecondsAndOneEndAtZero() {
        let (m, cue) = make()
        enterRest(m)
        // Tick across the warn boundary multiple times — must not double-warn.
        _ = m.tick(now: base.addingTimeInterval(79))   // remaining 11 → no warn
        XCTAssertEqual(cue.warnCount, 0)
        _ = m.tick(now: base.addingTimeInterval(80))   // remaining 10 → warn
        _ = m.tick(now: base.addingTimeInterval(80.2)) // still in window → no second warn
        _ = m.tick(now: base.addingTimeInterval(85))   // still in window → no second warn
        XCTAssertEqual(cue.warnCount, 1)
        XCTAssertEqual(cue.endCount, 0)
        _ = m.tick(now: base.addingTimeInterval(90))   // remaining 0 → end
        XCTAssertEqual(cue.endCount, 1)
        XCTAssertEqual(cue.warnCount, 1)
    }

    // A stray tick after the model has already left rest does not fire a 2nd end().
    func testStrayTickAfterFinishDoesNotDoubleFire() {
        let (m, cue) = make()
        enterRest(m)
        _ = m.tick(now: base.addingTimeInterval(90))   // ends: end() once, phase → active
        XCTAssertEqual(cue.endCount, 1)
        _ = m.tick(now: base.addingTimeInterval(90.2)) // stray tick, phase == .active
        _ = m.tick(now: base.addingTimeInterval(91))   // stray tick
        XCTAssertEqual(cue.endCount, 1)                // still one
        XCTAssertEqual(cue.teardownCount, 1)           // teardown not repeated
    }
```
- [ ] Run — expect **PASS** (logic already implemented in Task 3; the `guard phase == .rest` in `tick` and the `guard phase == .rest` in `afterRest` provide the stray-tick protection):
```
xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PulseTests/RestCueFiringTests
```
  Expected: **TEST SUCCEEDED** (5 tests).
- [ ] Commit:
```
git add PulseTests/ActiveWorkout/RestCueFiringTests.swift
git commit -m "test(active): lock single warn at T-10 and no double-fire on stray ticks [BAK-33]"
```

---

## Task 5 — `soundOnRestEnd == false` silences cues; rest still advances (AC: gating)

Covers Spec AC "soundOnRestEnd == false → zero warn/end calls; rest still advances".

**Files:**
- Modify: `PulseTests/ActiveWorkout/RestCueFiringTests.swift`

- [ ] Add:
```swift
    // Sound off: no warn() / end(), but rest still progresses and advances the step.
    func testSoundOffSilencesCuesButRestStillAdvances() {
        let (m, cue) = make(sound: false)
        enterRest(m)
        let startStep = m.stepIdx
        _ = m.tick(now: base.addingTimeInterval(80))   // warn window
        _ = m.tick(now: base.addingTimeInterval(90))   // end
        XCTAssertEqual(cue.warnCount, 0)
        XCTAssertEqual(cue.endCount, 0)
        XCTAssertEqual(m.phase, .active)               // advanced
        XCTAssertEqual(m.stepIdx, startStep + 1)
    }
```
- [ ] Run — expect **PASS** (gating is the `if soundOnRestEnd` guards already in `tick`/`afterRest`):
```
xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PulseTests/RestCueFiringTests
```
  Expected: **TEST SUCCEEDED** (6 tests).
- [ ] Commit:
```
git add PulseTests/ActiveWorkout/RestCueFiringTests.swift
git commit -m "test(active): assert soundOnRestEnd gates all cues [BAK-33]"
```

---

## Task 6 — `+30s` adjustment re-arms the warn (AC: re-arm after adjust)

Covers Spec AC "+30s adjustment while in the warn window re-arms and warns again later" and firing rule "adjustRest that pushes remaining back above 10s re-arms didWarn".

**Files:**
- Modify: `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` (`adjustRest` ~L105-109)
- Modify: `PulseTests/ActiveWorkout/RestCueFiringTests.swift`

### Write the failing test
- [ ] Add:
```swift
    // Warn fires at 10s; +30s pushes remaining back to 40s and re-arms; a later
    // pass through the 10s window warns a SECOND time.
    func testAdjustAboveThresholdReArmsWarn() {
        let (m, cue) = make()
        enterRest(m)                                    // restEndsAt = base + 90
        _ = m.tick(now: base.addingTimeInterval(82))    // remaining 8 → warn (#1)
        XCTAssertEqual(cue.warnCount, 1)
        m.adjustRest(30, now: base.addingTimeInterval(82)) // remaining 8 → 38 (> 10): re-arm
        XCTAssertFalse(m.didWarn)
        _ = m.tick(now: base.addingTimeInterval(82))    // remaining 38 → no warn yet
        XCTAssertEqual(cue.warnCount, 1)
        _ = m.tick(now: base.addingTimeInterval(112))   // remaining 8 again → warn (#2)
        XCTAssertEqual(cue.warnCount, 2)
    }

    // An adjustment that stays within the warn window does NOT re-arm (no extra warn).
    func testAdjustWithinWindowDoesNotReArm() {
        let (m, cue) = make()
        enterRest(m)
        _ = m.tick(now: base.addingTimeInterval(82))    // remaining 8 → warn (#1)
        m.adjustRest(-2, now: base.addingTimeInterval(82)) // remaining 8 → 6 (still <= 10)
        XCTAssertTrue(m.didWarn)
        _ = m.tick(now: base.addingTimeInterval(82))
        XCTAssertEqual(cue.warnCount, 1)                // no second warn
    }
```
- [ ] Run — expect **FAIL** (`adjustRest` doesn't re-arm yet; `didWarn` stays true so warnCount stuck at 1):
```
xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PulseTests/RestCueFiringTests/testAdjustAboveThresholdReArmsWarn
```
  Expected: **TEST FAILED** (`XCTAssertFalse(m.didWarn)` fails / warnCount 1 != 2).

### Implement
- [ ] Update `adjustRest` (~L105-109) to re-arm when the new remaining clears the 10s threshold:
```swift
    func adjustRest(_ delta: TimeInterval, now: Date = .now) {
        guard let end = restEndsAt else { return }
        let newRemaining = max(0, end.timeIntervalSince(now) + delta)
        restEndsAt = now.addingTimeInterval(newRemaining)
        // Re-arm the warn if the adjustment pushed us back above the warn window,
        // so a later descent through 10s warns again.
        if newRemaining > 10 { didWarn = false }
    }
```
- [ ] Run the two new tests — expect **PASS**:
```
xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PulseTests/RestCueFiringTests
```
  Expected: **TEST SUCCEEDED** (8 tests).
- [ ] Run `ActiveWorkoutModelTests` to confirm `testAdjustRestClampsAtZeroNoUpperClamp` still passes (the `if newRemaining > 10` line is additive):
```
xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PulseTests/ActiveWorkoutModelTests
```
  Expected: **TEST SUCCEEDED**.
- [ ] Commit:
```
git add Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift PulseTests/ActiveWorkout/RestCueFiringTests.swift
git commit -m "feat(active): re-arm rest warn cue when adjustment clears the warn window [BAK-33]"
```

---

## Task 7 — Wire `RestView` to drive `tick(now:)`

`RestView` currently computes `remaining` itself and triggers `afterRest()` via `onChange`. Move both behind `model.tick(now:)` so cues fire on the real tick cadence and the view stays a thin renderer. No new unit test (UI runner is broken); the model tests already cover firing. This is a mechanical refactor verified by build + manual checklist.

**Files:**
- Modify: `Pulse/Features/ActiveWorkout/RestView.swift` (`body` ~L7-15)

- [ ] Replace `RestView.body` (~L7-15) so the tick call both fires cues and yields `remaining`:
```swift
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            // tick(now:) advances cue firing AND returns remaining for the view.
            // afterRest() is now called inside tick at remaining <= 0, so the
            // previous onChange(remaining <= 0) trigger is removed.
            let remaining = model.tick(now: context.date)
            content(remaining: remaining)
        }
    }
```
> Removing the `onChange(of: remaining <= 0)` is intentional: `tick` calls `afterRest(now:)` itself at `remaining <= 0`. Keeping the old `onChange` would be a redundant second path (and `afterRest`'s `phase == .rest` guard already makes it harmless, but DRY says remove it).
- [ ] The "Skip rest →" button and the forward chevron still call `model.afterRest()` (no `now:` arg → defaults to `.now`, remaining > 0 → silent). Leave those lines unchanged.
- [ ] Build:
```
xcodebuild build -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16'
```
  Expected: **BUILD SUCCEEDED**.
- [ ] Commit:
```
git add Pulse/Features/ActiveWorkout/RestView.swift
git commit -m "refactor(active): drive RestView cue firing through model.tick [BAK-33]"
```

---

## Task 8 — Real `RestCueService` (audio session + players + haptics)

Implement the production service. No automated test (audio/haptics are device-only — manual checklist). TDD doesn't apply to the AVFoundation glue; correctness is verified by build + manual checklist + the model tests that already prove the *calls* happen.

**Files:**
- Modify: `Pulse/Core/Workout/RestCueService.swift` (add the real impl below the protocol)

- [ ] Append the real implementation to `RestCueService.swift`:
```swift
import AVFoundation
import UIKit

/// Real cue player. Mixes short cues over background audio without interrupting
/// it (`.ambient` + `.mixWithOthers`) and pairs each with a haptic so the cue
/// still registers when the device is muted or quiet. Marked @MainActor because
/// haptic generators and player setup are UIKit/main-thread friendly.
@MainActor
final class RestCueService: RestCuePlaying {
    private let session = AVAudioSession.sharedInstance()
    private var warnPlayer: AVAudioPlayer?
    private var endPlayer: AVAudioPlayer?
    private let notify = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .light)

    init() {
        warnPlayer = Self.makePlayer(named: "rest-warn")
        endPlayer = Self.makePlayer(named: "rest-end")
    }

    private static func makePlayer(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else {
            assertionFailure("Missing bundled audio asset \(name).caf")
            return nil
        }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }

    func prepare() {
        // .playback is audible even when the hardware silent switch is on
        // (important in a gym). .mixWithOthers keeps Spotify/podcasts playing;
        // .duckOthers briefly dips that audio so the cue cuts through.
        try? session.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
        warnPlayer?.prepareToPlay()
        endPlayer?.prepareToPlay()
        notify.prepare()
        impact.prepare()
    }

    func warn() {
        impact.impactOccurred()
        warnPlayer?.currentTime = 0
        warnPlayer?.play()
    }

    func end() {
        notify.notificationOccurred(.success)
        endPlayer?.currentTime = 0
        endPlayer?.play()
    }

    func teardown() {
        // Hand the session back so other apps can resume full control.
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
```
- [ ] Build (will succeed even before the .caf files exist — the `Bundle.main.url` returns nil at runtime, guarded by `assertionFailure`):
```
xcodebuild build -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16'
```
  Expected: **BUILD SUCCEEDED**.
- [ ] Commit:
```
git add Pulse/Core/Workout/RestCueService.swift
git commit -m "feat(active): real RestCueService with playback duck-mix + haptics [BAK-33]"
```

---

## Task 9 — Add the two audio assets + bundle them via project.yml

Covers the resource-bundling requirement. XcodeGen auto-detects known resource extensions inside a globbed source path, but `.caf` files are safest bundled with an explicit resources build phase. Add an explicit `resources` entry so the assets land in the app bundle deterministically.

**Files:**
- Create: `Pulse/Resources/Audio/rest-warn.caf`
- Create: `Pulse/Resources/Audio/rest-end.caf`
- Modify: `project.yml` (the `Pulse` target's `sources`)

- [ ] Create `Pulse/Resources/Audio/` and add the two real `.caf` files (see "Notes for the implementer" for `afconvert` recipe). They must be loadable by `AVAudioPlayer` — verify locally:
```
afinfo Pulse/Resources/Audio/rest-warn.caf && afinfo Pulse/Resources/Audio/rest-end.caf
```
  Expected: both print valid CAF info (duration < 1s).
- [ ] In `project.yml`, the `Pulse` target already globs `- Pulse` as sources. XcodeGen treats unknown extensions under a source glob as resources, but to be explicit and avoid the glob trying to compile them, add an explicit resources path. Change the `Pulse` target `sources:` block (lines ~15-20) to add a `buildPhase: resources` entry for the audio folder:
```yaml
    sources:
      - path: Pulse
        excludes:
          - "Resources/Audio/**"
      - path: Pulse/Resources/Audio
        buildPhase: resources
      # Dual-compiled into the app target (also globbed by PulseWidgets) so the
      # DEBUG LiveActivityDebugScreen can render the shared Live Activity subviews
      # in-app for XCUITest. Keep this path in sync if the file moves.
      - path: PulseWidgets/WorkoutLiveActivityViews.swift
```
> The `excludes` on the main `Pulse` glob prevents the audio folder being added twice (once by the glob, once by the explicit resources entry). The fonts under `Resources/Fonts` keep working — they're declared as resources by extension via the glob and referenced in `INFOPLIST_KEY_UIAppFonts`; we are not changing them.
- [ ] Regenerate the project:
```
xcodegen generate
```
  Expected: "Created project at .../Pulse.xcodeproj" (no errors). NEVER hand-edit the `.xcodeproj`.
- [ ] Confirm the assets are in the app target's resources by building and checking the bundle:
```
xcodebuild build -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16'
```
  Expected: **BUILD SUCCEEDED**. Then locate the built app and confirm the files are bundled:
```
APP=$(xcodebuild -showBuildSettings -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{d=$2} / FULL_PRODUCT_NAME /{n=$2} END{print d"/"n}')
ls "$APP"/rest-warn.caf "$APP"/rest-end.caf
```
  Expected: both files listed. (If `BUILT_PRODUCTS_DIR` is stale, resolve it fresh per the sim-verification memory note.)
- [ ] Run the full `PulseTests` suite to confirm nothing regressed after project regeneration:
```
xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PulseTests
```
  Expected: **TEST SUCCEEDED**.
- [ ] Commit:
```
git add project.yml Pulse/Resources/Audio/rest-warn.caf Pulse/Resources/Audio/rest-end.caf Pulse.xcodeproj
git commit -m "feat(active): bundle rest-warn/rest-end audio assets via XcodeGen [BAK-33]"
```

---

## Task 10 — Wire the real service + `soundOnRestEnd` at the production call site

So the feature actually runs in the app (not just behind the no-op default). The model is built in `AppShell.init` (`AppShell.swift:12`). Inject `RestCueService()`. The `soundOnRestEnd` value should come from settings; v1 reads the persisted default. See Spec Gaps for the settings-sync limitation.

**Files:**
- Modify: `Pulse/App/AppShell.swift` (`init`, ~L12-15)

- [ ] In `AppShell.init`, pass the real cue service into the session model (the `soundOnRestEnd` default `true` matches `UserSettings.default.soundOnRestEnd`):
```swift
        let session = ActiveWorkoutModel(
            exerciseRepo: MockSwapAlternativesRepository(),
            historyRepo: MockHistoryRepository(),
            sessionWriter: MockSessionWriter(),
            restCue: RestCueService())
```
> `RestCueService` is `@MainActor`; `AppShell.init` runs on the main actor (SwiftUI `View.init`), so this is safe. The 5 preview call sites keep the `NoopRestCueService` default (no AVFoundation in previews).
- [ ] Build:
```
xcodebuild build -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16'
```
  Expected: **BUILD SUCCEEDED**.
- [ ] Commit:
```
git add Pulse/App/AppShell.swift
git commit -m "feat(active): inject real RestCueService at the app shell [BAK-33]"
```

---

## Task 11 — Self-review against the spec & full suite

- [ ] Run the complete unit suite one final time:
```
xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PulseTests
```
  Expected: **TEST SUCCEEDED**.
- [ ] Walk each Spec acceptance criterion and confirm a test covers it:
  - AC1 (one warn at ≤10s, one end at 0) → `testOneWarnAtTenSecondsAndOneEndAtZero`.
  - AC2 (sound off → zero calls, rest advances) → `testSoundOffSilencesCuesButRestStillAdvances`.
  - AC3 (+30s re-arms, warns again) → `testAdjustAboveThresholdReArmsWarn` (+ `testAdjustWithinWindowDoesNotReArm`).
  - AC4 (skip → no end, teardown called) → `testSkipRestPlaysNoEndButTearsDown`.
  - AC5 (stray tick after finish → no second end) → `testStrayTickAfterFinishDoesNotDoubleFire`.
- [ ] Confirm the manual-only ACs (6 Spotify, 7 silent switch) are in the checklist below and not faked as unit tests.
- [ ] No commit (review-only step).

---

## Manual verification checklist (device only)

Run on a **physical iPhone** (audio session + haptics + silent switch can't be exercised on the simulator). Build & run from Xcode to the device.

- [ ] **Background music keeps playing (Spec AC6):** Start Spotify (or Apple Music / a podcast) playing. Start a workout, log a set to enter rest. The music **keeps playing uninterrupted** through the whole rest. At T-10s you hear the soft warn tick *over* the music; at 0 you hear the double-chime *over* the music. Music does not pause, duck noticeably, or stop.
- [ ] **Warn fires once, ~10s before end:** Watch the on-screen timer — the warn tick coincides with the 10s mark and does not repeat as the timer counts down.
- [ ] **End fires once at 0:** The double-chime plays exactly once as the timer hits 0 and the screen advances to the next set.
- [ ] **+30s re-arms:** Let rest reach the warn window (hear the warn), tap **+30s**, let it count back down through 10s — you hear the warn **a second time**.
- [ ] **Skip is silent:** Mid-rest (remaining > 10s and again with remaining < 10s), tap **Skip rest →** / the forward chevron — **no** end chime plays; the screen advances.
- [ ] **Sound toggle off (Spec AC2):** You → toggle **Sound on rest end** off. (Note: in v1 this may require relaunching the workout for the model to pick up the flag — see Spec Gaps.) Run a rest: **no** warn or end audio; the timer still advances. Haptics: see note below.
- [ ] **Silent switch / muted (Spec AC7):** Flip the hardware silent switch on. Run a rest: with `.playback` the cues are **still audible** (this is the point — a gym phone is often on silent). The **haptics also fire** (light impact at T-10s, success at 0). Volume slider at 0 → no sound but haptics still fire.
- [ ] **Haptics present:** With volume up, confirm a light tap at T-10s and a success buzz at 0.
- [ ] **No leftover audio interruption:** After rest ends, background music continues normally; leaving and re-entering rest repeatedly does not progressively break audio (teardown → prepare cycles cleanly).

---

## Spec gaps found (surfaced during planning)

1. **`soundOnRestEnd` is not actually plumbed into the running session.** The setting lives in `YouModel` (`Pulse/Features/You/YouModel.swift`) and is persisted via `SettingsRepository`, but `ActiveWorkoutModel` is constructed in `AppShell.init` (`AppShell.swift:12`) with no access to loaded settings, and `YouModel`/`AppShell` don't share a settings source. This plan injects a settable `soundOnRestEnd` (default `true`, matching `UserSettings.default`) so the gating logic is testable and correct, but **toggling the You switch will not affect an already-constructed session** in v1. The spec's AC2 is satisfied at the model level (and manually by relaunching the flow), but full live-toggle wiring (load settings in `AppShell` / sync into the session on `startWorkout`) is **not specified**. Recommend a small follow-up: have `AppShell` (or the `RepositoryContainer`) load `UserSettings` and pass `soundOnRestEnd` into `startWorkout`, or re-read it when rest starts. Flagged, not built, to avoid scope creep.

2. **End-cue trigger relies on `remaining <= 0` inside `afterRest`.** The spec describes `afterRest()` calling `cue.end()` if `soundOnRestEnd`, but doesn't distinguish the auto-finish path (should chime) from the Skip path (should be silent) at the `afterRest` level — it only says "Skipping rest calls teardown() and plays no end cue." This plan resolves the ambiguity by computing `remaining <= 0` inside `afterRest(now:)`: natural finish chimes, Skip (remaining > 0) is silent. Worth confirming this matches intent; an alternative is two separate methods (`finishRest()` vs `skipRest()`), which is more explicit but adds API surface (YAGNI says keep one guarded method).

3. **Hardcoded "OF 1:30" label and `restTotal = 90`.** Already called out in the spec's Open Questions as a separate follow-up (ignores `UserSettings.defaultRestSeconds`). This plan does **not** touch it. Left as-is.

4. **Asset format/content unspecified.** The spec says "two short bundled `.caf`/`.m4a` assets" but not their exact sound design. This plan fixes on `.caf` (uncompressed, lowest-latency for short cues) and leaves the precise tones to the implementer, with audibility verified manually. No blocker.
