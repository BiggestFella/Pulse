# Live Activity (lock screen / Dynamic Island timer) Implementation Plan — BAK-20

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Project the active-session engine's `active`/`rest` phases onto the iOS lock screen and Dynamic Island via a WidgetKit + ActivityKit **Live Activity**. The app owns all state (`stepIdx`/`doneSteps`/`swaps`); a thin `@Observable` controller maps engine state to an `ActivityContentState` and drives the ActivityKit lifecycle (start on first `active`, push on every transition, end on leaving the session). Any interaction (Skip rest) routes back through the same `afterRest` engine function — the Activity is a projection, never a second source of truth.

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. The controller lives in `Pulse/Features/ActiveWorkout/` alongside the BAK-14 active flow; shared `ActivityAttributes`/`ContentState` and the set-type label map live in `Pulse/Core/Workout/` so the app and the `PulseWidgets` extension share one definition. The Live Activity UI (lock screen + Dynamic Island compact/expanded/minimal) lives in `PulseWidgets`. Theme is propagated to the widget extension through a token snapshot embedded in `ContentState` (resolves the spec's open question #2 — no App Group needed for v1; a theme change triggers a re-push). Project is generated from `project.yml` via XcodeGen — never hand-edit the `.xcodeproj`.

**Tech Stack:** Swift 5.9+, SwiftUI, ActivityKit, WidgetKit, App Intents, XcodeGen, XCTest + XCUITest.

---

## Prerequisites (verify before starting)

This feature is **UI-first**: it renders against the BAK-14 session engine driven by the BAK-6 in-memory mock repositories' sample workout. It never calls Supabase directly.

- **Design System (BAK-7)** must be built first: `Theme` tokens (`bg`, `surface`, `ink`, `inkSoft`, `inkFaint`, `accent`, `accent2`, `onAccent`) and the three font families (Oswald hero numerals, Geist Mono uppercase labels, Hanken body) must be available.
- **Data layer (BAK-6)** must be built first: the `WorkoutRepository`/`ExerciseRepository` protocols + in-memory mocks seeding the sample PPL workout (including the single-set `failure` finisher and at least one superset pair).
- **Active-session engine (BAK-14)** must be built first: it owns `phase` (`pre`/`active`/`rest`/`summary`), `stepIdx`, `doneSteps`, `swaps`, the precomputed `STEPS[]`, and the transitions `logSet`, `afterRest`, rest-adjust (`−15/+15/+30`), `swapExercise`, `jumpToExercise`, `endWorkout`. This plan adds a **content-projection hook** to the engine but does not reimplement it.

Resolved product decisions applied below: **kg-only v1** (weights formatted via the shared weight helper, "KG" not "LBS"); `totalRest` derives from the engine's resolved rest duration (default 90s). The spec's open questions are resolved as: **interactive App Intent for Skip rest** (AC10 primary path) plus deep-link fallback; **theme via token snapshot in `ContentState`**; **`dropset` label = `"DROP SET"`**; set-type pill highlight uses **`onAccent`** on the filled chip.

- [ ] **Step 0a: Confirm prerequisite types exist**

Run:
```bash
ls Pulse/Core/Workout/SessionEngine.swift Pulse/Core/DesignSystem/Theme.swift Pulse/Core/Data/WorkoutRepository.swift
```
Expected: all three paths print (no "No such file"). If any is missing, its feature (BAK-14/BAK-7/BAK-6) is not yet built — stop and build it first.

- [ ] **Step 0b: Confirm XcodeGen and a clean build**

Run:
```bash
which xcodegen && xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 0c: Branch**

Run:
```bash
git switch -c feature/BAK-20-live-activity
```

---

## Task 1: Shared set-type label map (TDD)

The in-app active hero map omits `dropset`; the Live Activity must define a non-empty label for **all five** types (AC5). This shared helper is the single source so the app and widget agree.

**Files:**
- Create: `Pulse/Core/Workout/SetTypeLabel.swift`
- Create: `PulseTests/SetTypeLabelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/SetTypeLabelTests.swift`**

```swift
import XCTest
@testable import Pulse

final class SetTypeLabelTests: XCTestCase {
    func testEveryTypeHasNonEmptyUppercaseLabel() {
        for type in SetType.allCases {
            let label = SetTypeLabel.text(for: type)
            XCTAssertFalse(label.isEmpty, "\(type) must have a label")
            XCTAssertEqual(label, label.uppercased(), "\(type) label must be uppercase")
        }
    }

    func testExactLabels() {
        XCTAssertEqual(SetTypeLabel.text(for: .working), "WORKING")
        XCTAssertEqual(SetTypeLabel.text(for: .warmup), "WARMUP")
        XCTAssertEqual(SetTypeLabel.text(for: .dropset), "DROP SET")
        XCTAssertEqual(SetTypeLabel.text(for: .failure), "FAILURE")
        XCTAssertEqual(SetTypeLabel.text(for: .amrap), "AMRAP")
    }

    func testOnlyWorkingIsFilledChip() {
        XCTAssertTrue(SetTypeLabel.isFilledChip(.working))
        XCTAssertFalse(SetTypeLabel.isFilledChip(.warmup))
        XCTAssertFalse(SetTypeLabel.isFilledChip(.dropset))
        XCTAssertFalse(SetTypeLabel.isFilledChip(.failure))
        XCTAssertFalse(SetTypeLabel.isFilledChip(.amrap))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `SetTypeLabel` undefined.

- [ ] **Step 3: Write `Pulse/Core/Workout/SetTypeLabel.swift`**

```swift
import Foundation

/// Single source of truth for set-type display labels and chip styling, shared
/// by the in-app active hero and the Live Activity. Covers all five SetType
/// cases — the in-app hero map omits `dropset`, so this defines it explicitly.
enum SetTypeLabel {
    static func text(for type: SetType) -> String {
        switch type {
        case .working: return "WORKING"
        case .warmup:  return "WARMUP"
        case .dropset: return "DROP SET"
        case .failure: return "FAILURE"
        case .amrap:   return "AMRAP"
        }
    }

    /// `working` renders as a filled chip (accent fill, onAccent text);
    /// all others render outlined per the active hero pill rules.
    static func isFilledChip(_ type: SetType) -> Bool {
        type == .working
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (SetTypeLabelTests green).

- [ ] **Step 5: Register the shared file in both targets and regenerate**

Edit `project.yml` to add a shared sources group so `SetTypeLabel.swift` (and the attributes file from Task 2) compile into both `Pulse` and `PulseWidgets`. (The `PulseWidgets` target itself is added in Task 3; for now ensure the file is in the `Pulse` target's `Pulse` source root — already covered — and note it will be referenced from `PulseWidgets` in Task 3.) No `project.yml` change is required yet; the file is under `Pulse/` which the app target already globs.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/Workout/SetTypeLabel.swift PulseTests/SetTypeLabelTests.swift
git commit -m "feat: shared set-type label map covering all five types (BAK-20)"
```

---

## Task 2: Shared `ActivityAttributes` + `ContentState` (TDD)

The `ContentState` is the wire format between app and widget. It must be `Codable, Hashable` and carry a theme token snapshot so the widget renders the active palette without an App Group.

**Files:**
- Create: `Pulse/Core/Workout/WorkoutActivityAttributes.swift`
- Create: `PulseTests/WorkoutActivityAttributesTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/WorkoutActivityAttributesTests.swift`**

```swift
import XCTest
@testable import Pulse

final class WorkoutActivityAttributesTests: XCTestCase {
    private func sampleState() -> WorkoutActivityAttributes.ContentState {
        WorkoutActivityAttributes.ContentState(
            phase: .rest,
            exerciseName: "Bench Press",
            setIndex: 2, totalSets: 4,
            setTypeLabel: "WORKING",
            targetReps: 8, targetWeight: 80,
            ssLabel: nil, isMidPair: false,
            restEndsAt: Date(timeIntervalSince1970: 1_000_090),
            totalRest: 90,
            nextExerciseName: "Bench Press", nextReps: 8, nextWeight: 80, nextSsLabel: nil,
            completedSets: 1, totalStepCount: 12,
            palette: .coastal)
    }

    func testContentStateCodableRoundTrip() throws {
        let original = sampleState()
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            WorkoutActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testContentStateIsHashable() {
        XCTAssertEqual(sampleState().hashValue, sampleState().hashValue)
    }

    func testRestFractionUsesTotalRest() {
        let now = Date(timeIntervalSince1970: 1_000_045) // 45s elapsed of 90
        let state = sampleState()
        XCTAssertEqual(state.restFraction(now: now), 0.5, accuracy: 0.001)
    }

    func testRestFractionClampsAtZeroWhenElapsed() {
        let now = Date(timeIntervalSince1970: 1_000_200) // past end
        XCTAssertEqual(sampleState().restFraction(now: now), 0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `WorkoutActivityAttributes` undefined.

- [ ] **Step 3: Write `Pulse/Core/Workout/WorkoutActivityAttributes.swift`**

```swift
import ActivityKit
import Foundation

/// Shared between the app (which publishes state) and the PulseWidgets extension
/// (which renders it). The Live Activity is a projection of the session engine.
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable { case active, rest }

        var phase: Phase
        var exerciseName: String        // resolves session swaps
        var setIndex: Int               // 1-based
        var totalSets: Int
        var setTypeLabel: String        // defined for all 5 types incl. dropset
        var targetReps: Int?            // nil → render ∞ for failure
        var targetWeight: Double?       // nil/0 → omit for failure / bodyweight
        var ssLabel: String?            // "4A"/"4B" for supersets
        var isMidPair: Bool             // engine step.rest == false within a pair
        var restEndsAt: Date?           // absolute end; nil when phase == .active
        var totalRest: TimeInterval     // resolved rest duration → ring fraction base
        var nextExerciseName: String?   // UP NEXT preview
        var nextReps: Int?
        var nextWeight: Double?
        var nextSsLabel: String?
        var completedSets: Int          // doneSteps.count
        var totalStepCount: Int         // STEPS.count
        var palette: Palette            // theme token snapshot for the widget

        /// remaining / totalRest, clamped to 0...1. Drives the rest ring.
        func restFraction(now: Date = Date()) -> Double {
            guard let end = restEndsAt, totalRest > 0 else { return 0 }
            let remaining = end.timeIntervalSince(now)
            return min(max(remaining / totalRest, 0), 1)
        }
    }

    // Static attributes (set once at Activity start).
    var workoutName: String
}
```

- [ ] **Step 4: Confirm `Palette` is `Codable`**

`Palette` (from BAK-7) is a `String`-backed `enum`. Verify it conforms to `Codable`; if not, add `Codable` to its declaration in `Pulse/Core/DesignSystem/Palette.swift` (a one-line conformance, no behavior change). The widget reconstructs `Palette.tokens` from this snapshot.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/Workout/WorkoutActivityAttributes.swift PulseTests/WorkoutActivityAttributesTests.swift Pulse/Core/DesignSystem/Palette.swift
git commit -m "feat: shared WorkoutActivityAttributes + ContentState with theme snapshot (BAK-20)"
```

---

## Task 3: Add the `PulseWidgets` extension target (XcodeGen)

Register the widget extension, enable Live Activities on the app, and share the `Core/Workout` files into both targets.

**Files:**
- Modify: `project.yml`
- Create: `PulseWidgets/Info.plist`
- Create: `PulseWidgets/PulseWidgetsBundle.swift`

- [ ] **Step 1: Write `PulseWidgets/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSExtension</key>
  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string>
  </dict>
</dict>
</plist>
```

- [ ] **Step 2: Write `PulseWidgets/PulseWidgetsBundle.swift`**

```swift
import SwiftUI
import WidgetKit

@main
struct PulseWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
    }
}
```

- [ ] **Step 3: Edit `project.yml` — add the extension target, shared sources, and `NSSupportsLiveActivities`**

Add `NSSupportsLiveActivities` to the app's Info settings, add the `PulseWidgets` target, and make the shared `Core/Workout` + `Core/DesignSystem` files compile into both targets. Replace the `targets:` block accordingly:

```yaml
targets:
  Pulse:
    type: application
    platform: iOS
    sources: [Pulse]
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: au.com.codeheroes.pulse
        GENERATE_INFOPLIST_FILE: YES
        INFOPLIST_KEY_UILaunchScreen_Generation: YES
        INFOPLIST_KEY_NSSupportsLiveActivities: YES
    dependencies:
      - target: PulseWidgets
        embed: true
  PulseWidgets:
    type: app-extension
    platform: iOS
    sources:
      - path: PulseWidgets
      - path: Pulse/Core/Workout/WorkoutActivityAttributes.swift
      - path: Pulse/Core/Workout/SetTypeLabel.swift
      - path: Pulse/Core/Models/WorkoutModels.swift
      - path: Pulse/Core/DesignSystem/Palette.swift
      - path: Pulse/Core/DesignSystem/Theme.swift
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: au.com.codeheroes.pulse.widgets
        INFOPLIST_FILE: PulseWidgets/Info.plist
        GENERATE_INFOPLIST_FILE: NO
  PulseTests:
    type: bundle.unit-test
    platform: iOS
    sources: [PulseTests]
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: Pulse
  PulseUITests:
    type: bundle.ui-testing
    platform: iOS
    sources: [PulseUITests]
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: Pulse
```

(The `WorkoutModels.swift` is shared because `ContentState`/`SetTypeLabel` reference `SetType`. The `Theme`/`Palette` files are shared so the widget can resolve the palette snapshot to `Color`s.)

- [ ] **Step 4: Regenerate and confirm both targets compile**

The `WorkoutLiveActivity` referenced by the bundle does not exist yet — create a temporary stub so the target builds, replaced in Task 5. For now add a one-line stub at the bottom of `PulseWidgetsBundle.swift` is **not** allowed (no placeholders). Instead, do Task 5 before regenerating. Skip the build here; proceed to Task 5, then run:

```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected (after Task 5): `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit (after Task 5's views exist and the build passes)**

```bash
git add project.yml PulseWidgets/Info.plist PulseWidgets/PulseWidgetsBundle.swift
git commit -m "chore: add PulseWidgets app-extension target with shared sources (BAK-20)"
```

---

## Task 4: Skip-rest App Intent (TDD)

The Live Activity's "Skip rest" button uses an App Intent that routes into the **same `afterRest`** transition as the in-app button (AC10). The intent itself is logic — it must locate the live controller and call `afterRest`. Test it against a mockable engine handle.

**Files:**
- Create: `Pulse/Features/ActiveWorkout/SkipRestIntent.swift`
- Create: `PulseTests/SkipRestIntentTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/SkipRestIntentTests.swift`**

```swift
import XCTest
import AppIntents
@testable import Pulse

final class SkipRestIntentTests: XCTestCase {
    func testPerformCallsAfterRestOnSharedEngine() async throws {
        let spy = SkipRestTargetSpy()
        SkipRestIntent.target = spy

        let intent = SkipRestIntent()
        _ = try await intent.perform()

        XCTAssertEqual(spy.afterRestCallCount, 1)
    }

    func testPerformIsNoOpWhenNoActiveSession() async throws {
        SkipRestIntent.target = nil
        let intent = SkipRestIntent()
        _ = try await intent.perform() // must not crash
    }
}

/// Test double for the engine handle the intent routes into.
final class SkipRestTargetSpy: SkipRestTarget {
    private(set) var afterRestCallCount = 0
    func afterRest() { afterRestCallCount += 1 }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `SkipRestIntent` / `SkipRestTarget` undefined.

- [ ] **Step 3: Write `Pulse/Features/ActiveWorkout/SkipRestIntent.swift`**

```swift
import AppIntents

/// Abstraction over the live session engine so the intent is testable and the
/// Activity never owns state. The controller (Task 5) registers itself here.
protocol SkipRestTarget: AnyObject {
    func afterRest()
}

/// Fired by the "Skip rest" button on the Live Activity. Routes into the same
/// `afterRest` transition as the in-app button — advances without logging.
struct SkipRestIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Rest"
    /// Stay in-app context; do not bring the app foreground for this action.
    static var openAppWhenRun: Bool = false

    /// Set by the active controller while a session is live; nil otherwise.
    @MainActor static weak var target: SkipRestTarget?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.target?.afterRest()
        return .result()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/ActiveWorkout/SkipRestIntent.swift PulseTests/SkipRestIntentTests.swift
git commit -m "feat: SkipRestIntent routing into afterRest via testable target (BAK-20)"
```

---

## Task 5: Live Activity UI — lock screen + Dynamic Island (view assembly)

Pure SwiftUI view assembly using Theme tokens reconstructed from the `ContentState.palette` snapshot. Validated by `#Preview` and a UI test (Task 8), not line-by-line TDD.

**Files:**
- Create: `PulseWidgets/WorkoutLiveActivityViews.swift`
- Create: `PulseWidgets/WorkoutLiveActivity.swift`

- [ ] **Step 1: Write `PulseWidgets/WorkoutLiveActivityViews.swift` (shared subviews)**

Build the rest ring, set lockup, and UP NEXT card from tokens. The widget resolves a `Theme`-equivalent from the snapshot palette.

```swift
import SwiftUI

/// Resolves the palette snapshot embedded in ContentState into Colors, so the
/// widget renders the active Coastal/Mint theme without an App Group.
struct WidgetTheme {
    let palette: Palette
    private var t: PaletteTokens { palette.tokens }
    var bg: Color { Color(hex: t.bg) }
    var surface: Color { Color(hex: t.surface) }
    var ink: Color { Color(hex: t.ink) }
    var inkSoft: Color { Color(hex: t.ink).opacity(0.62) }
    var inkFaint: Color { Color(hex: t.ink).opacity(0.16) }
    var accent: Color { Color(hex: t.accent) }
    var accent2: Color { Color(hex: t.accent2) }
    var onAccent: Color { Color(hex: t.onAccent) }
}

/// mm:ss rest countdown numeral (Oswald) + accent2 ring over an inkFaint track.
struct RestRingView: View {
    let state: WorkoutActivityAttributes.ContentState
    let theme: WidgetTheme

    var body: some View {
        ZStack {
            Circle().stroke(theme.inkFaint, lineWidth: 6)
            Circle()
                .trim(from: 0, to: state.restFraction())
                .stroke(theme.accent2, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let end = state.restEndsAt {
                Text(timerInterval: Date()...end, countsDown: true)
                    .font(.custom("Oswald", size: 28))
                    .monospacedDigit()
                    .foregroundStyle(theme.ink)
            }
        }
        .frame(width: 64, height: 64)
    }
}

/// Active-phase set lockup: type pill + SET n/N + target reps numeral + weight.
struct SetLockupView: View {
    let state: WorkoutActivityAttributes.ContentState
    let theme: WidgetTheme

    private var isFailure: Bool { state.targetReps == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            setTypePill
            Text("SET \(state.setIndex)/\(state.totalSets)")
                .font(.custom("GeistMono-Regular", size: 11))
                .foregroundStyle(theme.inkSoft)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isFailure ? "∞" : "\(state.targetReps ?? 0)")
                    .font(.custom("Oswald", size: 30))
                    .foregroundStyle(theme.ink)
                if !isFailure, let w = state.targetWeight, w > 0 {
                    Text("\(Int(w)) KG")
                        .font(.custom("GeistMono-Regular", size: 11))
                        .foregroundStyle(theme.inkSoft)
                } else if isFailure {
                    Text("TO FAILURE")
                        .font(.custom("GeistMono-Regular", size: 11))
                        .foregroundStyle(theme.inkSoft)
                }
            }
        }
    }

    @ViewBuilder private var setTypePill: some View {
        let label = state.setTypeLabel
        let filled = label == "WORKING"
        Text(label)
            .font(.custom("GeistMono-Regular", size: 10))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(theme.onAccent)
            .background(
                Capsule().fill(filled ? theme.accent : .clear)
            )
            .overlay(
                Capsule().stroke(filled ? .clear : theme.inkFaint, lineWidth: 1)
            )
    }
}

/// UP NEXT preview (rest phase) — next exercise + reps/weight (or ∞), superset ssLabel.
struct UpNextView: View {
    let state: WorkoutActivityAttributes.ContentState
    let theme: WidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(state.isMidPair ? "NEXT IN PAIR" : "UP NEXT")
                    .font(.custom("GeistMono-Regular", size: 10))
                    .foregroundStyle(theme.inkSoft)
                if let ss = state.nextSsLabel {
                    Text("· \(ss)")
                        .font(.custom("GeistMono-Regular", size: 10))
                        .foregroundStyle(theme.accent)
                }
            }
            if let name = state.nextExerciseName {
                Text(name)
                    .font(.custom("HankenGrotesk-SemiBold", size: 14))
                    .foregroundStyle(theme.ink)
            }
            Text(nextDetail)
                .font(.custom("GeistMono-Regular", size: 11))
                .foregroundStyle(theme.inkSoft)
        }
    }

    private var nextDetail: String {
        let reps = state.nextReps.map(String.init) ?? "∞"
        if let w = state.nextWeight, w > 0 { return "\(reps) × \(Int(w)) KG" }
        return reps
    }
}
```

- [ ] **Step 2: Write `PulseWidgets/WorkoutLiveActivity.swift` (the `ActivityConfiguration`)**

Lock-screen card + Dynamic Island compact/expanded/minimal, all token-driven.

```swift
import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenCard(state: context.state)
                .activityBackgroundTint(Color(hex: context.state.palette.tokens.bg))
        } dynamicIsland: { context in
            let theme = WidgetTheme(palette: context.state.palette)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.phase == .rest {
                        RestRingView(state: context.state, theme: theme)
                    } else {
                        SetLockupView(state: context.state, theme: theme)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    UpNextView(state: context.state, theme: theme)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.phase == .rest {
                        Button(intent: SkipRestIntent()) {
                            Text("SKIP REST")
                                .font(.custom("GeistMono-Regular", size: 11))
                        }
                        .tint(theme.accent)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.phase == .rest ? "timer" : "dumbbell.fill")
                    .foregroundStyle(theme.accent)
            } compactTrailing: {
                compactValue(context.state, theme: theme)
            } minimal: {
                compactValue(context.state, theme: theme)
            }
            .keylineTint(theme.accent)
        }
    }

    @ViewBuilder
    private func compactValue(_ state: WorkoutActivityAttributes.ContentState,
                              theme: WidgetTheme) -> some View {
        if state.phase == .rest, let end = state.restEndsAt {
            Text(timerInterval: Date()...end, countsDown: true)
                .font(.custom("Oswald", size: 14))
                .monospacedDigit()
                .foregroundStyle(theme.ink)
                .frame(maxWidth: 44)
        } else {
            Text("\(state.setIndex)/\(state.totalSets)")
                .font(.custom("Oswald", size: 14))
                .foregroundStyle(theme.ink)
        }
    }
}

/// Lock-screen / banner presentation: rest or active card.
struct LockScreenCard: View {
    let state: WorkoutActivityAttributes.ContentState
    private var theme: WidgetTheme { WidgetTheme(palette: state.palette) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if state.phase == .rest {
                RestRingView(state: state, theme: theme)
                UpNextView(state: state, theme: theme)
            } else {
                SetLockupView(state: state, theme: theme)
                Spacer(minLength: 0)
                exerciseEyebrow
            }
            Spacer(minLength: 0)
            if state.phase == .rest {
                Button(intent: SkipRestIntent()) {
                    Text("SKIP")
                        .font(.custom("GeistMono-Regular", size: 11))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(theme.accent))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("la-skip-rest")
            }
        }
        .padding(16)
        .background(theme.bg)
    }

    private var exerciseEyebrow: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(state.exerciseName)
                .font(.custom("HankenGrotesk-SemiBold", size: 15))
                .foregroundStyle(theme.ink)
            if let ss = state.ssLabel {
                Text(ss)
                    .font(.custom("GeistMono-Regular", size: 10))
                    .foregroundStyle(theme.accent)
            }
        }
    }
}
```

- [ ] **Step 3: Add `#Preview`s for both presentations**

Append to `PulseWidgets/WorkoutLiveActivity.swift`:

```swift
#if DEBUG
extension WorkoutActivityAttributes {
    static var preview: WorkoutActivityAttributes { .init(workoutName: "Push Day") }
}
extension WorkoutActivityAttributes.ContentState {
    static var restPreview: Self {
        .init(phase: .rest, exerciseName: "Bench Press", setIndex: 2, totalSets: 4,
              setTypeLabel: "WORKING", targetReps: 8, targetWeight: 80,
              ssLabel: nil, isMidPair: false, restEndsAt: Date().addingTimeInterval(75),
              totalRest: 90, nextExerciseName: "Bench Press", nextReps: 8, nextWeight: 80,
              nextSsLabel: nil, completedSets: 5, totalStepCount: 12, palette: .coastal)
    }
    static var failurePreview: Self {
        .init(phase: .active, exerciseName: "Cable Fly", setIndex: 1, totalSets: 1,
              setTypeLabel: "FAILURE", targetReps: nil, targetWeight: nil,
              ssLabel: nil, isMidPair: false, restEndsAt: nil, totalRest: 90,
              nextExerciseName: nil, nextReps: nil, nextWeight: nil, nextSsLabel: nil,
              completedSets: 11, totalStepCount: 12, palette: .coastal)
    }
}

#Preview("Lock — Rest", as: .content, using: WorkoutActivityAttributes.preview) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState.restPreview
    WorkoutActivityAttributes.ContentState.failurePreview
}
#endif
```

- [ ] **Step 4: Regenerate, build (completes Task 3 Step 4), and verify previews compile**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED` (both `Pulse` and `PulseWidgets` compile).

- [ ] **Step 5: Commit**

```bash
git add PulseWidgets/WorkoutLiveActivity.swift PulseWidgets/WorkoutLiveActivityViews.swift
git commit -m "feat: Live Activity lock-screen + Dynamic Island UI on Theme tokens (BAK-20)"
```

---

## Task 6: `WorkoutLiveActivityController` — content mapping (TDD)

The `@Observable` controller maps engine state → `ContentState`. This is pure logic and gets strict TDD. It reads engine state only (never bypasses the engine to fetch data). To keep the mapper testable without ActivityKit, split it into a pure `ContentState` builder (tested here) and a thin lifecycle wrapper (Task 7).

**Files:**
- Create: `Pulse/Features/ActiveWorkout/WorkoutLiveActivityController.swift`
- Create: `PulseTests/WorkoutLiveActivityControllerTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/WorkoutLiveActivityControllerTests.swift`**

This assumes the BAK-14 engine exposes the documented surface: `phase`, `stepIdx`, `doneSteps`, `steps: [SessionStep]` where each step has `exerciseName`, `setIndex`, `totalSets`, `setType: SetType`, `targetReps: Int?`, `targetWeight: Double?`, `ssLabel: String?`, `rest: Bool`, and a resolved `restDuration`/`restEndsAt`. Adapt the accessor names if BAK-14 differs; the mapping assertions are the contract.

```swift
import XCTest
@testable import Pulse

final class WorkoutLiveActivityControllerTests: XCTestCase {
    // MARK: helpers
    private func step(name: String, idx: Int, total: Int, type: SetType,
                      reps: Int?, weight: Double?, ss: String? = nil,
                      rest: Bool = true) -> SessionStep {
        SessionStep(exerciseName: name, setIndex: idx, totalSets: total,
                    setType: type, targetReps: reps, targetWeight: weight,
                    ssLabel: ss, rest: rest)
    }

    private func engine(steps: [SessionStep], stepIdx: Int, phase: SessionPhase,
                        doneSteps: Int = 0, restEndsAt: Date? = nil,
                        totalRest: TimeInterval = 90,
                        palette: Palette = .coastal) -> MockSessionEngine {
        let e = MockSessionEngine()
        e.steps = steps; e.stepIdx = stepIdx; e.phase = phase
        e.doneStepsCount = doneSteps; e.restEndsAt = restEndsAt
        e.totalRest = totalRest; e.palette = palette
        return e
    }

    // AC4/AC5: active working set
    func testActiveWorkingSetMapping() {
        let e = engine(steps: [step(name: "Bench Press", idx: 2, total: 4,
                                    type: .working, reps: 8, weight: 80)],
                       stepIdx: 0, phase: .active, doneSteps: 5)
        let s = WorkoutContentBuilder.make(from: e)
        XCTAssertEqual(s.phase, .active)
        XCTAssertEqual(s.exerciseName, "Bench Press")
        XCTAssertEqual(s.setIndex, 2)
        XCTAssertEqual(s.totalSets, 4)
        XCTAssertEqual(s.setTypeLabel, "WORKING")
        XCTAssertEqual(s.targetReps, 8)
        XCTAssertEqual(s.targetWeight, 80)
        XCTAssertEqual(s.completedSets, 5)
    }

    // AC4: failure set → nil reps (∞), no weight
    func testFailureSetMapping() {
        let e = engine(steps: [step(name: "Cable Fly", idx: 1, total: 1,
                                    type: .failure, reps: nil, weight: nil, rest: false)],
                       stepIdx: 0, phase: .active)
        let s = WorkoutContentBuilder.make(from: e)
        XCTAssertNil(s.targetReps)
        XCTAssertNil(s.targetWeight)
        XCTAssertEqual(s.setTypeLabel, "FAILURE")
    }

    // AC5: dropset label non-empty
    func testDropsetLabelNonEmpty() {
        let e = engine(steps: [step(name: "Triceps", idx: 3, total: 3,
                                    type: .dropset, reps: 12, weight: 20)],
                       stepIdx: 0, phase: .active)
        let s = WorkoutContentBuilder.make(from: e)
        XCTAssertEqual(s.setTypeLabel, "DROP SET")
        XCTAssertFalse(s.setTypeLabel.isEmpty)
    }

    // AC2: rest phase fraction = remaining / totalRest
    func testRestPhaseFraction() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let end = now.addingTimeInterval(45)
        let e = engine(steps: [step(name: "Bench Press", idx: 2, total: 4,
                                    type: .working, reps: 8, weight: 80)],
                       stepIdx: 0, phase: .rest, restEndsAt: end, totalRest: 90)
        let s = WorkoutContentBuilder.make(from: e)
        XCTAssertEqual(s.phase, .rest)
        XCTAssertEqual(s.restEndsAt, end)
        XCTAssertEqual(s.totalRest, 90)
        XCTAssertEqual(s.restFraction(now: now), 0.5, accuracy: 0.001)
    }

    // AC6/AC12: superset round — mid-pair step maps isMidPair, no rest, carries partner ssLabel
    func testMidPairSupersetMapping() {
        let steps = [
            step(name: "Row", idx: 1, total: 2, type: .working, reps: 10, weight: 60, ss: "4A", rest: false),
            step(name: "Pulldown", idx: 1, total: 2, type: .working, reps: 10, weight: 50, ss: "4B"),
        ]
        let e = engine(steps: steps, stepIdx: 0, phase: .active)
        let s = WorkoutContentBuilder.make(from: e)
        XCTAssertTrue(s.isMidPair)
        XCTAssertNil(s.restEndsAt)
        XCTAssertEqual(s.ssLabel, "4A")
        XCTAssertEqual(s.nextSsLabel, "4B")
        XCTAssertEqual(s.nextExerciseName, "Pulldown")
    }

    // AC: completed/total counts
    func testCompletedAndTotalCounts() {
        let steps = (0..<12).map { step(name: "Ex\($0)", idx: 1, total: 1,
                                        type: .working, reps: 5, weight: 50) }
        let e = engine(steps: steps, stepIdx: 3, phase: .active, doneSteps: 3)
        let s = WorkoutContentBuilder.make(from: e)
        XCTAssertEqual(s.completedSets, 3)
        XCTAssertEqual(s.totalStepCount, 12)
    }

    // Theme snapshot propagates
    func testPaletteSnapshotPropagates() {
        let e = engine(steps: [step(name: "X", idx: 1, total: 1, type: .working,
                                    reps: 5, weight: 50)],
                       stepIdx: 0, phase: .active, palette: .mint)
        XCTAssertEqual(WorkoutContentBuilder.make(from: e).palette, .mint)
    }
}

// MARK: - Test double mirroring the BAK-14 engine surface the builder reads.
struct SessionStep {
    var exerciseName: String
    var setIndex: Int
    var totalSets: Int
    var setType: SetType
    var targetReps: Int?
    var targetWeight: Double?
    var ssLabel: String?
    var rest: Bool
}
enum SessionPhase { case pre, active, rest, summary }

final class MockSessionEngine: WorkoutContentSource {
    var steps: [SessionStep] = []
    var stepIdx = 0
    var phase: SessionPhase = .pre
    var doneStepsCount = 0
    var restEndsAt: Date?
    var totalRest: TimeInterval = 90
    var palette: Palette = .coastal
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `WorkoutContentBuilder` / `WorkoutContentSource` undefined.

- [ ] **Step 3: Write `Pulse/Features/ActiveWorkout/WorkoutLiveActivityController.swift`**

Define the source protocol (which the real BAK-14 engine conforms to via an extension — see Step 5), the pure builder, and the `@Observable` controller. Only the builder + protocol are needed to make Task 6 pass; the lifecycle methods are exercised in Task 7.

```swift
import Foundation

/// Read-only view of the session engine the Live Activity needs. The real
/// BAK-14 engine conforms via an extension; tests use a mock. SessionStep and
/// SessionPhase are the engine's own types (declared in Core/Workout by BAK-14).
protocol WorkoutContentSource: AnyObject {
    var steps: [SessionStep] { get }
    var stepIdx: Int { get }
    var phase: SessionPhase { get }
    var doneStepsCount: Int { get }
    var restEndsAt: Date? { get }
    var totalRest: TimeInterval { get }
    var palette: Palette { get }
}

/// Pure mapping: engine state → ContentState. No ActivityKit, fully testable.
enum WorkoutContentBuilder {
    static func make(from src: WorkoutContentSource) -> WorkoutActivityAttributes.ContentState {
        let cur = src.steps[src.stepIdx]
        let next = src.stepIdx + 1 < src.steps.count ? src.steps[src.stepIdx + 1] : nil
        let isMidPair = (cur.rest == false) && (cur.ssLabel != nil)

        return WorkoutActivityAttributes.ContentState(
            phase: src.phase == .rest ? .rest : .active,
            exerciseName: cur.exerciseName,
            setIndex: cur.setIndex,
            totalSets: cur.totalSets,
            setTypeLabel: SetTypeLabel.text(for: cur.setType),
            targetReps: cur.targetReps,
            targetWeight: cur.targetWeight,
            ssLabel: cur.ssLabel,
            isMidPair: isMidPair,
            restEndsAt: src.phase == .rest ? src.restEndsAt : nil,
            totalRest: src.totalRest,
            nextExerciseName: next?.exerciseName,
            nextReps: next?.targetReps,
            nextWeight: next?.targetWeight,
            nextSsLabel: next?.ssLabel,
            completedSets: src.doneStepsCount,
            totalStepCount: src.steps.count,
            palette: src.palette)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS.

- [ ] **Step 5: Conform the real BAK-14 engine to `WorkoutContentSource`**

In `Pulse/Features/ActiveWorkout/WorkoutLiveActivityController.swift`, add a conformance extension on the real engine type (named per BAK-14, e.g. `SessionEngine`). If BAK-14 already exposes `steps`/`stepIdx`/`phase`, this is empty conformance; otherwise map its property names. Remove the `SessionStep`/`SessionPhase`/`MockSessionEngine` duplicates from the test file if BAK-14 already declares `SessionStep`/`SessionPhase` (keep only `MockSessionEngine`). Re-run tests:

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (no redeclaration errors).

- [ ] **Step 6: Commit**

```bash
git add Pulse/Features/ActiveWorkout/WorkoutLiveActivityController.swift PulseTests/WorkoutLiveActivityControllerTests.swift
git commit -m "feat: WorkoutContentBuilder maps engine state to ContentState (BAK-20)"
```

---

## Task 7: Lifecycle + transition pushes (TDD)

The controller starts the Activity on first `active`, pushes a new `ContentState` on each relevant transition, recomputes `restEndsAt` on rest-adjust, and ends the Activity on `endWorkout`/`summary`. To test lifecycle without ActivityKit, route ActivityKit calls through a `LiveActivityHandle` protocol with an injectable mock.

**Files:**
- Modify: `Pulse/Features/ActiveWorkout/WorkoutLiveActivityController.swift`
- Modify: `PulseTests/WorkoutLiveActivityControllerTests.swift`

- [ ] **Step 1: Add failing lifecycle tests to `PulseTests/WorkoutLiveActivityControllerTests.swift`**

```swift
final class WorkoutLiveActivityLifecycleTests: XCTestCase {
    private func makeController() -> (WorkoutLiveActivityController, MockSessionEngine, MockActivityHandle) {
        let engine = MockSessionEngine()
        engine.steps = [SessionStep(exerciseName: "Bench Press", setIndex: 1, totalSets: 4,
                                    setType: .working, targetReps: 8, targetWeight: 80,
                                    ssLabel: nil, rest: true)]
        let handle = MockActivityHandle()
        let c = WorkoutLiveActivityController(engine: engine, handle: handle)
        return (c, engine, handle)
    }

    // AC1: first active starts an Activity
    func testFirstActiveStartsActivity() {
        let (c, engine, handle) = makeController()
        engine.phase = .pre
        c.sync()
        XCTAssertEqual(handle.startCount, 0, "no Activity during pre")
        engine.phase = .active
        c.sync()
        XCTAssertEqual(handle.startCount, 1)
    }

    // AC1: endWorkout / summary ends the Activity
    func testSummaryEndsActivity() {
        let (c, engine, handle) = makeController()
        engine.phase = .active; c.sync()
        engine.phase = .summary; c.sync()
        XCTAssertEqual(handle.endCount, 1)
    }

    // AC7: each transition pushes new content
    func testTransitionsPushContent() {
        let (c, engine, handle) = makeController()
        engine.phase = .active; c.sync()        // start + initial push
        let baseline = handle.updateCount
        engine.phase = .rest
        engine.restEndsAt = Date().addingTimeInterval(90)
        c.sync()                                 // afterRest → rest
        XCTAssertEqual(handle.updateCount, baseline + 1)
    }

    // AC8: rest -15 clamps remaining at 0; +30 has no upper clamp; both re-push
    func testRestAdjustClampAndPush() {
        let (c, engine, handle) = makeController()
        let now = Date(timeIntervalSince1970: 2_000_000)
        engine.phase = .rest
        engine.restEndsAt = now.addingTimeInterval(10)
        c.sync()
        let before = handle.updateCount

        c.adjustRest(by: -15, now: now)          // 10 - 15 → clamp to now
        XCTAssertEqual(engine.restEndsAt, now)
        XCTAssertEqual(handle.updateCount, before + 1)

        c.adjustRest(by: 30, now: now)           // now + 30, no upper clamp
        XCTAssertEqual(engine.restEndsAt, now.addingTimeInterval(30))
        XCTAssertEqual(handle.updateCount, before + 2)
    }
}

// Test double for the ActivityKit handle.
final class MockActivityHandle: LiveActivityHandle {
    var startCount = 0, updateCount = 0, endCount = 0
    var isRunning = false
    func start(_ state: WorkoutActivityAttributes.ContentState, name: String) {
        startCount += 1; isRunning = true
    }
    func update(_ state: WorkoutActivityAttributes.ContentState) { updateCount += 1 }
    func end() { endCount += 1; isRunning = false }
}
```

Extend `MockSessionEngine` with a mutable `restEndsAt` setter already present, and add an `adjustRest` to the engine mock that the controller delegates to:

```swift
extension MockSessionEngine {
    func setRestEndsAt(_ date: Date?) { restEndsAt = date }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `WorkoutLiveActivityController` / `LiveActivityHandle` undefined.

- [ ] **Step 3: Add the controller, handle protocol, and ActivityKit handle to `WorkoutLiveActivityController.swift`**

```swift
import ActivityKit

/// Wraps ActivityKit so the controller is testable. Real impl in this file;
/// tests inject a mock.
protocol LiveActivityHandle: AnyObject {
    var isRunning: Bool { get }
    func start(_ state: WorkoutActivityAttributes.ContentState, name: String)
    func update(_ state: WorkoutActivityAttributes.ContentState)
    func end()
}

/// @Observable coordinator: projects engine state onto the Live Activity and
/// owns its lifecycle. It is a projection — it reads the engine and routes
/// Skip-rest back through `afterRest`; it never holds canonical state.
@Observable
@MainActor
final class WorkoutLiveActivityController: SkipRestTarget {
    private let engine: any WorkoutContentSource
    private let handle: LiveActivityHandle
    private let workoutName: String

    init(engine: any WorkoutContentSource,
         handle: LiveActivityHandle = ActivityKitHandle(),
         workoutName: String = "Workout") {
        self.engine = engine
        self.handle = handle
        self.workoutName = workoutName
        SkipRestIntent.target = self
    }

    /// Call after every engine transition (logSet, afterRest, swap, jump).
    func sync() {
        switch engine.phase {
        case .pre:
            break // no Activity for pre
        case .active, .rest:
            let state = WorkoutContentBuilder.make(from: engine)
            if handle.isRunning {
                handle.update(state)
            } else {
                handle.start(state, name: workoutName)
            }
        case .summary:
            if handle.isRunning { handle.end() }
        }
    }

    /// Engine owns auto-advance; the Activity ends when the session ends.
    func endWorkout() { if handle.isRunning { handle.end() } }

    /// Rest adjust: clamp lower bound to `now`, no upper clamp, then re-push.
    func adjustRest(by delta: TimeInterval, now: Date = Date()) {
        guard let engine = engine as? RestAdjustable, let end = self.restEndsAt else { return }
        let proposed = end.addingTimeInterval(delta)
        engine.setRestEndsAt(max(proposed, now))
        sync()
    }

    private var restEndsAt: Date? { engine.restEndsAt }

    /// SkipRestTarget — Live Activity "Skip rest" routes here.
    func afterRest() {
        (engine as? AfterRestable)?.afterRest()
        sync()
    }
}

/// The real BAK-14 engine conforms to these so the controller can mutate rest
/// and advance. Declared here; BAK-14 supplies the bodies.
protocol RestAdjustable: AnyObject { func setRestEndsAt(_ date: Date?) }
protocol AfterRestable: AnyObject { func afterRest() }

/// Production ActivityKit handle.
final class ActivityKitHandle: LiveActivityHandle {
    private var activity: Activity<WorkoutActivityAttributes>?
    var isRunning: Bool { activity != nil }

    func start(_ state: WorkoutActivityAttributes.ContentState, name: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return } // graceful no-op
        let attributes = WorkoutActivityAttributes(workoutName: name)
        activity = try? Activity.request(
            attributes: attributes,
            content: .init(state: state, staleDate: nil))
    }

    func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        self.activity = nil
    }
}
```

Make `MockSessionEngine` conform to `RestAdjustable` & `AfterRestable` in the test file (add `: WorkoutContentSource, RestAdjustable, AfterRestable` and an `afterRest()` stub).

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (lifecycle + clamp + push tests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/ActiveWorkout/WorkoutLiveActivityController.swift PulseTests/WorkoutLiveActivityControllerTests.swift
git commit -m "feat: Live Activity lifecycle + transition pushes + rest-adjust clamp (BAK-20)"
```

---

## Task 8: Wire the controller into the active flow + graceful no-op

Hook the controller into the BAK-14 active-session screen so transitions call `sync()`, and ensure a denied/unsupported Activity request leaves the workout unaffected (AC, edge case).

**Files:**
- Modify: `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` (the BAK-14 model — exact name per BAK-14)
- Create: `PulseTests/WorkoutLiveActivityIntegrationTests.swift`

- [ ] **Step 1: Write the failing integration test `PulseTests/WorkoutLiveActivityIntegrationTests.swift`**

```swift
import XCTest
@testable import Pulse

final class WorkoutLiveActivityIntegrationTests: XCTestCase {
    // AC7: swap re-pushes with updated exercise name
    func testSwapRePushesUpdatedName() {
        let engine = MockSessionEngine()
        engine.steps = [SessionStep(exerciseName: "Bench Press", setIndex: 1, totalSets: 4,
                                    setType: .working, targetReps: 8, targetWeight: 80,
                                    ssLabel: nil, rest: true)]
        engine.phase = .active
        let handle = MockActivityHandle()
        let c = WorkoutLiveActivityController(engine: engine, handle: handle)
        c.sync()
        let before = handle.updateCount

        // simulate swapExercise resolving a new display name
        engine.steps[0].exerciseName = "Dumbbell Press"
        c.sync()
        XCTAssertEqual(handle.updateCount, before + 1)
    }

    // graceful no-op: handle that refuses to start leaves controller usable
    func testDeniedActivityDoesNotCrashFlow() {
        let engine = MockSessionEngine()
        engine.steps = [SessionStep(exerciseName: "X", setIndex: 1, totalSets: 1,
                                    setType: .working, targetReps: 5, targetWeight: 50,
                                    ssLabel: nil, rest: false)]
        engine.phase = .active
        let handle = DenyingActivityHandle()
        let c = WorkoutLiveActivityController(engine: engine, handle: handle)
        c.sync()               // start attempted but denied
        engine.phase = .summary
        c.sync()               // end is a no-op since never running
        XCTAssertFalse(handle.isRunning)
    }
}

/// Handle that simulates Live Activities disabled — start never takes effect.
final class DenyingActivityHandle: LiveActivityHandle {
    var isRunning: Bool { false }
    func start(_ state: WorkoutActivityAttributes.ContentState, name: String) {}
    func update(_ state: WorkoutActivityAttributes.ContentState) {}
    func end() {}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — compile errors only if the controller isn't yet integration-ready (it is from Task 7); the `start` no-op path may pass immediately. If both pass, that confirms graceful no-op; proceed.

- [ ] **Step 3: Hook `sync()` into the BAK-14 model transitions**

In the active-session model, own a `WorkoutLiveActivityController` and call `controller.sync()` at the end of each transition (`logSet`, `afterRest`, rest-adjust delegating to `controller.adjustRest`, `swapExercise`, `jumpToExercise`) and `controller.endWorkout()` in `endWorkout`. Example wiring (adapt to BAK-14 names):

```swift
// In ActiveWorkoutModel (BAK-14):
private lazy var liveActivity = WorkoutLiveActivityController(
    engine: self, workoutName: workout.name)

func logSet(/* … */) { /* existing engine logic */ ; liveActivity.sync() }
func afterRest()      { /* existing advance logic */ ; liveActivity.sync() }
func swapExercise(/* … */) { /* existing */ ; liveActivity.sync() }
func jumpToExercise(/* … */) { /* existing */ ; liveActivity.sync() }
func endWorkout()     { /* existing */ ; liveActivity.endWorkout() }
```

This requires `ActiveWorkoutModel` to conform to `WorkoutContentSource` (+ `RestAdjustable`, `AfterRestable`) — add the conformance extension mapping its engine properties.

- [ ] **Step 4: Run the tests to verify they pass; build**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS, `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/ActiveWorkout PulseTests/WorkoutLiveActivityIntegrationTests.swift
git commit -m "feat: wire Live Activity controller into active-session transitions (BAK-20)"
```

---

## Task 9: Acceptance / UI tests (XCUITest)

The Live Activity itself cannot be driven by XCUITest on the simulator's lock screen. Per spec, the acceptance criteria are validated by exercising the **in-app surface that drives the Activity** (a debug harness screen rendering the same `LockScreenCard` from a `ContentState`) plus the deep-link path. Add a hidden debug entry, gated to test builds, that renders `LockScreenCard` for a given fixture so UI tests can assert key elements exist.

**Files:**
- Create: `Pulse/Features/ActiveWorkout/LiveActivityDebugScreen.swift`
- Create: `PulseUITests/WorkoutLiveActivityTests.swift`
- Modify: `Pulse/App/AppShell.swift` (debug-only entry, behind a launch argument)

- [ ] **Step 1: Write `Pulse/Features/ActiveWorkout/LiveActivityDebugScreen.swift`**

Render the lock-screen card from fixtures, switchable by accessibility identifiers, so UI tests can assert AC4/AC5/AC6/AC11 on the real view. (The `LockScreenCard` lives in `PulseWidgets`; to reuse it in-app, move `WorkoutLiveActivityViews.swift` + `LockScreenCard` into shared `Core/Workout` sources, or duplicate a thin preview wrapper. Prefer: add the views' file to the `Pulse` target's globbed sources — it already is, since it lives under a shared path if you place reusable subviews in `Pulse/Core/Workout/LiveActivitySharedViews.swift`. For this task, render the subviews `RestRingView`/`SetLockupView`/`UpNextView` directly.)

```swift
import SwiftUI

#if DEBUG
struct LiveActivityDebugScreen: View {
    let state: WorkoutActivityAttributes.ContentState
    var body: some View {
        let theme = WidgetTheme(palette: state.palette)
        VStack(spacing: 16) {
            if state.phase == .rest {
                RestRingView(state: state, theme: theme)
                    .accessibilityIdentifier("la-rest-ring")
                UpNextView(state: state, theme: theme)
                    .accessibilityIdentifier("la-up-next")
            } else {
                SetLockupView(state: state, theme: theme)
                    .accessibilityIdentifier("la-set-lockup")
            }
        }
        .padding(16)
        .background(theme.bg)
    }
}
#endif
```

(To share `RestRingView`/`SetLockupView`/`UpNextView`/`WidgetTheme` with the app target, move `PulseWidgets/WorkoutLiveActivityViews.swift` to `Pulse/Core/Workout/LiveActivitySharedViews.swift` and update `project.yml` so both targets glob it. Do this move now, regenerate, and confirm the build.)

- [ ] **Step 2: Add a debug entry in `AppShell` behind a launch argument**

```swift
// In AppShell, inside the TabView body or as an overlay:
#if DEBUG
if ProcessInfo.processInfo.arguments.contains("-LA_DEBUG_REST") {
    LiveActivityDebugScreen(state: .restPreview)
} else if ProcessInfo.processInfo.arguments.contains("-LA_DEBUG_FAILURE") {
    LiveActivityDebugScreen(state: .failurePreview)
}
#endif
```

(Place these as a `fullScreenCover`/conditional root so the UI test sees only the debug screen when launched with the argument.)

- [ ] **Step 3: Write `PulseUITests/WorkoutLiveActivityTests.swift`**

```swift
import XCTest

final class WorkoutLiveActivityTests: XCTestCase {
    // AC2/AC6: rest surface shows ring + UP NEXT
    func testRestSurfaceShowsRingAndUpNext() {
        let app = XCUIApplication()
        app.launchArguments = ["-LA_DEBUG_REST"]
        app.launch()
        XCTAssertTrue(app.otherElements["la-rest-ring"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["la-up-next"].exists)
        XCTAssertTrue(app.staticTexts["UP NEXT"].exists)
    }

    // AC4/AC5: failure set shows ∞ / TO FAILURE and FAILURE label, no weight
    func testFailureSurfaceShowsInfinityAndLabel() {
        let app = XCUIApplication()
        app.launchArguments = ["-LA_DEBUG_FAILURE"]
        app.launch()
        XCTAssertTrue(app.otherElements["la-set-lockup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["FAILURE"].exists)
        XCTAssertTrue(app.staticTexts["∞"].exists)
        XCTAssertTrue(app.staticTexts["TO FAILURE"].exists)
        XCTAssertFalse(app.staticTexts["KG"].exists)
    }
}
```

- [ ] **Step 4: Run the UI tests; build**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (both UI tests green), `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add Pulse PulseWidgets PulseUITests/WorkoutLiveActivityTests.swift project.yml
git commit -m "test: acceptance/UI coverage for Live Activity surfaces via debug harness (BAK-20)"
```

---

## Task 10: Full suite, PR

- [ ] **Step 1: Run the full build + test suite**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' clean test
```
Expected: `TEST SUCCEEDED` — all unit + UI tests green, both targets build.

- [ ] **Step 2: Open the PR (⏸ outward action — confirm first)**

Run:
```bash
git push -u origin feature/BAK-20-live-activity
gh pr create --fill --base main
```
Link BAK-20, the spec, and this plan in the PR body; complete the PR template checklist (Theme tokens only, no Supabase, `xcodegen generate` clean).

---

## Self-Review notes

- **AC coverage:** AC1 (Task 7 lifecycle tests). AC2 (Task 2 `restFraction`, Task 6 rest mapping, Task 9 ring UI). AC3 (engine auto-advance + push, Task 7). AC4/AC5 (Task 1 labels, Task 6 failure/dropset mapping, Task 9 UI). AC6 (Task 6 UP NEXT + ssLabel, Task 9 UI). AC7 (Task 7/8 transition pushes). AC8 (Task 7 clamp test). AC9 (Task 5 compact/minimal DI). AC10 (Task 4 SkipRestIntent → afterRest). AC11 (Theme tokens throughout, `onAccent` on filled chip; Task 9 UI). AC12 (Task 6 mid-pair test, no rest segment).
- **Product decisions applied:** kg-only ("KG", `Int(weight)` via the shared weight formatter when BAK-13 lands), `totalRest` default 90s from the engine, theme-snapshot propagation, `dropset` = "DROP SET", `onAccent` on filled set-type pill.
- **Out of scope (honored):** no Supabase wiring, no session persistence across kills, no local notifications, no logging/PR computation, no Watch, no pre/summary presentation, no multi-Activity.
- **UI-first:** controller binds to the engine which sits over BAK-6 repository protocols + mocks; the Activity reads engine state only and never fetches data directly.
- **Adaptation note:** Tasks 6–8 assume the BAK-14 engine's accessor names (`steps`, `stepIdx`, `phase`, `doneStepsCount`, `restEndsAt`, `totalRest`, `swapExercise`, `jumpToExercise`, `afterRest`, `endWorkout`). If BAK-14 names differ, adapt the `WorkoutContentSource`/`RestAdjustable`/`AfterRestable` conformance extension only — the mapping assertions are the contract and must not change.
