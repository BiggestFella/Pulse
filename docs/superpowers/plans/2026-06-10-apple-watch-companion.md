# Apple Watch Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a watchOS companion that mirrors the active workout session (current exercise, set X of N, target reps, weight seed, rest countdown) and lets the user log the set, skip a set, adjust/skip rest, and feel a wrist haptic at rest-end and T‑10s — while the phone's `ActiveWorkoutModel` stays the single source of session truth. v1 is active-session-only and **join-only** (the phone starts the workout; the watch joins).

**Architecture:** Phone broadcasts immutable session-state **snapshots** (current step, reps target, weight seed, `restEndsAt`, phase, flags needed to render) to the watch; the watch sends **commands** (`logSet`, `skipSet`, `skipRest`, `adjustRest(±)`, `nextSet`) back. The phone applies each command to `ActiveWorkoutModel` exactly as the in-app UI would, then re-broadcasts a fresh snapshot — the watch never mutates session truth locally. Transport is `WatchConnectivity` (`WCSession`) hidden behind a `WorkoutSyncChannel` protocol (`send(state:)`, `onCommand(handler:)`) so the pure logic is unit-testable with a `MockWorkoutSyncChannel`. The watch rest countdown is driven by the absolute `restEndsAt` (no drift) and schedules its own local haptics at `restEndsAt − 10s` and `restEndsAt` via `WKInterfaceDevice.play`, gated by `soundOnRestEnd`. This mirrors the existing Live Activity precedent: `WorkoutActivityAttributes.ContentState` is a Codable projection of the engine, and `WorkoutLiveActivityContent.make(from:)` is the pure builder — we add a sibling snapshot + builder for the watch.

**Tech Stack:** SwiftUI (iOS 17+ / watchOS), Swift Concurrency, MVVM + `@Observable`, WatchConnectivity, WidgetKit/ActivityKit (existing, unchanged). Project is generated from `project.yml` via **XcodeGen** — never hand-edit the `.xcodeproj`; edit `project.yml`, then run `xcodegen generate`. Unit tests live in `PulseTests` (iOS). The UI-test runner is broken on the current toolchain, so the CI gate is `-only-testing:PulseTests`. Live `WCSession` paired-device behaviour is covered by a manual checklist.

---

## Open questions to resolve first

These are flagged in the spec as open and **must be answered before Task 4** (the target-scaffolding task), because they change the YAML and the available APIs:

1. **watchOS minimum deployment target.** The spec lists this as open and it *drives API choices* (e.g. observation, navigation, `WKInterfaceDevice` availability). **Recommendation: `watchOS 10.0`** — it pairs cleanly with the iOS 17 baseline (`@Observable`, modern SwiftUI navigation) and covers Series 4 and later. This plan's YAML uses `watchOS: "10.0"`; change the single `deploymentTarget.watchOS` line if the human picks otherwise. Do not start Task 4 until this is confirmed.
2. **HealthKit workout session (rings/HR)?** Out of scope for v1 per the spec recommendation — follow-up spec. Do not add HealthKit entitlements or a `HKWorkoutSession`.
3. **Can the watch start the day's workout?** No — **join-only** for v1 per the spec recommendation. The watch shows a neutral "Open Pulse on your phone to start" idle state when no session is active; it never starts/finishes a workout.

---

## File Structure

### New shared file (compiled into BOTH the iOS app and the watch app)

- **`Pulse/Core/Workout/WorkoutSyncSnapshot.swift`** — the Codable session-state snapshot the phone sends to the watch (current step fields, target reps, weight seed, `restEndsAt`, `totalRest`, `phase`, `soundOnRestEnd`, `isActive`). Mirrors `WorkoutActivityAttributes.ContentState` but trimmed to what the watch renders + the haptic gate. Also defines `WorkoutCommand` (the watch→phone command enum, Codable) and the `WorkoutSyncChannel` protocol. Pure value types + a protocol — no UIKit/WatchKit/ActivityKit imports, so it compiles on both platforms.

### New iOS-app (phone-side) files

- **`Pulse/Core/Workout/WorkoutSyncSnapshotBuilder.swift`** — pure builder `WorkoutSyncSnapshotBuilder.make(from: ActiveWorkoutModel, soundOnRestEnd: Bool) -> WorkoutSyncSnapshot`. Sibling of `WorkoutLiveActivityContent`. No transport, fully testable against the real engine.
- **`Pulse/Core/Workout/WorkoutCommandApplier.swift`** — pure function that applies a `WorkoutCommand` to an `ActiveWorkoutModel` (mapping each command to the same mutation the in-app UI triggers; wrong-phase commands are ignored). `@MainActor`. Fully unit-tested.
- **`Pulse/Core/Workout/WCSessionWorkoutSyncChannel.swift`** — the real phone-side `WorkoutSyncChannel` backed by `WCSession`: `send(state:)` → `updateApplicationContext` (latest-state, survives unreachability) and `onCommand` ← `didReceiveMessage`. `WCSessionDelegate`.
- **`Pulse/Features/ActiveWorkout/WatchSyncBridge.swift`** — `@MainActor` glue object (sibling of `WorkoutLiveActivityController`): owns a `WorkoutSyncChannel`, pushes a fresh snapshot on every engine transition via `sync()`, and routes inbound commands through `WorkoutCommandApplier` then re-broadcasts. Reads `soundOnRestEnd` from settings.

### Phone-side wiring (modified)

- **`Pulse/Features/ActiveWorkout/ActiveWorkoutFlowView.swift`** — instantiate `WatchSyncBridge` alongside the existing `WorkoutLiveActivityController` and call `bridge.sync()` at the same points the Live Activity is synced. (Modified, build-verified.)

### New watchOS-app files (new target `PulseWatch`)

- **`PulseWatch/PulseWatchApp.swift`** — `@main` watchOS `App` entry; hosts `WatchRootView`.
- **`PulseWatch/WatchSessionModel.swift`** — `@Observable` watch-side model. Holds the latest `WorkoutSyncSnapshot`, exposes derived display state, sends `WorkoutCommand`s through its `WorkoutSyncChannel`, and schedules/cancels local haptics from `restEndsAt`. Never mutates session truth.
- **`PulseWatch/WCSessionWatchSyncChannel.swift`** — the real watch-side `WorkoutSyncChannel`: receives snapshots via `didReceiveApplicationContext`, sends commands via `sendMessage` (with a dropped-when-unreachable guard).
- **`PulseWatch/WatchRootView.swift`** — routes on snapshot phase: idle (no session) → `WatchIdleView`; `.active` → `WatchSetView`; `.rest` → `WatchRestView`; `.summary`/none → idle.
- **`PulseWatch/WatchSetView.swift`** — exercise name, set X of N, target reps, weight, "Log set", "Skip set".
- **`PulseWatch/WatchRestView.swift`** — countdown ring driven by `restEndsAt`, `−15 / +15 / +30`, "Skip", with the local-haptic scheduling.
- **`PulseWatch/WatchHaptics.swift`** — thin protocol `WatchHapticsPlaying` + real `WKInterfaceDevice` impl, so the scheduler can be reasoned about without a device.
- **`PulseWatch/Info.plist`** — watch app Info.plist (`WKApplication`, `WKCompanionAppBundleIdentifier`).

### New test file (iOS `PulseTests`)

- **`PulseTests/ActiveWorkout/WorkoutSyncTests.swift`** — codec round-trip for `WorkoutSyncSnapshot` + `WorkoutCommand`, the snapshot builder against the real engine, the command applier (each command == in-app mutation; wrong-phase ignored), and the bridge end-to-end with `MockWorkoutSyncChannel`.

### Modified project file

- **`project.yml`** — add `PulseWatch` watchOS application target, add the shared file to the watch sources + `PulseTests`, embed the watch app in the `Pulse` iOS app, and add it to the build scheme.

---

## Task 1 — Shared snapshot + command + channel protocol (codec test)

Extract the Codable types the phone and watch share. This is pure value types, so it is fully TDD-able. We write the round-trip test first.

**Files:**
- `PulseTests/ActiveWorkout/WorkoutSyncTests.swift` (new)
- `Pulse/Core/Workout/WorkoutSyncSnapshot.swift` (new)
- `project.yml` (add shared file to `PulseTests` sources is NOT needed — `PulseTests` depends on `Pulse`, which already globs `Pulse/`; the file is reachable via `@testable import Pulse`)

Steps:

- [ ] Write the failing codec test. Create `PulseTests/ActiveWorkout/WorkoutSyncTests.swift`:

```swift
import XCTest
@testable import Pulse

final class WorkoutSyncTests: XCTestCase {

    // AC3: snapshot encodes the fields the watch needs and round-trips.
    func testSnapshotCodableRoundTrip() throws {
        let end = Date(timeIntervalSince1970: 1_700_000_000)
        let original = WorkoutSyncSnapshot(
            isActive: true,
            phase: .rest,
            exerciseName: "Bench Press",
            ssLabel: "1A",
            setIndex: 2,
            totalSets: 4,
            setTypeLabel: "WORKING",
            targetReps: 8,
            targetWeight: 60,
            isFailure: false,
            nextExerciseName: "Incline DB",
            nextReps: 10,
            restEndsAt: end,
            totalRest: 90,
            soundOnRestEnd: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutSyncSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // AC3: nil weight / nil reps (failure / bodyweight) round-trip.
    func testSnapshotNilFieldsRoundTrip() throws {
        let original = WorkoutSyncSnapshot(
            isActive: true, phase: .active, exerciseName: "Pushups",
            ssLabel: nil, setIndex: 1, totalSets: 3, setTypeLabel: "TO FAILURE",
            targetReps: nil, targetWeight: nil, isFailure: true,
            nextExerciseName: nil, nextReps: nil,
            restEndsAt: nil, totalRest: 0, soundOnRestEnd: false)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutSyncSnapshot.self, from: data), original)
    }

    // AC3: idle (no session) snapshot round-trips.
    func testIdleSnapshotRoundTrip() throws {
        let data = try JSONEncoder().encode(WorkoutSyncSnapshot.idle)
        XCTAssertEqual(try JSONDecoder().decode(WorkoutSyncSnapshot.self, from: data),
                       WorkoutSyncSnapshot.idle)
    }

    // Command codec round-trips for every case (sendMessage uses a dictionary,
    // so the codec is the safety net for the payload).
    func testCommandCodableRoundTrip() throws {
        let commands: [WorkoutCommand] = [
            .logSet, .skipSet, .skipRest, .nextSet, .adjustRest(delta: 15), .adjustRest(delta: -15)
        ]
        for c in commands {
            let data = try JSONEncoder().encode(c)
            XCTAssertEqual(try JSONDecoder().decode(WorkoutCommand.self, from: data), c)
        }
    }
}
```

- [ ] Run it and confirm it FAILS to compile (types don't exist yet):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/WorkoutSyncTests 2>&1 | tail -30`
  Expected: compile failure — `cannot find 'WorkoutSyncSnapshot' in scope`.

- [ ] Create `Pulse/Core/Workout/WorkoutSyncSnapshot.swift` with the minimal types to pass:

```swift
import Foundation

/// Phone → watch session-state snapshot. A trimmed projection of the engine —
/// only the fields the watch renders plus the `soundOnRestEnd` haptic gate.
/// Pure value type with no UIKit/WatchKit imports so it compiles on both
/// iOS and watchOS. Sibling of `WorkoutActivityAttributes.ContentState`.
struct WorkoutSyncSnapshot: Codable, Hashable {
    enum Phase: String, Codable { case idle, active, rest, summary }

    var isActive: Bool
    var phase: Phase
    var exerciseName: String        // resolves session swaps
    var ssLabel: String?            // "1A"/"1B" for supersets
    var setIndex: Int               // 1-based
    var totalSets: Int
    var setTypeLabel: String        // WORKING / WARMUP / DROPSET / TO FAILURE / AMRAP
    var targetReps: Int?            // nil → render ∞ for failure
    var targetWeight: Double?       // nil/0 → bodyweight / failure (no weight)
    var isFailure: Bool
    var nextExerciseName: String?   // UP NEXT preview on the rest screen
    var nextReps: Int?
    var restEndsAt: Date?           // absolute end; nil when not resting
    var totalRest: TimeInterval     // ring fraction base; 0 when not resting
    var soundOnRestEnd: Bool        // gates the wrist haptics

    /// Shown when no session is running (join-only: phone hasn't started one).
    static let idle = WorkoutSyncSnapshot(
        isActive: false, phase: .idle, exerciseName: "", ssLabel: nil,
        setIndex: 0, totalSets: 0, setTypeLabel: "", targetReps: nil,
        targetWeight: nil, isFailure: false, nextExerciseName: nil, nextReps: nil,
        restEndsAt: nil, totalRest: 0, soundOnRestEnd: true)

    /// remaining / totalRest, clamped to 0...1. Drives the watch rest ring.
    func restFraction(now: Date = Date()) -> Double {
        guard let end = restEndsAt, totalRest > 0 else { return 0 }
        return min(max(end.timeIntervalSince(now) / totalRest, 0), 1)
    }

    /// Seconds remaining on rest from `now`, clamped at 0.
    func remainingRest(now: Date = Date()) -> TimeInterval {
        guard let end = restEndsAt else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }
}

/// Watch → phone command. The phone applies it to `ActiveWorkoutModel` then
/// re-broadcasts; the watch never mutates session truth locally.
enum WorkoutCommand: Codable, Hashable {
    case logSet          // log current set with the phone's seeded reps × weight
    case skipSet         // advance without logging
    case skipRest        // end rest early (== afterRest)
    case nextSet         // explicit advance (alias used by the set screen)
    case adjustRest(delta: TimeInterval)
}

/// Transport seam. The phone sends snapshots and receives commands; the watch
/// receives snapshots and sends commands. Two conforming impls (`WCSession`)
/// plus a `MockWorkoutSyncChannel` for tests.
protocol WorkoutSyncChannel: AnyObject {
    /// Phone: broadcast latest state. Watch: no-op (or send last command echo).
    func send(state: WorkoutSyncSnapshot)
    /// Phone: send a command (used by the watch impl). Phone impl is a no-op.
    func send(command: WorkoutCommand)
    /// Register a handler for inbound snapshots (watch side).
    func onState(_ handler: @escaping (WorkoutSyncSnapshot) -> Void)
    /// Register a handler for inbound commands (phone side).
    func onCommand(_ handler: @escaping (WorkoutCommand) -> Void)
}
```

- [ ] Re-run the test; expected PASS:
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/WorkoutSyncTests 2>&1 | tail -20`

- [ ] Commit:
  `git add Pulse/Core/Workout/WorkoutSyncSnapshot.swift PulseTests/ActiveWorkout/WorkoutSyncTests.swift`
  `git commit -m "feat(watch): shared session snapshot + command + channel protocol [BAK-37]"`

---

## Task 2 — `MockWorkoutSyncChannel` + snapshot builder (TDD against the real engine)

Add the test double and the pure builder that projects the engine onto a snapshot. Sibling of `WorkoutLiveActivityContent.make`.

**Files:**
- `PulseTests/ActiveWorkout/WorkoutSyncTests.swift` (append)
- `Pulse/Core/Workout/WorkoutSyncSnapshotBuilder.swift` (new)

Steps:

- [ ] Append the failing builder test + the mock channel to `WorkoutSyncTests.swift`:

```swift
extension WorkoutSyncTests {

    private func started() -> ActiveWorkoutModel {
        let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                                   historyRepo: MockHistoryRepository(),
                                   sessionWriter: MockSessionWriter())
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
        return m
    }

    // AC3: builder pulls the engine's current step, seeds, phase, restEndsAt.
    func testBuilderProjectsActiveStep() {
        let m = started()                                   // step 0 = bench warmup
        let snap = WorkoutSyncSnapshotBuilder.make(from: m, soundOnRestEnd: true)
        XCTAssertTrue(snap.isActive)
        XCTAssertEqual(snap.phase, .active)
        XCTAssertEqual(snap.exerciseName, m.displayName(forExercise: m.currentStep.exIdx))
        XCTAssertEqual(snap.setIndex, m.currentStep.setIdx + 1)
        XCTAssertEqual(snap.targetReps, m.seedReps)
        XCTAssertEqual(snap.targetWeight, m.seedWeight)
        XCTAssertNil(snap.restEndsAt)
        XCTAssertTrue(snap.soundOnRestEnd)
    }

    // AC3: rest snapshot carries the absolute restEndsAt + totalRest for the ring.
    func testBuilderProjectsRest() {
        let m = started()
        let t0 = Date(timeIntervalSince1970: 5_000_000)
        m.logSet(reps: 15, weight: 40, now: t0)             // → rest
        let snap = WorkoutSyncSnapshotBuilder.make(from: m, soundOnRestEnd: false)
        XCTAssertEqual(snap.phase, .rest)
        XCTAssertEqual(snap.restEndsAt, t0.addingTimeInterval(m.restTotal))
        XCTAssertEqual(snap.totalRest, m.restTotal)
        XCTAssertFalse(snap.soundOnRestEnd)
    }

    // AC3: a not-started model projects the idle snapshot (join-only).
    func testBuilderIdleWhenInactive() {
        let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                                   historyRepo: MockHistoryRepository(),
                                   sessionWriter: MockSessionWriter())
        let snap = WorkoutSyncSnapshotBuilder.make(from: m, soundOnRestEnd: true)
        XCTAssertFalse(snap.isActive)
        XCTAssertEqual(snap.phase, .idle)
    }
}

/// In-memory channel for unit tests. Records what was sent and lets a test
/// drive the inbound handlers directly (simulating the paired device).
final class MockWorkoutSyncChannel: WorkoutSyncChannel {
    private(set) var sentStates: [WorkoutSyncSnapshot] = []
    private(set) var sentCommands: [WorkoutCommand] = []
    private var stateHandler: ((WorkoutSyncSnapshot) -> Void)?
    private var commandHandler: ((WorkoutCommand) -> Void)?

    func send(state: WorkoutSyncSnapshot) { sentStates.append(state) }
    func send(command: WorkoutCommand) { sentCommands.append(command) }
    func onState(_ handler: @escaping (WorkoutSyncSnapshot) -> Void) { stateHandler = handler }
    func onCommand(_ handler: @escaping (WorkoutCommand) -> Void) { commandHandler = handler }

    /// Simulate the watch receiving a snapshot.
    func deliver(state: WorkoutSyncSnapshot) { stateHandler?(state) }
    /// Simulate the phone receiving a command.
    func deliver(command: WorkoutCommand) { commandHandler?(command) }
}
```

- [ ] Run; expected FAIL (`cannot find 'WorkoutSyncSnapshotBuilder'`):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/WorkoutSyncTests 2>&1 | tail -30`

- [ ] Create `Pulse/Core/Workout/WorkoutSyncSnapshotBuilder.swift`:

```swift
import Foundation

/// Pure projection: maps the live `ActiveWorkoutModel` onto a
/// `WorkoutSyncSnapshot`. No transport, no WatchKit — fully testable against
/// the real engine. Sibling of `WorkoutLiveActivityContent`.
enum WorkoutSyncSnapshotBuilder {
    @MainActor
    static func make(from model: ActiveWorkoutModel,
                     soundOnRestEnd: Bool) -> WorkoutSyncSnapshot {
        // Join-only: nothing to mirror until the phone starts & begins sets.
        guard model.isActive, !model.steps.isEmpty, model.phase != .pre else {
            var idle = WorkoutSyncSnapshot.idle
            idle.soundOnRestEnd = soundOnRestEnd
            return idle
        }

        let step = model.currentStep
        let ex = model.workout.exercises[step.exIdx]
        let spec = ex.sets.indices.contains(step.setIdx) ? ex.sets[step.setIdx] : nil
        let isRest = model.phase == .rest
        let isFailure = spec?.type == .failure
        let next = model.nextStep

        return WorkoutSyncSnapshot(
            isActive: true,
            phase: model.phase == .summary ? .summary : (isRest ? .rest : .active),
            exerciseName: model.displayName(forExercise: step.exIdx),
            ssLabel: step.ssLabel(in: model.workout),
            setIndex: step.setIdx + 1,
            totalSets: ex.sets.count,
            setTypeLabel: spec.map { SetTypeLabel.text(for: $0.type) } ?? "",
            targetReps: isFailure ? nil : model.seedReps,
            targetWeight: isFailure ? nil : model.seedWeight,
            isFailure: isFailure,
            nextExerciseName: next.map { model.displayName(forExercise: $0.exIdx) },
            nextReps: next.flatMap { n in
                let nx = model.workout.exercises[n.exIdx].sets
                guard nx.indices.contains(n.setIdx), nx[n.setIdx].type != .failure
                else { return nil }
                return nx[n.setIdx].reps
            },
            restEndsAt: isRest ? model.restEndsAt : nil,
            totalRest: isRest ? model.restTotal : 0,
            soundOnRestEnd: soundOnRestEnd)
    }
}
```

- [ ] Run; expected PASS:
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/WorkoutSyncTests 2>&1 | tail -20`

- [ ] Commit:
  `git add Pulse/Core/Workout/WorkoutSyncSnapshotBuilder.swift PulseTests/ActiveWorkout/WorkoutSyncTests.swift`
  `git commit -m "feat(watch): snapshot builder + mock sync channel [BAK-37]"`

---

## Task 3 — Phone-side command applier + bridge (TDD: commands == in-app mutations; wrong-phase ignored)

This is the heart of the acceptance criteria (AC1, AC2, AC4). Each command must mutate `ActiveWorkoutModel` exactly as the in-app UI does, and wrong-phase commands must be no-ops.

**Files:**
- `PulseTests/ActiveWorkout/WorkoutSyncTests.swift` (append)
- `Pulse/Core/Workout/WorkoutCommandApplier.swift` (new)
- `Pulse/Features/ActiveWorkout/WatchSyncBridge.swift` (new)

Steps:

- [ ] Append the failing applier + bridge tests:

```swift
@MainActor
final class WorkoutCommandApplierTests: XCTestCase {

    private func started() -> ActiveWorkoutModel {
        let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                                   historyRepo: MockHistoryRepository(),
                                   sessionWriter: MockSessionWriter())
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
        return m
    }

    // AC1: logSet command advances the model exactly as an in-app log would.
    func testLogSetCommandMatchesInAppLog() {
        let actual = started()
        WorkoutCommandApplier.apply(.logSet, to: actual)        // step 0 → rest

        let expected = started()
        expected.logSet(reps: expected.seedReps, weight: expected.seedWeight)

        XCTAssertEqual(actual.phase, expected.phase)
        XCTAssertEqual(actual.stepIdx, expected.stepIdx)
        XCTAssertEqual(actual.doneSteps, expected.doneSteps)
    }

    // AC2: adjustRest command changes restEndsAt identically to model.adjustRest.
    func testAdjustRestCommandMatchesModel() {
        let m = started()
        let t0 = Date(timeIntervalSince1970: 6_000_000)
        m.logSet(reps: 15, weight: 40, now: t0)                 // → rest, ends t0+90
        WorkoutCommandApplier.apply(.adjustRest(delta: 30), to: m, now: t0)
        XCTAssertEqual(m.restEndsAt, t0.addingTimeInterval(120))
    }

    // AC2: skipRest command ends rest like afterRest (advance + clear restEndsAt).
    func testSkipRestCommandMatchesAfterRest() {
        let m = started()
        m.logSet(reps: 15, weight: 40)                          // → rest at step 0
        WorkoutCommandApplier.apply(.skipRest, to: m)
        XCTAssertEqual(m.phase, .active)
        XCTAssertEqual(m.stepIdx, 1)
        XCTAssertNil(m.restEndsAt)
    }

    // AC2: skipSet command advances without logging.
    func testSkipSetCommandAdvancesWithoutLogging() {
        let m = started()
        WorkoutCommandApplier.apply(.skipSet, to: m)
        XCTAssertEqual(m.stepIdx, 1)
        XCTAssertTrue(m.doneSteps.isEmpty)
    }

    // AC4: logSet received during rest is ignored (wrong phase).
    func testLogSetIgnoredDuringRest() {
        let m = started()
        m.logSet(reps: 15, weight: 40)                          // → rest
        let stepBefore = m.stepIdx
        WorkoutCommandApplier.apply(.logSet, to: m)             // ignored
        XCTAssertEqual(m.phase, .rest)
        XCTAssertEqual(m.stepIdx, stepBefore)
    }

    // AC4: skipRest received while active is ignored (wrong phase).
    func testSkipRestIgnoredWhenActive() {
        let m = started()
        WorkoutCommandApplier.apply(.skipRest, to: m)
        XCTAssertEqual(m.phase, .active)
        XCTAssertEqual(m.stepIdx, 0)
    }

    // AC4: adjustRest while active is ignored (no restEndsAt to adjust).
    func testAdjustRestIgnoredWhenActive() {
        let m = started()
        WorkoutCommandApplier.apply(.adjustRest(delta: 15), to: m)
        XCTAssertNil(m.restEndsAt)
    }
}

@MainActor
final class WatchSyncBridgeTests: XCTestCase {

    private func started() -> ActiveWorkoutModel {
        let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                                   historyRepo: MockHistoryRepository(),
                                   sessionWriter: MockSessionWriter())
        m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
        return m
    }

    // AC5 (logic half): sync() broadcasts the current snapshot.
    func testSyncBroadcastsSnapshot() {
        let m = started()
        let ch = MockWorkoutSyncChannel()
        let bridge = WatchSyncBridge(model: m, channel: ch, soundOnRestEnd: { true })
        bridge.sync()
        XCTAssertEqual(ch.sentStates.last?.phase, .active)
        XCTAssertEqual(ch.sentStates.last?.targetReps, m.seedReps)
    }

    // AC1 + re-broadcast: an inbound command is applied then a fresh snapshot is pushed.
    func testInboundCommandAppliesThenRebroadcasts() {
        let m = started()
        let ch = MockWorkoutSyncChannel()
        let bridge = WatchSyncBridge(model: m, channel: ch, soundOnRestEnd: { true })
        bridge.sync()
        let statesBefore = ch.sentStates.count

        ch.deliver(command: .logSet)                            // simulate watch tap

        XCTAssertEqual(m.doneSteps, [0])                        // applied
        XCTAssertGreaterThan(ch.sentStates.count, statesBefore) // re-broadcast
        XCTAssertEqual(ch.sentStates.last?.phase, .rest)        // newest reflects rest
    }

    // soundOnRestEnd gate flows into the broadcast snapshot.
    func testSoundGateFlowsIntoSnapshot() {
        let m = started()
        let ch = MockWorkoutSyncChannel()
        let bridge = WatchSyncBridge(model: m, channel: ch, soundOnRestEnd: { false })
        bridge.sync()
        XCTAssertEqual(ch.sentStates.last?.soundOnRestEnd, false)
    }
}
```

- [ ] Run; expected FAIL (types missing):
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/WorkoutCommandApplierTests -only-testing:PulseTests/WatchSyncBridgeTests 2>&1 | tail -30`

- [ ] Create `Pulse/Core/Workout/WorkoutCommandApplier.swift`:

```swift
import Foundation

/// Applies a watch-originated `WorkoutCommand` to the phone's `ActiveWorkoutModel`,
/// mapping each command to the same mutation the in-app UI triggers. Commands
/// received in the wrong phase are ignored (the watch reflects truth on the next
/// snapshot). Pure side-effecting function — no transport.
enum WorkoutCommandApplier {
    @MainActor
    static func apply(_ command: WorkoutCommand,
                      to model: ActiveWorkoutModel,
                      now: Date = .now) {
        switch command {
        case .logSet:
            // In-app: "Log set" logs the current step with the seeded reps × weight.
            // Only valid while actively on a set.
            guard model.phase == .active else { return }
            model.logSet(reps: model.seedReps, weight: model.seedWeight, now: now)

        case .skipSet, .nextSet:
            // In-app: "Skip set" advances without logging. Only while active.
            guard model.phase == .active else { return }
            model.skipSet()

        case .skipRest:
            // In-app: "Skip rest" == afterRest. afterRest already guards phase == .rest.
            model.afterRest()

        case .adjustRest(let delta):
            // In-app: ±15/+30 chips. adjustRest already guards restEndsAt != nil,
            // so it is a no-op outside rest.
            guard model.phase == .rest else { return }
            model.adjustRest(delta, now: now)
        }
    }
}
```

- [ ] Create `Pulse/Features/ActiveWorkout/WatchSyncBridge.swift`:

```swift
import Foundation

/// Phone-side glue between the session engine and the watch. Sibling of
/// `WorkoutLiveActivityController`: it is a projection that pushes snapshots on
/// every engine transition and routes inbound commands back through the engine —
/// it never holds canonical session state. Not `@Observable`: it surfaces no
/// state to views; the flow view owns it and drives `sync()`.
@MainActor
final class WatchSyncBridge {
    private let model: ActiveWorkoutModel
    private let channel: WorkoutSyncChannel
    private let soundOnRestEnd: () -> Bool

    /// Designated init — tests inject a `MockWorkoutSyncChannel` and a sound gate.
    init(model: ActiveWorkoutModel,
         channel: WorkoutSyncChannel,
         soundOnRestEnd: @escaping () -> Bool) {
        self.model = model
        self.channel = channel
        self.soundOnRestEnd = soundOnRestEnd
        channel.onCommand { [weak self] command in
            guard let self else { return }
            WorkoutCommandApplier.apply(command, to: self.model)
            self.sync()                      // re-broadcast the new truth
        }
    }

    /// Call after every engine transition (same call sites as the Live Activity
    /// controller's `sync()`). Broadcasts a fresh snapshot to the watch.
    func sync() {
        channel.send(state: WorkoutSyncSnapshotBuilder.make(
            from: model, soundOnRestEnd: soundOnRestEnd()))
    }
}
```

- [ ] Run; expected PASS:
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests/WorkoutCommandApplierTests -only-testing:PulseTests/WatchSyncBridgeTests 2>&1 | tail -20`

- [ ] Commit:
  `git add Pulse/Core/Workout/WorkoutCommandApplier.swift Pulse/Features/ActiveWorkout/WatchSyncBridge.swift PulseTests/ActiveWorkout/WorkoutSyncTests.swift`
  `git commit -m "feat(watch): command applier + phone sync bridge [BAK-37]"`

---

## Task 4 — Add the watchOS target to `project.yml` (scaffolding — build-verified, not unit-tested)

> **Scaffolding task — cannot be TDD'd.** XcodeGen target wiring has no unit test; the verification is a clean `xcodegen generate` + a watchOS build. **Do not start until Open Question 1 (watchOS min target) is confirmed.** This task only adds the target, its Info.plist, and a placeholder `@main` so the target compiles; the real views land in Tasks 5–7.

**Files:**
- `project.yml` (modified)
- `PulseWatch/Info.plist` (new)
- `PulseWatch/PulseWatchApp.swift` (new placeholder)

Steps:

- [ ] Add the watch target + sources + embed + scheme to `project.yml`. Apply these edits:

  Add to the `options.deploymentTarget` map:

```yaml
options:
  bundleIdPrefix: au.com.codeheroes.pulse
  deploymentTarget:
    iOS: "17.0"
    watchOS: "10.0"   # confirm via Open Question 1 before generating
```

  Add the new target under `targets:` (after `PulseWidgets`):

```yaml
  PulseWatch:
    type: application
    platform: watchOS
    sources:
      - path: PulseWatch
      # Shared, platform-agnostic session types compiled into the watch app
      # (no WatchConnectivity/WatchKit in these files).
      - path: Pulse/Core/Workout/WorkoutSyncSnapshot.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: au.com.codeheroes.pulse.watchkitapp
        INFOPLIST_FILE: PulseWatch/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        # Single-target watchOS app (watchOS 7+): no separate extension target.
        WATCHOS_DEPLOYMENT_TARGET: "10.0"
```

  Add the watch app as an embedded dependency of the iOS app so it ships in the
  same archive. Under `targets.Pulse.dependencies`, append:

```yaml
    dependencies:
      - target: PulseWidgets
        embed: true
      - target: PulseWatch
        embed: true
```

  Add the watch app to the build scheme. Under `schemes.Pulse.build.targets`:

```yaml
schemes:
  Pulse:
    build:
      targets:
        Pulse: all
        PulseWatch: all
    test:
      targets: [PulseTests, PulseUITests]
```

- [ ] Create `PulseWatch/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Pulse</string>
    <key>CFBundleName</key>
    <string>Pulse</string>
    <key>WKApplication</key>
    <true/>
    <key>WKCompanionAppBundleIdentifier</key>
    <string>au.com.codeheroes.pulse</string>
    <key>UISupportedInterfaceOrientations</key>
    <array>
        <string>UIInterfaceOrientationPortrait</string>
        <string>UIInterfaceOrientationPortraitUpsideDown</string>
    </array>
</dict>
</plist>
```

- [ ] Create the placeholder `PulseWatch/PulseWatchApp.swift` so the target compiles:

```swift
import SwiftUI

@main
struct PulseWatchApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Pulse")   // replaced by WatchRootView in Task 5
        }
    }
}
```

- [ ] Regenerate and build the watch target (verification, not a test):
  `xcodegen generate`
  `xcodebuild build -scheme Pulse -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' 2>&1 | tail -20`
  Expected: `** BUILD SUCCEEDED **`. (If the named simulator is absent, run `xcrun simctl list devicetypes | grep Watch` and substitute an available one.)

- [ ] Confirm the iOS app + tests still build/pass after the project change:
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests 2>&1 | tail -20`

- [ ] Commit:
  `git add project.yml PulseWatch/Info.plist PulseWatch/PulseWatchApp.swift`
  `git commit -m "chore(watch): add watchOS app target via XcodeGen [BAK-37]"`

---

## Task 5 — Watch session model + set screen (build-verified)

> **UI task — build-verified.** SwiftUI views and the `@Observable` watch model render only with a paired/sim device; the pure projection logic is already covered by Tasks 1–3. Verify via watchOS build; behaviour goes on the manual checklist.

**Files:**
- `PulseWatch/WatchSessionModel.swift` (new)
- `PulseWatch/WatchRootView.swift` (new)
- `PulseWatch/WatchSetView.swift` (new)
- `PulseWatch/WatchHaptics.swift` (new — protocol + real impl; scheduling lands in Task 6)
- `PulseWatch/PulseWatchApp.swift` (replace placeholder)

Steps:

- [ ] Create `PulseWatch/WatchHaptics.swift`:

```swift
import Foundation
import WatchKit

/// Seam over `WKInterfaceDevice.play` so haptic intent is expressible without a
/// physical device. Two cues, matching the Rest Timer Audio semantics: a lighter
/// warning at T-10s and a success notification at rest end.
protocol WatchHapticsPlaying {
    func playWarning()   // T-10s
    func playRestEnd()   // 0
}

struct WatchHaptics: WatchHapticsPlaying {
    func playWarning() { WKInterfaceDevice.current().play(.directionUp) }
    func playRestEnd() { WKInterfaceDevice.current().play(.success) }
}
```

- [ ] Create `PulseWatch/WatchSessionModel.swift`:

```swift
import Foundation
import Observation

/// Watch-side `@Observable` model. Holds the latest phone snapshot, exposes
/// derived display state, and sends commands. It NEVER mutates session truth —
/// it asks the phone, and reflects whatever snapshot comes back. Haptic
/// scheduling from `restEndsAt` is wired in Task 6.
@MainActor
@Observable
final class WatchSessionModel {
    private(set) var snapshot: WorkoutSyncSnapshot = .idle
    private let channel: WorkoutSyncChannel
    private let haptics: WatchHapticsPlaying

    init(channel: WorkoutSyncChannel, haptics: WatchHapticsPlaying = WatchHaptics()) {
        self.channel = channel
        self.haptics = haptics
        channel.onState { [weak self] state in
            Task { @MainActor in self?.receive(state) }
        }
    }

    /// Apply an inbound snapshot. Task 6 overrides/extends this to (re)schedule
    /// rest haptics; here it just stores the latest truth (last-write-wins).
    func receive(_ state: WorkoutSyncSnapshot) {
        snapshot = state
    }

    // MARK: - commands (fire-and-forget; phone re-broadcasts the result)
    func logSet()           { channel.send(command: .logSet) }
    func skipSet()          { channel.send(command: .skipSet) }
    func skipRest()         { channel.send(command: .skipRest) }
    func adjustRest(_ d: TimeInterval) { channel.send(command: .adjustRest(delta: d)) }

    // MARK: - derived display
    var weightLabel: String {
        guard let w = snapshot.targetWeight, w > 0 else { return "BW" }
        return "\(Int(w)) kg"
    }
    var repsLabel: String {
        snapshot.isFailure ? "∞" : "\(snapshot.targetReps ?? 0)"
    }
}
```

- [ ] Create `PulseWatch/WatchSetView.swift`:

```swift
import SwiftUI

struct WatchSetView: View {
    let model: WatchSessionModel

    var body: some View {
        let s = model.snapshot
        VStack(alignment: .leading, spacing: 6) {
            if let ss = s.ssLabel {
                Text(ss).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(s.exerciseName).font(.headline).lineLimit(2)
            Text("SET \(s.setIndex) OF \(s.totalSets)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(model.repsLabel).font(.system(size: 34, weight: .bold))
                Text("reps").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(model.weightLabel).font(.title3.bold())
            }
            .padding(.vertical, 2)
            Button("Log set") { model.logSet() }
                .buttonStyle(.borderedProminent)
            Button("Skip set") { model.skipSet() }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 4)
    }
}
```

- [ ] Create `PulseWatch/WatchRootView.swift` (rest view added in Task 6 — route to a placeholder for now):

```swift
import SwiftUI

struct WatchRootView: View {
    let model: WatchSessionModel

    var body: some View {
        switch model.snapshot.phase {
        case .active:
            WatchSetView(model: model)
        case .rest:
            // Replaced by WatchRestView in Task 6.
            Text("Resting…")
        case .idle, .summary:
            WatchIdleView()
        }
    }
}

struct WatchIdleView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone").font(.title2).foregroundStyle(.secondary)
            Text("Open Pulse on your phone to start a workout")
                .font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding()
    }
}
```

- [ ] Replace `PulseWatch/PulseWatchApp.swift` to build the model with the real channel (added in Task 7) — until then, wire a temporary idle channel so it builds:

```swift
import SwiftUI

@main
struct PulseWatchApp: App {
    // The real WCSession channel is injected in Task 7; until then this idle
    // channel keeps the target buildable and shows the idle screen.
    @State private var model = WatchSessionModel(channel: IdleSyncChannel())

    var body: some Scene {
        WindowGroup { WatchRootView(model: model) }
    }
}

/// Placeholder channel — replaced by WCSessionWatchSyncChannel in Task 7.
private final class IdleSyncChannel: WorkoutSyncChannel {
    func send(state: WorkoutSyncSnapshot) {}
    func send(command: WorkoutCommand) {}
    func onState(_ handler: @escaping (WorkoutSyncSnapshot) -> Void) {}
    func onCommand(_ handler: @escaping (WorkoutCommand) -> Void) {}
}
```

- [ ] Add the new watch sources to `project.yml`? No edit needed — `PulseWatch` globs `path: PulseWatch`, so new files are picked up. Regenerate and build:
  `xcodegen generate`
  `xcodebuild build -scheme Pulse -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' 2>&1 | tail -20`
  Expected: `** BUILD SUCCEEDED **`.

- [ ] Commit:
  `git add PulseWatch project.yml`
  `git commit -m "feat(watch): session model + set screen [BAK-37]"`

---

## Task 6 — Watch rest screen + local haptics from `restEndsAt` (build-verified)

> **UI + timing task — build-verified.** The ring + chips are SwiftUI; the haptic scheduling is local to the watch (no phone round-trip), driven by the absolute `restEndsAt` so there is no drift. Verify via build; the haptic fire goes on the manual checklist (AC6).

**Files:**
- `PulseWatch/WatchRestView.swift` (new)
- `PulseWatch/WatchSessionModel.swift` (extend `receive` to schedule haptics)
- `PulseWatch/WatchRootView.swift` (route `.rest` to `WatchRestView`)

Steps:

- [ ] Extend `WatchSessionModel` to schedule local haptics whenever a `.rest` snapshot arrives. Replace the `receive(_:)` method and add the scheduler:

```swift
    private var warningTask: Task<Void, Never>?
    private var endTask: Task<Void, Never>?

    /// Apply an inbound snapshot (last-write-wins) and (re)schedule rest haptics
    /// from the absolute `restEndsAt`. Reconciles to the phone on every push, so
    /// an out-of-range reconnect just re-schedules from fresh truth.
    func receive(_ state: WorkoutSyncSnapshot) {
        snapshot = state
        scheduleRestHaptics(for: state)
    }

    private func scheduleRestHaptics(for state: WorkoutSyncSnapshot) {
        warningTask?.cancel(); endTask?.cancel()
        warningTask = nil; endTask = nil

        guard state.phase == .rest, state.soundOnRestEnd,
              let end = state.restEndsAt else { return }

        let now = Date()
        let toEnd = end.timeIntervalSince(now)
        let toWarning = toEnd - 10

        if toWarning > 0 {
            warningTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(toWarning * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.haptics.playWarning() }
            }
        }
        if toEnd > 0 {
            endTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(toEnd * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.haptics.playRestEnd() }
            }
        }
    }
```

- [ ] Create `PulseWatch/WatchRestView.swift`:

```swift
import SwiftUI

struct WatchRestView: View {
    let model: WatchSessionModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let s = model.snapshot
            let remaining = s.remainingRest(now: context.date)
            let fraction = s.restFraction(now: context.date)
            VStack(spacing: 8) {
                ZStack {
                    Circle().stroke(.gray.opacity(0.3), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(timeString(remaining)).font(.system(size: 30, weight: .bold))
                }
                .frame(width: 92, height: 92)

                HStack(spacing: 4) {
                    chip("−15") { model.adjustRest(-15) }
                    chip("+15") { model.adjustRest(15) }
                    chip("+30") { model.adjustRest(30) }
                }
                Button("Skip") { model.skipRest() }
                    .buttonStyle(.bordered)
                if let next = s.nextExerciseName {
                    Text("UP NEXT · \(next)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func chip(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.system(.caption2, design: .monospaced))
            .buttonStyle(.bordered)
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }
}
```

- [ ] Route `.rest` to the real view in `WatchRootView` — replace the placeholder:

```swift
        case .rest:
            WatchRestView(model: model)
```

- [ ] Regenerate + build the watch target:
  `xcodegen generate`
  `xcodebuild build -scheme Pulse -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' 2>&1 | tail -20`
  Expected: `** BUILD SUCCEEDED **`.

- [ ] Commit:
  `git add PulseWatch`
  `git commit -m "feat(watch): rest screen + local rest-end haptics [BAK-37]"`

---

## Task 7 — Real `WCSession` transport wiring (build-verified, paired-device on the checklist)

> **Transport task — build-verified.** `WCSession` cannot be unit-tested (the `MockWorkoutSyncChannel` already covers the logic). This task wires the real channels on both sides and hooks `WatchSyncBridge` into the phone's flow. Behaviour is verified on paired devices via the manual checklist (AC5, AC7).

**Files:**
- `Pulse/Core/Workout/WCSessionWorkoutSyncChannel.swift` (new — phone)
- `PulseWatch/WCSessionWatchSyncChannel.swift` (new — watch)
- `Pulse/Features/ActiveWorkout/ActiveWorkoutFlowView.swift` (modified — instantiate `WatchSyncBridge`, call `sync()` at the Live Activity sync points)
- `PulseWatch/PulseWatchApp.swift` (modified — inject the real channel + activate `WCSession`)

Steps:

- [ ] Create `Pulse/Core/Workout/WCSessionWorkoutSyncChannel.swift` (phone side):

```swift
import Foundation
import WatchConnectivity

/// Phone-side real transport. Latest session state goes via
/// `updateApplicationContext` (coalesced, survives unreachability — the watch
/// reconciles to it on reconnect). Commands arrive via `didReceiveMessage`.
final class WCSessionWorkoutSyncChannel: NSObject, WorkoutSyncChannel, WCSessionDelegate {
    private let session: WCSession
    private var commandHandler: ((WorkoutCommand) -> Void)?

    init(session: WCSession = .default) {
        self.session = session
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func send(state: WorkoutSyncSnapshot) {
        guard session.activationState == .activated,
              let data = try? JSONEncoder().encode(state) else { return }
        // updateApplicationContext throws if called before activation; guarded above.
        try? session.updateApplicationContext(["state": data])
    }

    func send(command: WorkoutCommand) { /* phone does not send commands */ }

    func onState(_ handler: @escaping (WorkoutSyncSnapshot) -> Void) { /* phone receives commands, not state */ }

    func onCommand(_ handler: @escaping (WorkoutCommand) -> Void) { commandHandler = handler }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["command"] as? Data,
              let command = try? JSONDecoder().decode(WorkoutCommand.self, from: data) else { return }
        DispatchQueue.main.async { self.commandHandler?(command) }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
```

- [ ] Create `PulseWatch/WCSessionWatchSyncChannel.swift` (watch side):

```swift
import Foundation
import WatchConnectivity

/// Watch-side real transport. Receives the latest snapshot via
/// `didReceiveApplicationContext` (always the freshest phone truth, so a
/// reconnect reconciles automatically) and sends commands via `sendMessage`.
/// Commands sent while unreachable are dropped — the phone is authoritative and
/// the watch reflects truth on the next snapshot.
final class WCSessionWatchSyncChannel: NSObject, WorkoutSyncChannel, WCSessionDelegate {
    private let session: WCSession
    private var stateHandler: ((WorkoutSyncSnapshot) -> Void)?

    init(session: WCSession = .default) {
        self.session = session
        super.init()
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
    }

    func send(state: WorkoutSyncSnapshot) { /* watch does not send state */ }

    func send(command: WorkoutCommand) {
        guard session.activationState == .activated, session.isReachable,
              let data = try? JSONEncoder().encode(command) else { return } // dropped if unreachable
        session.sendMessage(["command": data], replyHandler: nil, errorHandler: nil)
    }

    func onState(_ handler: @escaping (WorkoutSyncSnapshot) -> Void) {
        stateHandler = handler
        // Replay the context already received before the handler was set.
        if let data = session.receivedApplicationContext["state"] as? Data,
           let state = try? JSONDecoder().decode(WorkoutSyncSnapshot.self, from: data) {
            DispatchQueue.main.async { handler(state) }
        }
    }

    func onCommand(_ handler: @escaping (WorkoutCommand) -> Void) { /* watch receives state, not commands */ }

    // MARK: WCSessionDelegate
    func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let data = context["state"] as? Data,
              let state = try? JSONDecoder().decode(WorkoutSyncSnapshot.self, from: data) else { return }
        DispatchQueue.main.async { self.stateHandler?(state) }
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
}
```

- [ ] Inject the real channel into the watch app — update `PulseWatch/PulseWatchApp.swift`, removing the `IdleSyncChannel`:

```swift
import SwiftUI

@main
struct PulseWatchApp: App {
    @State private var model = WatchSessionModel(channel: WCSessionWatchSyncChannel())

    var body: some Scene {
        WindowGroup { WatchRootView(model: model) }
    }
}
```

- [ ] Hook the bridge into the phone flow. In `ActiveWorkoutFlowView.swift`, create the bridge next to the existing `WorkoutLiveActivityController` and call `bridge.sync()` everywhere `controller.sync()` is called. Inject the real channel and read `soundOnRestEnd` from the settings the flow already holds. (Mirror the controller's ownership pattern — same `@State`/init site, same sync call sites. The exact lines depend on the current flow wiring; keep the closure `{ settings.soundOnRestEnd }` so the gate stays live.)

- [ ] Regenerate + build BOTH targets:
  `xcodegen generate`
  `xcodebuild build -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
  `xcodebuild build -scheme Pulse -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' 2>&1 | tail -20`
  Expected: both `** BUILD SUCCEEDED **`.

- [ ] Re-run the full unit gate to confirm nothing regressed:
  `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:PulseTests 2>&1 | tail -20`

- [ ] Commit:
  `git add Pulse PulseWatch`
  `git commit -m "feat(watch): WCSession transport + phone flow wiring [BAK-37]"`

---

## Manual verification checklist (paired iPhone + Apple Watch)

`WCSession` paired-device behaviour can't be unit-tested — verify these by hand on a paired device pair (or iPhone + paired Watch simulators) before opening the PR. Maps to spec AC5–AC7.

- [ ] **AC5 — phone → watch sync.** Start a workout on the phone, begin sets. The watch leaves the idle screen and shows the current exercise, set X of N, target reps, and weight within ~1s.
- [ ] **AC5 — watch → phone sync.** Tap **Log set** on the watch. The phone advances the set (logs it, moves to rest) and the watch updates to the rest screen — both within ~1s. Repeat for **Skip set**, **−15/+15/+30**, and **Skip rest**; each watch action is reflected on the phone and the resulting truth comes back to the watch.
- [ ] **AC6 — rest-end haptic.** Enter rest. Confirm a lighter warning haptic fires on the wrist at **T‑10s** and a success haptic at **0**. Toggle **You → Sound on rest end OFF** and confirm no haptics fire (the snapshot's `soundOnRestEnd` gate). Toggle back ON and confirm they return.
- [ ] **AC6 — adjust resets haptics.** During rest, tap **+30** on the watch (or phone). Confirm the haptics re-schedule to the new end (warning fires 10s before the new 0).
- [ ] **AC7 — out-of-range then reconnect.** With a session active and resting, move the watch out of range (or disable Bluetooth / set the watch to Airplane mode). Tap a watch command and confirm it is dropped (phone unchanged). Advance the set on the **phone**. Bring the watch back in range — confirm the watch reconciles to the phone's current state (last-write-wins from the phone) without a stale screen.
- [ ] **Join-only.** With no session running, the watch shows the idle "Open Pulse on your phone to start" screen and offers no start/finish controls.
