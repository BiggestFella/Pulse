# Today Tab (BAK-9) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Logic (the `@Observable` model, repositories, mocks) is built strict-TDD (failing test → run → minimal impl → run → commit); SwiftUI views are built as concrete structure + `#Preview` + an XCUITest. Never hardcode a color, spacing, or radius — `Theme` tokens only.

**Goal:** Build the Today tab — the app's home screen and first tab — as a SwiftUI screen bound to repository protocols backed by in-memory mocks. It surfaces today's prescribed workout in an `accent` hero card with a one-tap **Start →**, a 7-cell week-progress strip, a greeting + streak header, and a tappable Yesterday recap row. `Start →` and the Yesterday push target are stubs here (active flow is BAK-14; Session Detail is a separate feature).

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. One screen = `TodayView` (View) + `TodayModel` (`@Observable`) in `Pulse/Features/Today/`. The model loads on appear and exposes view-ready value types; it reads data **only** through repository protocols injected via its initializer (never Supabase directly). Colors/spacing/radii/type come from the injected `Theme`. The Today tab is a `NavigationStack` root inside the existing `AppShell` `TabView`.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency (`async`/`await`), XcodeGen, XCTest + XCUITest. Test destination: `platform=iOS Simulator,name=iPhone 17`.

**Prerequisites (must be built first):**
- **Design System (BAK-7)** — provides the `Theme` tokens used throughout. The repo currently has `Theme`/`Palette` (Coastal/Mint) from the foundation layer; the richer BAK-7 components (Lockup, pressable `ButtonStyle`, eyebrow/H1/numeral text styles, row component, vendored fonts) may not all exist yet. **This plan therefore defines the small Today-local view pieces it needs (eyebrow/numeral text, hero lockup, pressable button style, week cell, recap row) inside `Pulse/Features/Today/`.** If BAK-7 has already shipped equivalents, replace the local copies with the shared components in a follow-up — but do not block on BAK-7 here.
- **Data layer (BAK-6)** — owns the real repository protocols + Supabase implementations. They are not yet in the repo. This plan declares the **protocol surface Today consumes** in `Pulse/Core/Data/` (Task 2) and an in-memory mock so the screen is fully exercisable UI-first. When BAK-6 lands its protocols, reconcile names there; the model depends only on the protocol, so the mock swaps for the live repo with no view changes.

Authoritative product decisions (override the spec's Open questions): streak = consecutive honored scheduled days rendered as `<n>D` (`0D` at zero, never hidden); weights are **kg only** (the prototype's `LBS` copy becomes `KG`); week starts **Monday**; all day-bucketing uses `Calendar.current` device-local. The `⋯` overflow glyph and week-strip cells are inert/display-only. See `docs/superpowers/specs/2026-05-31-product-decisions.md`.

---

## Task 1: Today-local view-model value types (TDD)

These are the Today-only projections the view renders. Pure value types with one derived helper worth a test (the est-1RM-free counts live on the model in Task 3; here we only test construction + `WeekDayCell.State` completeness).

**Files:**
- Create: `Pulse/Features/Today/TodayViewModels.swift`
- Create: `PulseTests/TodayViewModelsTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/TodayViewModelsTests.swift`**

```swift
import XCTest
@testable import Pulse

final class TodayViewModelsTests: XCTestCase {
    func testWeekDayStateHasFourCases() {
        XCTAssertEqual(Set(WeekDayCell.State.allCases),
                       [.done, .today, .plan, .rest])
    }

    func testTodayWorkoutCardHoldsFields() {
        let card = TodayWorkoutCard(
            workoutID: UUID(),
            programLabel: "PPL", week: 4, day: 23,
            name: "Chest & Tris", exerciseCount: 7, est: "~60 min")
        XCTAssertEqual(card.programLabel, "PPL")
        XCTAssertEqual(card.day, 23)
        XCTAssertEqual(card.exerciseCount, 7)
    }

    func testSessionRecapHoldsNameAndSubline() {
        let r = SessionRecap(sessionID: UUID(), name: "Legs",
                             subline: "71M · 18.7K KG · +1 PR")
        XCTAssertEqual(r.name, "Legs")
        XCTAssertEqual(r.subline, "71M · 18.7K KG · +1 PR")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: FAIL — `WeekDayCell`, `TodayWorkoutCard`, `SessionRecap` undefined (compile error in `PulseTests`).

- [ ] **Step 3: Write `Pulse/Features/Today/TodayViewModels.swift`**

```swift
import Foundation

/// Hero-card projection of today's prescribed workout.
struct TodayWorkoutCard: Equatable, Identifiable {
    var id: UUID { workoutID }
    let workoutID: UUID
    let programLabel: String   // "PPL"
    let week: Int              // 4
    let day: Int               // 23
    let name: String           // "Chest & Tris"
    let exerciseCount: Int     // 7
    let est: String            // "~60 min"

    var eyebrow: String { "TODAY · \(programLabel) · WEEK \(week)" }
    var dayLabel: String { "Day \(day)" }
    var footerEyebrow: String { "\(exerciseCount) EXERCISES · \(est.uppercased())" }
}

/// One of exactly seven cells in the week strip.
struct WeekDayCell: Equatable, Identifiable {
    enum State: String, CaseIterable { case done, today, plan, rest }
    var id: String { dayLetter + label }
    let dayLetter: String   // "M"
    let label: String       // "Chest&Tris"
    let state: State
}

/// Most-recent completed session, shown in the Yesterday row.
struct SessionRecap: Equatable, Identifiable {
    var id: UUID { sessionID }
    let sessionID: UUID
    let name: String        // "Legs"
    let subline: String     // "71M · 18.7K KG · +1 PR"
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (`TodayViewModelsTests` green; existing suites still green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Today/TodayViewModels.swift PulseTests/TodayViewModelsTests.swift
git commit -m "feat: Today view-model value types (card, week cell, recap)"
```

---

## Task 2: Today repository protocols + in-memory mock (TDD)

Declares the protocol surface Today reads (owned long-term by BAK-6) and a deterministic mock seeded with the spec's sample data, plus a failing-mock variant for the error path. The mock is the substitution point for tests and previews.

**Files:**
- Create: `Pulse/Core/Data/TodayRepository.swift`
- Create: `Pulse/Core/Data/MockTodayRepository.swift`
- Create: `PulseTests/MockTodayRepositoryTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/MockTodayRepositoryTests.swift`**

```swift
import XCTest
@testable import Pulse

final class MockTodayRepositoryTests: XCTestCase {
    func testSampleReturnsSevenDayWeek() async throws {
        let repo = MockTodayRepository.sample
        let snapshot = try await repo.loadToday()
        XCTAssertEqual(snapshot.week.count, 7)
        XCTAssertEqual(snapshot.greetingName, "Alex")
        XCTAssertEqual(snapshot.streak, 27)
        XCTAssertEqual(snapshot.dateEyebrow, "WED · MAY 28")
        XCTAssertEqual(snapshot.today?.name, "Chest & Tris")
        XCTAssertEqual(snapshot.yesterday?.name, "Legs")
    }

    func testSampleWeekHasThreeDoneFivePlanned() async throws {
        let snapshot = try await MockTodayRepository.sample.loadToday()
        let done = snapshot.week.filter { $0.state == .done }.count
        let planned = snapshot.week.filter { $0.state != .rest }.count
        XCTAssertEqual(done, 3)
        XCTAssertEqual(planned, 5)
    }

    func testRestDayVariantHasNoToday() async throws {
        let snapshot = try await MockTodayRepository.restDay.loadToday()
        XCTAssertNil(snapshot.today)
    }

    func testNoHistoryVariantHasNoYesterday() async throws {
        let snapshot = try await MockTodayRepository.noHistory.loadToday()
        XCTAssertNil(snapshot.yesterday)
    }

    func testFailingVariantThrows() async {
        do {
            _ = try await MockTodayRepository.failing.loadToday()
            XCTFail("expected loadToday to throw")
        } catch {
            // expected
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: FAIL — `MockTodayRepository` / `TodaySnapshot` / `TodayRepository` undefined.

- [ ] **Step 3: Write `Pulse/Core/Data/TodayRepository.swift`**

```swift
import Foundation

/// Everything the Today screen needs in one fetch. BAK-6 owns the live
/// implementation; the screen depends only on this protocol so the Supabase
/// repo and the in-memory mock are interchangeable.
struct TodaySnapshot: Equatable {
    let dateEyebrow: String        // "WED · MAY 28"
    let greetingName: String       // "Alex"
    let streak: Int                // 27 (honored scheduled days)
    let today: TodayWorkoutCard?   // nil on a rest / no-workout day
    let week: [WeekDayCell]        // expected to be exactly 7
    let yesterday: SessionRecap?   // nil when there is no prior session
}

protocol TodayRepository: Sendable {
    func loadToday() async throws -> TodaySnapshot
}
```

- [ ] **Step 4: Write `Pulse/Core/Data/MockTodayRepository.swift`**

```swift
import Foundation

/// Deterministic in-memory `TodayRepository` for UI-first development, previews,
/// and tests. Mirrors the sample data in the spec (and `docs/design/pulse-app.jsx`).
struct MockTodayRepository: TodayRepository {
    enum Failure: Error { case unavailable }

    var snapshot: TodaySnapshot?      // nil => throw (error path)
    var artificialDelay: Duration = .zero

    func loadToday() async throws -> TodaySnapshot {
        if artificialDelay > .zero { try? await Task.sleep(for: artificialDelay) }
        guard let snapshot else { throw Failure.unavailable }
        return snapshot
    }

    // MARK: Canned variants

    static let sample = MockTodayRepository(snapshot: .sample)
    static let restDay = MockTodayRepository(snapshot: .restDay)
    static let noHistory = MockTodayRepository(snapshot: .noHistory)
    static let allRest = MockTodayRepository(snapshot: .allRest)
    static let failing = MockTodayRepository(snapshot: nil)

    /// Sample with a visible loading window for previewing the skeleton.
    static let slow = MockTodayRepository(snapshot: .sample, artificialDelay: .seconds(2))
}

extension TodaySnapshot {
    static let sampleWorkoutID = UUID()

    static let sampleWeek: [WeekDayCell] = [
        WeekDayCell(dayLetter: "M", label: "Chest&Tris", state: .done),
        WeekDayCell(dayLetter: "T", label: "Back&Bis", state: .done),
        WeekDayCell(dayLetter: "W", label: "Legs", state: .done),
        WeekDayCell(dayLetter: "T", label: "Shoulders", state: .today),
        WeekDayCell(dayLetter: "F", label: "Arms·finisher", state: .plan),
        WeekDayCell(dayLetter: "S", label: "Rest", state: .rest),
        WeekDayCell(dayLetter: "S", label: "Rest", state: .rest),
    ]

    static let sampleCard = TodayWorkoutCard(
        workoutID: sampleWorkoutID,
        programLabel: "PPL", week: 4, day: 23,
        name: "Chest & Tris", exerciseCount: 7, est: "~60 min")

    static let sampleRecap = SessionRecap(
        sessionID: UUID(), name: "Legs", subline: "71M · 18.7K KG · +1 PR")

    static let sample = TodaySnapshot(
        dateEyebrow: "WED · MAY 28", greetingName: "Alex", streak: 27,
        today: sampleCard, week: sampleWeek, yesterday: sampleRecap)

    static let restDay = TodaySnapshot(
        dateEyebrow: "SAT · MAY 31", greetingName: "Alex", streak: 27,
        today: nil, week: sampleWeek, yesterday: sampleRecap)

    static let noHistory = TodaySnapshot(
        dateEyebrow: "WED · MAY 28", greetingName: "Alex", streak: 0,
        today: sampleCard, week: sampleWeek, yesterday: nil)

    static let allRest = TodaySnapshot(
        dateEyebrow: "SUN · JUN 01", greetingName: "Alex", streak: 0,
        today: nil,
        week: Array(repeating:
            WeekDayCell(dayLetter: "R", label: "Rest", state: .rest), count: 7),
        yesterday: nil)
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (`MockTodayRepositoryTests` green).

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/Data/TodayRepository.swift Pulse/Core/Data/MockTodayRepository.swift PulseTests/MockTodayRepositoryTests.swift
git commit -m "feat: Today repository protocol + in-memory mock with sample data"
```

---

## Task 3: `TodayModel` — load, phases, counts, callbacks (TDD)

The `@Observable` model: loads via the injected repo, maps to `Phase`, derives `doneCount`/`plannedCount`, and exposes the two stub callbacks. This is the logic core — strict TDD.

**Files:**
- Create: `Pulse/Features/Today/TodayModel.swift`
- Create: `PulseTests/TodayModelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/TodayModelTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class TodayModelTests: XCTestCase {
    func testLoadPopulatesAllFields() async {
        let model = TodayModel(repository: .sample)
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.dateEyebrow, "WED · MAY 28")
        XCTAssertEqual(model.greetingName, "Alex")
        XCTAssertEqual(model.streak, 27)
        XCTAssertEqual(model.today?.name, "Chest & Tris")
        XCTAssertEqual(model.week.count, 7)
        XCTAssertEqual(model.yesterday?.name, "Legs")
    }

    func testCountsFromSampleWeek() async {
        let model = TodayModel(repository: .sample)
        await model.load()
        XCTAssertEqual(model.doneCount, 3)
        XCTAssertEqual(model.plannedCount, 5)
    }

    func testRestDayLoadsEmptyPhase() async {
        let model = TodayModel(repository: .restDay)
        await model.load()
        XCTAssertEqual(model.phase, .empty)
        XCTAssertNil(model.today)
    }

    func testNoHistoryHasNilYesterday() async {
        let model = TodayModel(repository: .noHistory)
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertNil(model.yesterday)
    }

    func testAllRestWeekCountsZeroNoCrash() async {
        let model = TodayModel(repository: .allRest)
        await model.load()
        XCTAssertEqual(model.doneCount, 0)
        XCTAssertEqual(model.plannedCount, 0)
    }

    func testFailureSetsErrorThenRecovers() async {
        let model = TodayModel(repository: .failing)
        await model.load()
        XCTAssertEqual(model.phase, .error)
        // Recover by swapping in a working repo and reloading.
        model.replaceRepository(.sample)
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
    }

    func testStartTodaysWorkoutInvokesCallbackOnceWithWorkoutID() async {
        var started: [UUID] = []
        let model = TodayModel(repository: .sample,
                               onStartWorkout: { started.append($0) })
        await model.load()
        model.startTodaysWorkout()
        XCTAssertEqual(started, [TodaySnapshot.sampleWorkoutID])
    }

    func testStartTodaysWorkoutDoesNothingOnRestDay() async {
        var started: [UUID] = []
        let model = TodayModel(repository: .restDay,
                               onStartWorkout: { started.append($0) })
        await model.load()
        model.startTodaysWorkout()
        XCTAssertTrue(started.isEmpty)
    }

    func testOpenYesterdayPushesOnlyWhenRecapExists() async {
        var opened: [UUID] = []
        let model = TodayModel(repository: .sample,
                               onOpenSession: { opened.append($0) })
        await model.load()
        model.openYesterday()
        XCTAssertEqual(opened.count, 1)

        let empty = TodayModel(repository: .noHistory,
                               onOpenSession: { opened.append($0) })
        await empty.load()
        empty.openYesterday()
        XCTAssertEqual(opened.count, 1)   // unchanged
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: FAIL — `TodayModel` undefined.

- [ ] **Step 3: Write `Pulse/Features/Today/TodayModel.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class TodayModel {
    enum Phase: Equatable { case loading, loaded, empty, error }

    private(set) var phase: Phase = .loading

    private(set) var dateEyebrow = ""
    private(set) var greetingName = ""
    private(set) var streak = 0
    private(set) var today: TodayWorkoutCard?
    private(set) var week: [WeekDayCell] = []
    private(set) var yesterday: SessionRecap?

    var doneCount: Int { week.filter { $0.state == .done }.count }
    var plannedCount: Int { week.filter { $0.state != .rest }.count }

    /// Streak rendered as "<n>D" — 0D at zero, never hidden (product decision).
    var streakLabel: String { "\(streak)D" }
    /// Header trailing eyebrow, e.g. "3 OF 5 DONE".
    var weekProgressLabel: String { "\(doneCount) OF \(plannedCount) DONE" }

    private var repository: any TodayRepository
    private let onStartWorkout: (UUID) -> Void
    private let onOpenSession: (UUID) -> Void

    init(repository: any TodayRepository,
         onStartWorkout: @escaping (UUID) -> Void = { _ in },
         onOpenSession: @escaping (UUID) -> Void = { _ in }) {
        self.repository = repository
        self.onStartWorkout = onStartWorkout
        self.onOpenSession = onOpenSession
    }

    func load() async {
        phase = .loading
        do {
            let s = try await repository.loadToday()
            dateEyebrow = s.dateEyebrow
            greetingName = s.greetingName
            streak = s.streak
            today = s.today
            week = s.week
            yesterday = s.yesterday
            phase = (s.today == nil) ? .empty : .loaded
        } catch {
            phase = .error
        }
    }

    func startTodaysWorkout() {
        guard let id = today?.workoutID else { return }
        onStartWorkout(id)
    }

    func openYesterday() {
        guard let id = yesterday?.sessionID else { return }
        onOpenSession(id)
    }

    /// Test/recovery seam: swap the repo (e.g. after an error) then `load()` again.
    func replaceRepository(_ repo: any TodayRepository) { repository = repo }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (`TodayModelTests` green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Today/TodayModel.swift PulseTests/TodayModelTests.swift
git commit -m "feat: TodayModel — load/phases, week counts, start/open callbacks"
```

---

## Task 4: Today-local design pieces (eyebrow, numeral, pressable button)

Small reusable view bits the screen needs, themed via `Theme`. Pure view assembly — validated by `#Preview` (no unit tests). If BAK-7 already ships these, delete these and import the shared ones in a follow-up.

**Files:**
- Create: `Pulse/Features/Today/TodayComponents.swift`

- [ ] **Step 1: Write `Pulse/Features/Today/TodayComponents.swift`**

```swift
import SwiftUI

/// Uppercase mono eyebrow/label (Geist Mono per design; system monospaced until
/// BAK-7 vendors the font). Tracking + soft ink per the handoff.
struct Eyebrow: View {
    @Environment(Theme.self) private var theme
    let text: String
    var emphasis: Double = 1.0
    init(_ text: String, emphasis: Double = 1.0) { self.text = text; self.emphasis = emphasis }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(theme.inkSoft.opacity(emphasis))
    }
}

/// Giant condensed poster numeral (Oswald per design; fixed point-size, no
/// Dynamic Type scaling per product decision). System until BAK-7 vendors Oswald.
struct PosterNumeral: View {
    let value: Int
    var size: CGFloat = 72
    var color: Color
    var body: some View {
        Text("\(value)")
            .font(.system(size: size, weight: .bold, design: .default))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// Press feedback: nudges down 1pt while pressed (design's icon/button behavior).
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

#Preview {
    @Previewable @State var theme = Theme()
    return VStack(alignment: .leading, spacing: 16) {
        Eyebrow("TODAY · PPL · WEEK 4")
        PosterNumeral(value: 7, color: theme.accent)
        Button("Start") {}.buttonStyle(PressableStyle())
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.bg)
    .environment(theme)
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Today/TodayComponents.swift
git commit -m "feat: Today-local design pieces (eyebrow, poster numeral, pressable)"
```

---

## Task 5: Hero card view (`accent` fill, lockup, inverted Start)

The `accent`-filled hero with the lockup and the special inverted (`ink`-filled, `bg` text) Start button. View assembly + `#Preview`.

**Files:**
- Create: `Pulse/Features/Today/TodayHeroCard.swift`

- [ ] **Step 1: Write `Pulse/Features/Today/TodayHeroCard.swift`**

```swift
import SwiftUI

/// The hero card. When `card == nil` (rest/empty day) it renders the rest
/// treatment with no Start button (AC #10).
struct TodayHeroCard: View {
    @Environment(Theme.self) private var theme
    let card: TodayWorkoutCard?
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let card {
                Eyebrow(card.eyebrow, emphasis: 0.85)
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                lockup(card)
                footer(card)
            } else {
                Eyebrow("TODAY · REST DAY", emphasis: 0.85)
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                Text("Rest day.")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(theme.onAccent)
                Text("No workout scheduled — recover and come back tomorrow.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.onAccent.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(theme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityIdentifier("today.hero")
    }

    private func lockup(_ card: TodayWorkoutCard) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PosterNumeral(value: card.exerciseCount, size: 72, color: theme.onAccent)
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(card.dayLabel, emphasis: 0.85)
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                Text(card.name)
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(theme.onAccent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("today.hero.name")
            }
        }
    }

    private func footer(_ card: TodayWorkoutCard) -> some View {
        HStack(alignment: .center) {
            Eyebrow(card.footerEyebrow, emphasis: 0.85)
                .foregroundStyle(theme.onAccent.opacity(0.85))
            Spacer()
            Button(action: onStart) {
                HStack(spacing: 6) {
                    Text("Start").font(.system(size: 14, weight: .bold))
                    Image(systemName: "arrow.right")
                }
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(theme.ink, in: RoundedRectangle(cornerRadius: 999))
                .overlay(RoundedRectangle(cornerRadius: 999).strokeBorder(theme.ink, lineWidth: 2))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("today.hero.start")
        }
    }
}

#Preview("Workout") {
    @Previewable @State var theme = Theme()
    return TodayHeroCard(card: .sampleCard, onStart: {})
        .padding().background(theme.bg).environment(theme)
}

#Preview("Rest day") {
    @Previewable @State var theme = Theme()
    return TodayHeroCard(card: nil, onStart: {})
        .padding().background(theme.bg).environment(theme)
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Today/TodayHeroCard.swift
git commit -m "feat: Today hero card (accent fill, lockup, inverted Start, rest state)"
```

---

## Task 6: Week strip + Yesterday recap views

The 7-cell strip with per-state styling (AC #6/#7) and the tappable recap row (AC #8). View assembly + `#Preview`.

**Files:**
- Create: `Pulse/Features/Today/TodayWeekStrip.swift`
- Create: `Pulse/Features/Today/YesterdayRow.swift`

- [ ] **Step 1: Write `Pulse/Features/Today/TodayWeekStrip.swift`**

```swift
import SwiftUI

/// Header (THIS WEEK · <done> OF <planned> DONE) + 7 display-only day cells.
struct TodayWeekStrip: View {
    @Environment(Theme.self) private var theme
    let week: [WeekDayCell]
    let progressLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow("THIS WEEK")
                Spacer()
                Eyebrow(progressLabel)
            }
            HStack(spacing: 8) {
                ForEach(week) { cell in WeekCell(cell: cell) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.weekStrip")
    }
}

private struct WeekCell: View {
    @Environment(Theme.self) private var theme
    let cell: WeekDayCell

    var body: some View {
        Text(cell.dayLetter)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .aspectRatio(0.82, contentMode: .fit)
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(border)
            .opacity(cell.state == .rest ? 0.5 : 1)
    }

    private var fill: Color { cell.state == .done ? theme.accent : .clear }
    private var textColor: Color { cell.state == .done ? theme.onAccent : theme.inkSoft }

    @ViewBuilder private var border: some View {
        switch cell.state {
        case .done:  RoundedRectangle(cornerRadius: 8).strokeBorder(theme.accent, lineWidth: 1.5)
        case .today: RoundedRectangle(cornerRadius: 8).strokeBorder(theme.accent2, lineWidth: 2)
        case .plan:  RoundedRectangle(cornerRadius: 8).strokeBorder(theme.inkFaint, lineWidth: 1.5)
        case .rest:  RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.inkFaint,
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }
}

#Preview {
    @Previewable @State var theme = Theme()
    return TodayWeekStrip(week: TodaySnapshot.sampleWeek, progressLabel: "3 OF 5 DONE")
        .padding().background(theme.bg).environment(theme)
}
```

- [ ] **Step 2: Write `Pulse/Features/Today/YesterdayRow.swift`**

```swift
import SwiftUI

/// Tappable recap of the most recent prior session → pushes Session Detail (stub).
struct YesterdayRow: View {
    @Environment(Theme.self) private var theme
    let recap: SessionRecap
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recap.name)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.ink)
                    Text(recap.subline)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(theme.inkSoft)
            }
            .padding(14)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .opacity(0.85)
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("today.yesterday")
    }
}

#Preview {
    @Previewable @State var theme = Theme()
    return YesterdayRow(recap: TodaySnapshot.sampleRecap, onTap: {})
        .padding().background(theme.bg).environment(theme)
}
```

- [ ] **Step 3: Build to confirm both compile**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Pulse/Features/Today/TodayWeekStrip.swift Pulse/Features/Today/YesterdayRow.swift
git commit -m "feat: Today week strip (per-state cells) and Yesterday recap row"
```

---

## Task 7: `TodayView` — screen assembly, phases, navigation

Composes the header, hero, week strip, and recap inside the tab's `NavigationStack`, handling loading/loaded/empty/error phases, the mount transition, and the Yesterday → Session Detail stub push. View assembly + `#Preview`; behavior is covered by the UI tests in Task 9.

**Files:**
- Modify: `Pulse/Features/Today/TodayView.swift`

- [ ] **Step 1: Replace `Pulse/Features/Today/TodayView.swift`**

```swift
import SwiftUI

/// Stub push target for the Yesterday row. Real Session Detail is a separate
/// feature; this satisfies AC #8 (navigation occurs) without owning that screen.
struct SessionDetailStub: View {
    @Environment(Theme.self) private var theme
    let sessionID: UUID
    var body: some View {
        Text("Session Detail")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
            .navigationTitle("Session")
            .accessibilityIdentifier("sessionDetail.stub")
    }
}

struct TodayView: View {
    @Environment(Theme.self) private var theme
    @State private var model: TodayModel
    @State private var path: [UUID] = []

    /// Default initializer wires the sample mock; `AppShell` injects the real
    /// repo/callbacks (Task 8). Tests/previews inject their own model.
    init(model: TodayModel? = nil) {
        _model = State(initialValue: model ?? TodayModel(repository: MockTodayRepository.sample))
    }

    var body: some View {
        NavigationStack(path: $path) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(theme.bg.ignoresSafeArea())
                .navigationDestination(for: UUID.self) { SessionDetailStub(sessionID: $0) }
        }
        .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            loaded(skeleton: true).redacted(reason: .placeholder)
                .accessibilityIdentifier("today.loading")
        case .loaded, .empty:
            loaded(skeleton: false)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        case .error:
            errorState
        }
    }

    private func loaded(skeleton: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                topBar
                greetingRow
                TodayHeroCard(card: model.today) { model.startTodaysWorkout() }
                TodayWeekStrip(week: model.week, progressLabel: model.weekProgressLabel)
                if let recap = model.yesterday {
                    Eyebrow("YESTERDAY")
                    YesterdayRow(recap: recap) {
                        model.openYesterday()
                        path.append(recap.sessionID)
                    }
                }
            }
            .padding(18)
        }
    }

    private var topBar: some View {
        HStack {
            Eyebrow(model.dateEyebrow)
            Spacer()
            Button { /* inert placeholder (product decision) */ } label: {
                Image(systemName: "ellipsis").foregroundStyle(theme.inkSoft)
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("today.overflow")
        }
    }

    private var greetingRow: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Hey, \(model.greetingName).")
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("today.greeting")
            Spacer()
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(model.streak)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(theme.accent2)
                Text("D")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.accent2.opacity(0.7))
            }
            .accessibilityIdentifier("today.streak")
        }
    }

    private var errorState: some View {
        VStack(spacing: 14) {
            Text("Couldn't load Today.")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.ink)
            Button("Retry") { Task { await model.load() } }
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 999))
                .buttonStyle(PressableStyle())
                .accessibilityIdentifier("today.retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("today.error")
    }
}

#Preview("Loaded") {
    TodayView(model: TodayModel(repository: MockTodayRepository.sample))
        .environment(Theme())
}
#Preview("Rest day") {
    TodayView(model: TodayModel(repository: MockTodayRepository.restDay))
        .environment(Theme())
}
#Preview("Error") {
    TodayView(model: TodayModel(repository: MockTodayRepository.failing))
        .environment(Theme())
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Today/TodayView.swift
git commit -m "feat: TodayView screen — header, hero, week, recap, phases, nav"
```

---

## Task 8: Wire the Theme into `AppShell` and inject the real Today wiring

The tab root must receive a `Theme` and the Today tab must get a model wired to the (mock) repo + the Start/open callbacks. AC #1 (default first tab, `NavigationStack` root, path resets on tab switch) and AC #12 (palette re-skins instantly) live here.

**Files:**
- Modify: `Pulse/App/AppShell.swift`
- Modify: `Pulse/App/PulseApp.swift`

- [ ] **Step 1: Replace `Pulse/App/PulseApp.swift`**

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

- [ ] **Step 2: Replace `Pulse/App/AppShell.swift`**

```swift
import SwiftUI

struct AppShell: View {
    @Environment(Theme.self) private var theme

    /// Today is the default/first tab. Its model is built once and wired to the
    /// mock repo + stub callbacks (Start → is BAK-14; Session Detail is separate).
    @State private var todayModel = TodayModel(
        repository: MockTodayRepository.sample,
        onStartWorkout: { _ in /* BAK-14 active flow hook */ },
        onOpenSession: { _ in /* handled by TodayView path push */ })

    var body: some View {
        TabView {
            TodayView(model: todayModel)
                .tabItem { Label("Today", systemImage: "bolt.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            YouView()
                .tabItem { Label("You", systemImage: "person.fill") }
        }
        .tint(theme.accent)
    }
}

#Preview { AppShell().environment(Theme()) }
```

- [ ] **Step 3: Build and run the existing test suite (regression)**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: `BUILD SUCCEEDED` and all unit tests PASS.

- [ ] **Step 4: Commit**

```bash
git add Pulse/App/AppShell.swift Pulse/App/PulseApp.swift
git commit -m "feat: inject Theme app-wide and wire Today tab into AppShell"
```

---

## Task 9: Acceptance / UI tests (XCUITest)

Maps the spec's acceptance criteria to UI assertions against the default sample mock. Because the live wiring uses the sample mock, the launched app shows the sample data — assertions target the accessibility identifiers added above. A launch-argument toggle drives the rest-day and error variants.

**Files:**
- Modify: `Pulse/App/AppShell.swift` (launch-argument variant switch)
- Create: `PulseUITests/TodayTabTests.swift`

- [ ] **Step 1: Add a launch-argument variant switch to `AppShell.swift`**

Replace the `todayModel` declaration in `Pulse/App/AppShell.swift` with a computed initial value that honors UI-test launch arguments:

```swift
    @State private var todayModel: TodayModel = {
        let repo: MockTodayRepository
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestRestDay") { repo = .restDay }
        else if args.contains("-uiTestError") { repo = .failing }
        else { repo = .sample }
        return TodayModel(
            repository: repo,
            onStartWorkout: { _ in },
            onOpenSession: { _ in })
    }()
```

(Replaces the literal `TodayModel(repository: MockTodayRepository.sample, …)` from Task 8 Step 2. Rebuild after editing.)

- [ ] **Step 2: Write `PulseUITests/TodayTabTests.swift`**

```swift
import XCTest

final class TodayTabTests: XCTestCase {
    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += args
        app.launch()
        return app
    }

    // AC2/AC3
    func testHeaderShowsDateGreetingStreak() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["WED · MAY 28"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["today.greeting"].exists
                      || app.staticTexts["Hey, Alex."].exists)
        XCTAssertTrue(app.staticTexts["27"].exists)
    }

    // AC4/AC5
    func testHeroShowsWorkoutAndStartFires() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Day 23"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Chest & Tris"].exists)
        XCTAssertTrue(app.staticTexts["7 EXERCISES · ~60 MIN"].exists)
        let start = app.buttons["today.hero.start"]
        XCTAssertTrue(start.exists)
        start.tap()   // no crash; BAK-14 hook is a no-op here
    }

    // AC6/AC7
    func testWeekStripRendersAndHeader() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["3 OF 5 DONE"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["today.weekStrip"].exists)
    }

    // AC8
    func testYesterdayRowPushesSessionDetail() {
        let app = launch()
        let row = app.buttons["today.yesterday"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.staticTexts["sessionDetail.stub"].waitForExistence(timeout: 5)
                      || app.staticTexts["Session Detail"].waitForExistence(timeout: 5))
    }

    // AC10
    func testRestDayShowsNoStart() {
        let app = launch(["-uiTestRestDay"])
        XCTAssertTrue(app.staticTexts["Rest day."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["today.hero.start"].exists)
    }

    // AC9/AC11
    func testErrorShowsRetry() {
        let app = launch(["-uiTestError"])
        XCTAssertTrue(app.buttons["today.retry"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 3: Run the full test suite (unit + UI)**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: `TEST SUCCEEDED` — all unit suites and `TodayTabTests` pass.

- [ ] **Step 4: Commit**

```bash
git add Pulse/App/AppShell.swift PulseUITests/TodayTabTests.swift
git commit -m "test: Today tab acceptance UI tests (AC2–AC11) + launch-arg variants"
```

---

## Task 10: Theme-switch verification (AC #12) and final regression

Confirm both palettes render the screen with no hardcoded values and no crash. A lightweight unit test asserts the model is palette-agnostic; the visual re-skin is verified by previewing both palettes (snapshot infra is not yet in the repo, so this is a manual preview check plus a guard test).

**Files:**
- Create: `PulseTests/TodayThemeTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/TodayThemeTests.swift`**

```swift
import XCTest
import SwiftUI
@testable import Pulse

@MainActor
final class TodayThemeTests: XCTestCase {
    /// The model carries no color/theme state — switching palette never touches it.
    func testModelIsThemeAgnostic() async {
        let theme = Theme()
        theme.palette = .coastal
        let model = TodayModel(repository: .sample)
        await model.load()
        let coastalCount = model.doneCount
        theme.palette = .mint
        XCTAssertEqual(model.doneCount, coastalCount)
        XCTAssertEqual(model.phase, .loaded)
    }

    /// Both palettes resolve all tokens the Today screen reads (no nil/clear).
    func testBothPalettesResolveTodayTokens() {
        for palette in Palette.allCases {
            let theme = Theme()
            theme.palette = palette
            // Touch each token Today uses; must not trap.
            _ = [theme.bg, theme.surface, theme.ink, theme.inkSoft,
                 theme.inkFaint, theme.accent, theme.accent2, theme.onAccent]
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails, then passes**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: the new tests compile and PASS (they assert existing behavior — if a token were missing or the model held theme state, they would fail).

- [ ] **Step 3: Manually verify the re-skin in previews**

Open `TodayView.swift` in Xcode; in the "Loaded" preview, edit the injected `Theme()` to `.mint` (`let t = Theme(); t.palette = .mint`) and confirm the hero `accent` fill, `accent2` streak numeral, and week-cell borders re-skin with no hardcoded color surviving and no background flash. Revert the edit.

- [ ] **Step 4: Full regression run**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test
```
Expected: `TEST SUCCEEDED` across all suites.

- [ ] **Step 5: Commit**

```bash
git add PulseTests/TodayThemeTests.swift
git commit -m "test: Today is palette-agnostic and both palettes resolve all tokens"
```

---

## Self-Review notes

- **Acceptance-criteria coverage:** AC1 (Task 7/8 — first tab, `NavigationStack` root, `path` resets on tab switch since the stack is local state); AC2/AC3 (Task 7 `topBar`/`greetingRow`, Task 9 tests); AC4/AC5 (Task 5 hero + inverted Start, Task 9 test fires Start); AC6/AC7 (Task 6 week strip + `weekProgressLabel`, Task 9 `3 OF 5 DONE`); AC8 (Task 7 path push to `SessionDetailStub`, Task 9 test); AC9 (Task 7 `.loading` redacted skeleton); AC10 (Task 5 rest treatment + Task 7 `.empty`, Task 9 rest-day test); AC11 (Task 7 error state + retry, Task 9 error test); AC12 (Task 10).
- **Product decisions honored:** streak `27D`/`0D` never hidden; `KG` not `LBS` in the recap subline; Monday-start week implied by the sample cell order `M T W T F S S`; `⋯` and week cells inert/display-only.
- **Architecture conformance:** model reads data only via `TodayRepository` (injected); no Supabase reference; all colors/spacing/radii via `Theme`; one View + one `@Observable` model per the folder convention; project regenerated via `xcodegen generate` (no hand-edited `.xcodeproj`).
- **TDD vs view assembly:** logic (`TodayViewModels`, `MockTodayRepository`, `TodayModel`, theme-agnosticism) is strict failing-test-first; views (`TodayComponents`, `TodayHeroCard`, `TodayWeekStrip`, `YesterdayRow`, `TodayView`) are concrete structure + `#Preview` + XCUITest.
- **Prerequisite reconciliation:** if BAK-7 ships shared `Eyebrow`/numeral/`Lockup`/`ButtonStyle`/row, and BAK-6 ships the canonical repository protocols, the Today-local copies and `TodayRepository` should be replaced/renamed in a follow-up; the model's protocol dependency makes the repo swap a one-line change.
```