# Workout Detail + Start — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user open a saved workout from the Library, see its exercises, and Start it — launching the existing active session.

**Architecture:** A new read-only `WorkoutDetailModel` + `WorkoutDetailView` in `Features/Library/`. A new `LibraryRoute.workoutDetail(id:name:)` is pushed when the (currently no-op) workout-row tap fires, in both the root Library and folder detail. The detail model fetches the workout via `WorkoutRepository.fetchWorkout(id:)`. Its Start button calls an `onStart: (Workout) -> Void` closure threaded from `AppShell`, which calls `session.startWorkout(_:)` — the same callback pattern Today and Plan already use.

**Tech Stack:** SwiftUI, `@Observable` MVVM, Swift Concurrency, XcodeGen (run `xcodegen generate` after adding files), XCTest.

**Spec:** `docs/superpowers/specs/2026-06-12-workout-detail-start-design.md`

---

## File Structure

- **Create** `Pulse/Features/Library/WorkoutDetailModel.swift` — `WorkoutDetailRow` value type + `WorkoutDetailModel` (`@Observable`): loads the workout, projects exercise rows, exposes `canStart`, fires `onStart`.
- **Create** `Pulse/Features/Library/WorkoutDetailView.swift` — the read-only screen with a Start button.
- **Create** `PulseTests/Features/Library/WorkoutDetailModelTests.swift` — unit tests (the acceptance gate).
- **Modify** `Pulse/Features/Library/LibraryRoute.swift` — add the `workoutDetail` case + marker.
- **Modify** `Pulse/Features/Library/LibraryView.swift` — add `onStartWorkout`, wire the two no-op `onOpenWorkout` callbacks, render the detail destination.
- **Modify** `Pulse/App/AppShell.swift` — pass `onStartWorkout` into `LibraryView`.

**Testing note:** Acceptance is covered by `WorkoutDetailModelTests` (load → rows, `canStart`, `start()` fires the callback with the workout). A full XCUITest is intentionally **not** added: in the `-uiMock` world the sample workouts live under a program (rendered as a program row), so there's no loose, tappable workout row to drive the flow, and the UI runner is unreliable on Xcode/iOS 26.5 (gate is `-only-testing:PulseTests`). The view gets accessibility identifiers so a UI test can be added later once the mock seeds a loose workout.

---

## Task 1: WorkoutDetailModel + row projection (unit-tested)

**Files:**
- Create: `Pulse/Features/Library/WorkoutDetailModel.swift`
- Test: `PulseTests/Features/Library/WorkoutDetailModelTests.swift`

- [ ] **Step 1: Create the model file**

Create `Pulse/Features/Library/WorkoutDetailModel.swift`:

```swift
import Foundation
import Observation

/// One exercise row on the Workout Detail screen.
struct WorkoutDetailRow: Identifiable, Equatable {
    let id: UUID            // WorkoutExercise.id
    let exerciseName: String
    let variationName: String
    let setSummary: String  // e.g. "4 sets · 12·10·8·6"
}

/// Read-only detail for a saved workout, with a Start action that hands the
/// hydrated workout to the active session via `onStart`.
@MainActor
@Observable
final class WorkoutDetailModel {
    let title: String
    private(set) var loadState: LibraryLoadState = .loading
    private(set) var rows: [WorkoutDetailRow] = []
    private(set) var workout: Workout?

    private let workoutID: UUID
    private let workoutRepo: any WorkoutRepository
    private let onStart: (Workout) -> Void

    init(workoutID: UUID,
         title: String,
         workoutRepo: any WorkoutRepository,
         onStart: @escaping (Workout) -> Void) {
        self.workoutID = workoutID
        self.title = title
        self.workoutRepo = workoutRepo
        self.onStart = onStart
    }

    /// Start is available only once the workout has loaded with ≥1 exercise.
    var canStart: Bool { workout?.exercises.isEmpty == false }

    func load() async {
        loadState = .loading
        do {
            guard let w = try await workoutRepo.fetchWorkout(id: workoutID) else {
                workout = nil; rows = []; loadState = .error; return
            }
            workout = w
            rows = w.exercises.map(Self.row)
            loadState = .loaded
        } catch {
            workout = nil; rows = []; loadState = .error
        }
    }

    func start() {
        guard let workout, canStart else { return }
        onStart(workout)
    }

    /// Project a `WorkoutExercise` into a display row. Variation name resolves
    /// from the chosen variation (or the exercise default); the set summary is
    /// the rep ladder joined by "·".
    static func row(_ we: WorkoutExercise) -> WorkoutDetailRow {
        let variation = we.exercise.variations.first {
            $0.id == (we.variationID ?? we.exercise.defaultVariationID)
        }
        let reps = we.sets.map { String($0.reps) }.joined(separator: "·")
        let n = we.sets.count
        let summary = "\(n) set\(n == 1 ? "" : "s")\(reps.isEmpty ? "" : " · \(reps)")"
        return WorkoutDetailRow(
            id: we.id,
            exerciseName: we.exercise.name,
            variationName: variation?.name ?? "",
            setSummary: summary)
    }
}
```

- [ ] **Step 2: Write the tests**

Create `PulseTests/Features/Library/WorkoutDetailModelTests.swift`:

```swift
import XCTest
@testable import Pulse

@MainActor
final class WorkoutDetailModelTests: XCTestCase {

    private func legExtension(reps: [Int]) -> WorkoutExercise {
        let v = Variation(name: "Machine", equipment: "Machine")
        let ex = Exercise(name: "Leg Extension", muscleGroup: "Legs",
                          variations: [v], defaultVariationID: v.id)
        let sets = reps.map { SetSpec(reps: $0, rir: 1, type: .working) }
        return WorkoutExercise(exercise: ex, variationID: v.id, supersetGroup: nil, sets: sets)
    }

    private func workout(_ exercises: [WorkoutExercise]) -> Workout {
        Workout(name: "Legs B", weekday: nil, order: 0, exercises: exercises)
    }

    func testLoadBuildsRowsFromWorkout() async {
        let w = workout([legExtension(reps: [12, 10, 8, 6])])
        let repo = FakeWorkoutRepository(workouts: [w])
        let model = WorkoutDetailModel(workoutID: w.id, title: "Legs B",
                                       workoutRepo: repo, onStart: { _ in })
        await model.load()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.rows.count, 1)
        XCTAssertEqual(model.rows[0].exerciseName, "Leg Extension")
        XCTAssertEqual(model.rows[0].variationName, "Machine")
        XCTAssertEqual(model.rows[0].setSummary, "4 sets · 12·10·8·6")
        XCTAssertTrue(model.canStart)
    }

    func testStartInvokesCallbackWithWorkout() async {
        let w = workout([legExtension(reps: [10])])
        let repo = FakeWorkoutRepository(workouts: [w])
        var started: Workout?
        let model = WorkoutDetailModel(workoutID: w.id, title: "Legs B",
                                       workoutRepo: repo, onStart: { started = $0 })
        await model.load()
        model.start()
        XCTAssertEqual(started?.id, w.id)
    }

    func testEmptyWorkoutDisablesStart() async {
        let w = workout([])
        let repo = FakeWorkoutRepository(workouts: [w])
        var started: Workout?
        let model = WorkoutDetailModel(workoutID: w.id, title: "Empty",
                                       workoutRepo: repo, onStart: { started = $0 })
        await model.load()
        XCTAssertFalse(model.canStart)
        model.start()
        XCTAssertNil(started, "start() must be a no-op when there are no exercises")
    }

    func testMissingWorkoutIsError() async {
        let repo = FakeWorkoutRepository(workouts: [])
        let model = WorkoutDetailModel(workoutID: UUID(), title: "Gone",
                                       workoutRepo: repo, onStart: { _ in })
        await model.load()
        XCTAssertEqual(model.loadState, .error)
        XCTAssertFalse(model.canStart)
    }
}
```

(`FakeWorkoutRepository` already exists at `PulseTests/Plan/FakePlanRepositories.swift` and implements `fetchWorkout(id:)`.)

- [ ] **Step 3: Register the new files with XcodeGen**

Run: `xcodegen generate`
Expected: "Created project at .../Pulse.xcodeproj" (new files are picked up by the synchronized groups).

- [ ] **Step 4: Run the tests**

Run (substitute an available simulator id from `xcrun simctl list devices available | grep iPhone`):
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:PulseTests/WorkoutDetailModelTests test
```
Expected: all 4 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Library/WorkoutDetailModel.swift \
        PulseTests/Features/Library/WorkoutDetailModelTests.swift project.yml
git commit -m "feat(library): WorkoutDetailModel — load workout, rows, start [workout-detail]"
```

---

## Task 2: WorkoutDetailView

**Files:**
- Create: `Pulse/Features/Library/WorkoutDetailView.swift`

- [ ] **Step 1: Create the view**

Create `Pulse/Features/Library/WorkoutDetailView.swift`:

```swift
import SwiftUI

/// Read-only detail for a saved workout, with a Start button that launches the
/// active session. Edit/Delete/Schedule will land here in a follow-up (scope C).
struct WorkoutDetailView: View {
    @State private var model: WorkoutDetailModel
    @Environment(Theme.self) private var theme

    init(model: WorkoutDetailModel) { _model = State(initialValue: model) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("workoutDetail.title")
                    .padding(.top, 8)

                content.padding(.top, 14)
            }
            .padding(.horizontal, 18).padding(.top, 8)
            .padding(.bottom, 96)   // room for the sticky Start button
        }
        .background(theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { startBar }
        .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.loadState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                .accessibilityIdentifier("workoutDetail.loading")
        case .error:
            Text("Couldn't load this workout.")
                .font(.system(size: 15)).foregroundStyle(theme.inkSoft)
                .frame(maxWidth: .infinity).padding(.top, 40)
                .accessibilityIdentifier("workoutDetail.error")
        case .loaded:
            VStack(alignment: .leading, spacing: 6) {
                StatLabel("EXERCISES · \(model.rows.count)")
                ForEach(model.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.variationName.isEmpty ? row.exerciseName
                                                        : "\(row.exerciseName) · \(row.variationName)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        Text(row.setSummary)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.inkFaint, lineWidth: 1.5))
                    .accessibilityIdentifier("workoutDetail.row.\(row.exerciseName)")
                }
            }
        }
    }

    @ViewBuilder private var startBar: some View {
        VStack(spacing: 4) {
            Button { model.start() } label: {
                Text("Start workout")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .disabled(!model.canStart)
            .opacity(model.canStart ? 1 : 0.5)
            .accessibilityIdentifier("workoutDetail.start")

            if model.loadState == .loaded && !model.canStart {
                Text("This workout has no exercises yet.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.inkSoft)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
```

- [ ] **Step 2: Register with XcodeGen**

Run: `xcodegen generate`
Expected: project regenerated.

- [ ] **Step 3: Build to verify it compiles**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```
Expected: `** BUILD SUCCEEDED **`. (If `theme.onAccent` does not resolve, use the design-system token for on-accent text per `docs/design/` — do not hardcode a color.)

- [ ] **Step 4: Commit**

```bash
git add Pulse/Features/Library/WorkoutDetailView.swift project.yml
git commit -m "feat(library): WorkoutDetailView — read-only screen + Start button [workout-detail]"
```

---

## Task 3: Route + navigation + shell wiring

**Files:**
- Modify: `Pulse/Features/Library/LibraryRoute.swift`
- Modify: `Pulse/Features/Library/LibraryView.swift`
- Modify: `Pulse/App/AppShell.swift`

- [ ] **Step 1: Add the route case**

In `Pulse/Features/Library/LibraryRoute.swift`, add the case to the enum (after `case folderDetail(...)`):

```swift
    case workoutDetail(id: UUID, name: String)
```

And add to the `marker` switch (alongside the others):

```swift
        case .workoutDetail(let id, _): return "workoutDetail:\(id)"
```

- [ ] **Step 2: Give LibraryView an onStartWorkout callback**

In `Pulse/Features/Library/LibraryView.swift`, add a stored property + explicit init at the top of the struct (after the existing `@State`/`@Environment` declarations, before `var body`):

```swift
    /// Hands a chosen workout up to the app shell to launch the active session.
    let onStartWorkout: (Workout) -> Void

    init(onStartWorkout: @escaping (Workout) -> Void = { _ in }) {
        self.onStartWorkout = onStartWorkout
    }
```

- [ ] **Step 3: Wire the root workout-row tap**

In `LibraryView.swift`, in `defaultBody(_:)`, replace the no-op:

```swift
                    onOpenWorkout: { _ in /* workout detail route lands with that feature */ },
```

with:

```swift
                    onOpenWorkout: { workout in path.append(.workoutDetail(id: workout.id, name: workout.name)) },
```

- [ ] **Step 4: Wire the folder-detail workout-row tap**

In `LibraryView.swift`, in `destination(_:)`'s `.folderDetail` case, replace:

```swift
                onOpenWorkout: { _ in },
```

with:

```swift
                onOpenWorkout: { workout in path.append(.workoutDetail(id: workout.id, name: workout.name)) },
```

- [ ] **Step 5: Render the detail destination**

In `LibraryView.swift`, in `destination(_:)`, add a case before `default:`:

```swift
        case .workoutDetail(let id, let name):
            WorkoutDetailView(model: WorkoutDetailModel(
                workoutID: id, title: name,
                workoutRepo: repos.workouts, onStart: onStartWorkout))
```

- [ ] **Step 6: Pass the callback from AppShell**

In `Pulse/App/AppShell.swift`, in `tabs`, replace:

```swift
            LibraryView()
```

with:

```swift
            LibraryView(onStartWorkout: { session.startWorkout($0) })
```

- [ ] **Step 7: Regenerate + build**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```
Expected: `** BUILD SUCCEEDED **`. (`LibraryView()` in the file's `#Preview` still compiles thanks to the defaulted `onStartWorkout`.)

- [ ] **Step 8: Run the full unit gate**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:PulseTests test
```
Expected: PulseTests PASS (including `WorkoutDetailModelTests`).

- [ ] **Step 9: Commit**

```bash
git add Pulse/Features/Library/LibraryRoute.swift \
        Pulse/Features/Library/LibraryView.swift \
        Pulse/App/AppShell.swift project.yml
git commit -m "feat(library): open a saved workout and start it [workout-detail]"
```

---

## Task 4: Manual verification on device/simulator

**Files:** none (verification only)

- [ ] **Step 1: Build, install, and exercise the flow**

Run the app (simulator or device per the project's run flow). Then:
1. Go to **Library** → tap a saved workout row (e.g. under a folder, or "Legs B" on the live path).
2. Confirm the **Workout Detail** screen shows the exercises with set summaries.
3. Tap **Start workout** → confirm the active session takes over full-screen (`activeFlow.root`).
4. Confirm an empty workout shows a disabled Start with the "no exercises yet" hint.

Expected: all four behave as described. No commit (verification step).

---

## Self-Review

- **Spec coverage:**
  - AC1 (tap row → detail, root + folder) → Task 3 Steps 3–5.
  - AC2 (name + exercises + set summary) → Task 1 `row()` + Task 2 view; `setSummary` asserted in tests.
  - AC3 (Start launches active session) → Task 3 Steps 5–6 (`onStart` → `session.startWorkout`); `start()` callback asserted in Task 1.
  - AC4 (empty → disabled Start + hint) → `canStart` (Task 1, tested) + `startBar` hint (Task 2).
  - AC5 (sets persist) → reuses the existing active flow; no new code.
  - Architecture (callback threading) → Task 3 Steps 2, 6.
  - Non-goals (Edit/Delete/Schedule, Today/Plan) → not implemented; view leaves room.
- **Placeholder scan:** none — every step has full code or an exact command.
- **Type consistency:** `WorkoutDetailModel(workoutID:title:workoutRepo:onStart:)`, `onStart: (Workout) -> Void`, `LibraryRoute.workoutDetail(id:name:)`, and `WorkoutDetailRow` fields are used identically across Tasks 1–3. `LibraryLoadState` is the existing shared enum. `FakeWorkoutRepository(workouts:)` matches the existing test helper.
