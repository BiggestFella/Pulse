# Stats (BAK-15) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Models/helpers use strict TDD (failing test → run → minimal impl → run → commit); pure view assembly is validated by `#Preview` + an XCUITest.

**Goal:** Build the read-only **Stats** screen — a stack screen pushed from the You tab — that summarizes training output over a selectable range: a hero volume card with a 12-bar trend chart, a 2×2 sub-stat grid (Sessions / New PRs / Avg Time / Streak), and a horizontal "Volume by muscle" bar list. UI-first: the screen renders entirely against an in-memory mock repository before the real Supabase data layer (BAK-6) lands.

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. The screen is one `StatsView` + one `@Observable StatsModel` in `Pulse/Features/Stats/`. The model holds a `phase: LoadPhase` state machine (`.loading/.loaded/.empty/.error`) and talks only to a `StatsRepository` protocol (defined here, mock-backed; real impl deferred to BAK-6). Domain aggregates (`StatsSummary`, `VolumeByMuscle`) live in `Pulse/Core/Models`. All colors/spacing/typography come from `Theme` tokens injected via `.environment(Theme.self)`.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency (`async`/`await`), XCTest + XCUITest, XcodeGen.

---

## Prerequisites (verify before starting)

This feature depends on two foundation features being built first:

- **Design System (BAK-7)** — `Theme` tokens (`bg/surface/accent/accent2/onAccent/ink/inkSoft/inkFaint`, `spacing`, `radiusCard`, `radiusPill`), the vendored fonts (Hanken Grotesk / Oswald / Geist Mono) declared via `UIAppFonts`, and the shared components this screen reuses: `TopBar`, `Eyebrow`, `FilterChip`, `H1` styling. The current repo has `Theme`/`Palette` only; the shared components arrive with BAK-7.
- **Data layer (BAK-6)** — the repository protocol surface + the convention that views/models bind to protocols and in-memory mocks, never Supabase directly. This plan defines `StatsRepository` and a mock locally so Stats is buildable ahead of BAK-6; when BAK-6 lands, the protocol moves under its ownership behind the same signature and the live impl is swapped in.

**Authoritative product decisions** (from `docs/superpowers/specs/2026-05-31-product-decisions.md` — these override the spec's "Open questions"):
- **Units are kilograms only** for v1. Replace the prototype's `LBS` copy with `KG`. Keep weight/units formatting in one helper so a later toggle is localized.
- **PR = estimated 1RM via Epley**; `newPRs` for a range = count of records set within that range. Stats only *displays* the count produced by the analytics layer.
- **Streak = consecutive honored scheduled days.** The Streak stat shows the value computed by analytics; Stats does not recompute it.
- **Range bucketing:** 7D & 30D by day; 3M by week; YR & ALL by month. The mock returns a 12-element series per range regardless; bucketing math is BAK-6's job.
- **Trend for `ALL`** (no prior period): `volumeTrendPct` is `nil` → trend label renders `—`.

- [ ] **Step 0a: Confirm the project generates and the baseline builds**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 0b: Branch**

Run:
```bash
git switch -c feature/BAK-15-stats
```
Expected: `Switched to a new branch 'feature/BAK-15-stats'`.

- [ ] **Step 0c: Note on shared design components**

`TopBar`, `Eyebrow`, and `FilterChip` are owned by BAK-7. If they do not yet exist in `Pulse/Core/DesignSystem/` when you start, build Stats against the minimal local shims described in Task 6 (clearly marked `// BAK-7: replace with shared component`) so this feature stays unblocked. When BAK-7 lands, delete the shims and import the shared components — the call sites are identical.

---

## Task 1: Domain models — `StatsSummary` & `VolumeByMuscle` (TDD)

**Files:**
- Create: `Pulse/Core/Models/StatsModels.swift`
- Create: `PulseTests/Features/Stats/StatsModelsTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Features/Stats/StatsModelsTests.swift`**

```swift
import XCTest
@testable import Pulse

final class StatsModelsTests: XCTestCase {
    func testVolumeByMuscleIsIdentifiableAndEquatable() {
        let a = VolumeByMuscle(muscle: "Legs", value: 56_000, valueDisplay: "56k", pct: 1.0)
        let b = VolumeByMuscle(id: a.id, muscle: "Legs", value: 56_000, valueDisplay: "56k", pct: 1.0)
        XCTAssertEqual(a, b)
    }

    func testSummaryHoldsTwelveBarSeriesAndMuscleList() {
        let s = StatsSummary(
            volume: 184_000, volumeDisplay: "184K", volumeTrendPct: 12,
            volumeSeries: [40, 55, 52, 68, 72, 80, 60, 75, 72, 85, 90, 82],
            sessions: 21, sessionsPlanned: 22, newPRs: 4,
            avgTimeMinutes: 62, streakDays: 27,
            volumeByMuscle: [
                VolumeByMuscle(muscle: "Chest", value: 42_000, valueDisplay: "42k", pct: 0.95)
            ])
        XCTAssertEqual(s.volumeSeries.count, 12)
        XCTAssertEqual(s.volumeByMuscle.count, 1)
        XCTAssertEqual(s.sessionsPlanned, 22)
    }

    func testTrendPctIsOptionalForAllRange() {
        let s = StatsSummary(
            volume: 0, volumeDisplay: "0", volumeTrendPct: nil, volumeSeries: Array(repeating: 0, count: 12),
            sessions: 0, sessionsPlanned: 0, newPRs: 0, avgTimeMinutes: 0, streakDays: 0,
            volumeByMuscle: [])
        XCTAssertNil(s.volumeTrendPct)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/StatsModelsTests
```
Expected: FAIL — `StatsSummary` / `VolumeByMuscle` undefined (compile error).

- [ ] **Step 3: Write `Pulse/Core/Models/StatsModels.swift`**

```swift
import Foundation

/// One muscle's contribution to total volume over a range, for the
/// "Volume by muscle" bar list. `pct` is 0...1 relative to the max-volume muscle.
struct VolumeByMuscle: Identifiable, Equatable {
    var id = UUID()
    var muscle: String          // "Chest"
    var value: Int              // 42_000 (kg total)
    var valueDisplay: String    // "42k"
    var pct: Double             // 0...1 bar fill proportion
}

/// The aggregate rendered by the Stats screen for one selected range.
/// Produced by the analytics layer (BAK-6); Stats only displays it.
struct StatsSummary: Equatable {
    var volume: Int                 // total volume for the range (kg)
    var volumeDisplay: String       // "184K"
    var volumeTrendPct: Int?        // +12 → "+12% vs prev"; nil → "—" (e.g. ALL)
    var volumeSeries: [Int]         // exactly 12 bars, each 0...100 (% of max)
    var sessions: Int               // 21
    var sessionsPlanned: Int        // 22
    var newPRs: Int                 // 4
    var avgTimeMinutes: Int         // 62
    var streakDays: Int             // 27 (honored scheduled days)
    var volumeByMuscle: [VolumeByMuscle]
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/StatsModelsTests
```
Expected: PASS.

- [ ] **Step 5: Regenerate (new folders) and commit**

```bash
xcodegen generate
git add Pulse/Core/Models/StatsModels.swift PulseTests/Features/Stats/StatsModelsTests.swift project.yml
git commit -m "feat: StatsSummary and VolumeByMuscle domain models"
```

---

## Task 2: `StatsRange` enum (TDD)

**Files:**
- Create: `Pulse/Features/Stats/StatsRange.swift`
- Create: `PulseTests/Features/Stats/StatsRangeTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Features/Stats/StatsRangeTests.swift`**

```swift
import XCTest
@testable import Pulse

final class StatsRangeTests: XCTestCase {
    func testChipOrderIsSevenThirtyThreeMonthYearAll() {
        XCTAssertEqual(StatsRange.allCases, [.d7, .d30, .m3, .yr, .all])
    }

    func testChipLabels() {
        XCTAssertEqual(StatsRange.allCases.map(\.chipLabel),
                       ["7D", "30D", "3M", "YR", "ALL"])
    }

    func testEyebrowToken() {
        XCTAssertEqual(StatsRange.d30.eyebrowToken, "30D")
        XCTAssertEqual(StatsRange.all.eyebrowToken, "ALL")
    }

    func testDefaultIsThirtyDay() {
        XCTAssertEqual(StatsRange.defaultRange, .d30)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/StatsRangeTests
```
Expected: FAIL — `StatsRange` undefined.

- [ ] **Step 3: Write `Pulse/Features/Stats/StatsRange.swift`**

```swift
import Foundation

/// The five fixed time windows offered by the range-chip row.
enum StatsRange: CaseIterable, Hashable {
    case d7, d30, m3, yr, all

    static let defaultRange: StatsRange = .d30

    /// Pill label shown in the chip row.
    var chipLabel: String {
        switch self {
        case .d7:  return "7D"
        case .d30: return "30D"
        case .m3:  return "3M"
        case .yr:  return "YR"
        case .all: return "ALL"
        }
    }

    /// Token used in the hero eyebrow, e.g. "30D VOLUME · KG".
    var eyebrowToken: String { chipLabel }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/StatsRangeTests
```
Expected: PASS.

- [ ] **Step 5: Regenerate and commit**

```bash
xcodegen generate
git add Pulse/Features/Stats/StatsRange.swift PulseTests/Features/Stats/StatsRangeTests.swift project.yml
git commit -m "feat: StatsRange enum (7D/30D/3M/YR/ALL, default 30D)"
```

---

## Task 3: `StatsRepository` protocol + in-memory mock (TDD)

**Files:**
- Create: `Pulse/Core/Data/StatsRepository.swift`
- Create: `PulseTests/Features/Stats/MockStatsRepositoryTests.swift`

This defines the protocol Stats binds to and a deterministic mock seeded with the design's sample values. Other ranges return plausibly-scaled summaries so every chip renders content. A controllable failing variant supports the `.error`/`retry()` tests. (When BAK-6 lands, the protocol moves to its ownership behind the same signature.)

- [ ] **Step 1: Write the failing test `PulseTests/Features/Stats/MockStatsRepositoryTests.swift`**

```swift
import XCTest
@testable import Pulse

final class MockStatsRepositoryTests: XCTestCase {
    func testThirtyDaySummaryMatchesDesignSample() async throws {
        let repo = MockStatsRepository()
        let s = try await repo.summary(range: .d30)
        XCTAssertEqual(s.volumeDisplay, "184K")
        XCTAssertEqual(s.volumeTrendPct, 12)
        XCTAssertEqual(s.volumeSeries, [40, 55, 52, 68, 72, 80, 60, 75, 72, 85, 90, 82])
        XCTAssertEqual(s.sessions, 21)
        XCTAssertEqual(s.sessionsPlanned, 22)
        XCTAssertEqual(s.newPRs, 4)
        XCTAssertEqual(s.avgTimeMinutes, 62)
        XCTAssertEqual(s.streakDays, 27)
        XCTAssertEqual(s.volumeByMuscle.map(\.muscle),
                       ["Chest", "Back", "Legs", "Shoulders", "Arms"])
        XCTAssertEqual(s.volumeByMuscle.first { $0.muscle == "Legs" }?.value, 56_000)
    }

    func testEveryRangeReturnsTwelveBarsAndNonEmptyMuscles() async throws {
        let repo = MockStatsRepository()
        for range in StatsRange.allCases {
            let s = try await repo.summary(range: range)
            XCTAssertEqual(s.volumeSeries.count, 12, "\(range)")
            XCTAssertFalse(s.volumeByMuscle.isEmpty, "\(range)")
        }
    }

    func testAllRangeHasNilTrend() async throws {
        let repo = MockStatsRepository()
        let s = try await repo.summary(range: .all)
        XCTAssertNil(s.volumeTrendPct)
    }

    func testEmptyVariantReturnsZeroedSummary() async throws {
        let repo = MockStatsRepository(mode: .empty)
        let s = try await repo.summary(range: .d7)
        XCTAssertEqual(s.volume, 0)
        XCTAssertTrue(s.volumeByMuscle.isEmpty)
        XCTAssertEqual(s.volumeSeries, Array(repeating: 0, count: 12))
    }

    func testFailingVariantThrows() async {
        let repo = MockStatsRepository(mode: .failing)
        do {
            _ = try await repo.summary(range: .d30)
            XCTFail("expected throw")
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
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/MockStatsRepositoryTests
```
Expected: FAIL — `MockStatsRepository` / `StatsRepository` undefined.

- [ ] **Step 3: Write `Pulse/Core/Data/StatsRepository.swift`**

```swift
import Foundation

/// Source of pre-aggregated training stats for a range.
/// Stats binds to this protocol only — never to Supabase directly.
/// Real implementation lands with BAK-6 behind this same signature.
protocol StatsRepository: Sendable {
    func summary(range: StatsRange) async throws -> StatsSummary
}

/// Deterministic in-memory repository for UI-first development and tests.
/// Seeds the design's 30D sample; other ranges are scaled from it so every
/// chip renders real-looking content.
struct MockStatsRepository: StatsRepository {
    enum Mode { case populated, empty, failing }
    struct StatsError: Error {}

    let mode: Mode
    init(mode: Mode = .populated) { self.mode = mode }

    func summary(range: StatsRange) async throws -> StatsSummary {
        switch mode {
        case .failing: throw StatsError()
        case .empty:   return Self.emptySummary
        case .populated: return Self.populated(range)
        }
    }

    static let emptySummary = StatsSummary(
        volume: 0, volumeDisplay: "0", volumeTrendPct: nil,
        volumeSeries: Array(repeating: 0, count: 12),
        sessions: 0, sessionsPlanned: 0, newPRs: 0,
        avgTimeMinutes: 0, streakDays: 0, volumeByMuscle: [])

    /// The 30D design sample; other ranges scale volume/sessions off it.
    private static func populated(_ range: StatsRange) -> StatsSummary {
        let factor: Double
        let trend: Int?
        switch range {
        case .d7:  factor = 0.25;  trend = 8
        case .d30: factor = 1.0;   trend = 12
        case .m3:  factor = 2.9;   trend = 6
        case .yr:  factor = 11.5;  trend = -4
        case .all: factor = 18.0;  trend = nil   // no prior period to compare
        }

        let muscles: [(String, Int)] = [
            ("Chest", 42_000), ("Back", 38_000), ("Legs", 56_000),
            ("Shoulders", 22_000), ("Arms", 18_000),
        ]
        let scaled = muscles.map { ($0.0, Int(Double($0.1) * factor)) }
        let maxValue = scaled.map(\.1).max() ?? 1
        let byMuscle = scaled.map { name, value in
            VolumeByMuscle(
                muscle: name, value: value,
                valueDisplay: abbreviate(value),
                pct: Double(value) / Double(maxValue))
        }

        let totalVolume = Int(184_000 * factor)
        let sessions = Int((21.0 * factor).rounded())
        let planned  = Int((22.0 * factor).rounded())

        return StatsSummary(
            volume: totalVolume,
            volumeDisplay: abbreviateUpper(totalVolume),
            volumeTrendPct: trend,
            volumeSeries: [40, 55, 52, 68, 72, 80, 60, 75, 72, 85, 90, 82],
            sessions: sessions,
            sessionsPlanned: planned,
            newPRs: range == .all ? 38 : 4,
            avgTimeMinutes: 62,
            streakDays: 27,
            volumeByMuscle: byMuscle)
    }

    private static func abbreviate(_ v: Int) -> String {
        v >= 1_000 ? "\(v / 1_000)k" : "\(v)"
    }
    private static func abbreviateUpper(_ v: Int) -> String {
        if v >= 1_000_000 {
            return String(format: "%.1fM", Double(v) / 1_000_000)
        } else if v >= 1_000 {
            return "\(v / 1_000)K"
        }
        return "\(v)"
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/MockStatsRepositoryTests
```
Expected: PASS (the 30D sample asserts `184K`, the exact 12-bar series, and Legs = 56k).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Core/Data/StatsRepository.swift PulseTests/Features/Stats/MockStatsRepositoryTests.swift
git commit -m "feat: StatsRepository protocol + seeded in-memory mock"
```

---

## Task 4: `LoadPhase` shared state enum (TDD)

**Files:**
- Create: `Pulse/Core/Models/LoadPhase.swift`
- Create: `PulseTests/Core/LoadPhaseTests.swift`

A tiny shared enum used by sibling specs' models. If BAK-6 already provides it, skip this task and import it; the tests below double as the contract.

- [ ] **Step 1: Write the failing test `PulseTests/Core/LoadPhaseTests.swift`**

```swift
import XCTest
@testable import Pulse

final class LoadPhaseTests: XCTestCase {
    func testHasFourCases() {
        XCTAssertEqual(LoadPhase.loading, .loading)
        XCTAssertEqual(LoadPhase.loaded, .loaded)
        XCTAssertEqual(LoadPhase.empty, .empty)
        XCTAssertEqual(LoadPhase.error, .error)
    }

    func testEquatable() {
        XCTAssertNotEqual(LoadPhase.loading, .loaded)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/LoadPhaseTests
```
Expected: FAIL — `LoadPhase` undefined.

- [ ] **Step 3: Write `Pulse/Core/Models/LoadPhase.swift`**

```swift
import Foundation

/// Coarse load state for read-only screens. Shared across feature models.
enum LoadPhase: Equatable {
    case loading   // first load or a range change is in flight
    case loaded    // populated content available
    case empty     // request succeeded but there is no data to show
    case error     // request failed; offer retry
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/LoadPhaseTests
```
Expected: PASS.

- [ ] **Step 5: Regenerate and commit**

```bash
xcodegen generate
git add Pulse/Core/Models/LoadPhase.swift PulseTests/Core/LoadPhaseTests.swift project.yml
git commit -m "feat: shared LoadPhase state enum"
```

---

## Task 5: `StatsModel` — the @Observable view model (TDD)

**Files:**
- Create: `Pulse/Features/Stats/StatsModel.swift`
- Create: `PulseTests/Features/Stats/StatsModelTests.swift`

This is the logic core. Build it strictly test-first; each sub-step adds one behavior.

### Step group A — initial state & happy-path load

- [ ] **Step 1: Write the first failing tests `PulseTests/Features/Stats/StatsModelTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class StatsModelTests: XCTestCase {
    func testInitialState() {
        let model = StatsModel(repository: MockStatsRepository())
        XCTAssertEqual(model.selectedRange, .d30)
        XCTAssertEqual(model.phase, .loading)
        XCTAssertNil(model.summary)
        XCTAssertEqual(model.unitsLabel, "KG")
    }

    func testLoadHappyPathPopulatesSummary() async {
        let model = StatsModel(repository: MockStatsRepository())
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.summary?.volumeDisplay, "184K")
        XCTAssertEqual(model.summary?.sessions, 21)
        XCTAssertEqual(model.summary?.sessionsPlanned, 22)
        XCTAssertEqual(model.summary?.streakDays, 27)
        XCTAssertEqual(model.summary?.volumeSeries.count, 12)
        XCTAssertEqual(model.summary?.volumeByMuscle.count, 5)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/StatsModelTests
```
Expected: FAIL — `StatsModel` undefined.

- [ ] **Step 3: Write the minimal `Pulse/Features/Stats/StatsModel.swift`**

```swift
import Foundation

@MainActor
@Observable
final class StatsModel {
    private(set) var phase: LoadPhase = .loading
    private(set) var selectedRange: StatsRange = .defaultRange
    private(set) var summary: StatsSummary?

    /// kg-only for v1 (product decision). Kept here so a later units toggle is localized.
    let unitsLabel = "KG"

    private let repository: StatsRepository

    init(repository: StatsRepository) {
        self.repository = repository
    }

    func load() async {
        phase = .loading
        do {
            let result = try await repository.summary(range: selectedRange)
            summary = result
            phase = result.isEmpty ? .empty : .loaded
        } catch {
            summary = nil
            phase = .error
        }
    }
}

private extension StatsSummary {
    /// No training data in the window: zero volume and no muscle breakdown.
    var isEmpty: Bool { volume == 0 && volumeByMuscle.isEmpty }
}
```

- [ ] **Step 4: Run to verify these tests pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/StatsModelTests
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Stats/StatsModel.swift PulseTests/Features/Stats/StatsModelTests.swift
git commit -m "feat: StatsModel initial state + happy-path load"
```

### Step group B — range selection reload

- [ ] **Step 6: Add failing tests for `select(_:)`**

Append to `StatsModelTests`:
```swift
    func testSelectChangesRangeAndReloads() async {
        let model = StatsModel(repository: MockStatsRepository())
        await model.load()
        let thirtyDayVolume = model.summary?.volume

        await model.select(.d7)
        XCTAssertEqual(model.selectedRange, .d7)
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertNotNil(model.summary)
        XCTAssertNotEqual(model.summary?.volume, thirtyDayVolume) // 7D scaled down
    }

    func testSelectingSameRangeStillReloads() async {
        let model = StatsModel(repository: MockStatsRepository())
        await model.select(.d30)
        XCTAssertEqual(model.selectedRange, .d30)
        XCTAssertEqual(model.phase, .loaded)
    }
```

- [ ] **Step 7: Run to verify the new tests fail**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseTests/StatsModelTests
```
Expected: FAIL — `select(_:)` undefined.

- [ ] **Step 8: Add `select(_:)` to `StatsModel`**

```swift
    func select(_ range: StatsRange) async {
        selectedRange = range
        await load()
    }
```

- [ ] **Step 9: Run to verify pass; commit**

Run the same `-only-testing:PulseTests/StatsModelTests` command. Expected: PASS.
```bash
git add Pulse/Features/Stats/StatsModel.swift PulseTests/Features/Stats/StatsModelTests.swift
git commit -m "feat: StatsModel range selection reload"
```

### Step group C — derived values (maxVolumeMuscleID, volumeChartMax)

- [ ] **Step 10: Add failing tests for derived properties**

Append to `StatsModelTests`:
```swift
    func testMaxVolumeMuscleIsHighest() async {
        let model = StatsModel(repository: MockStatsRepository())
        await model.load()
        let legs = model.summary?.volumeByMuscle.first { $0.muscle == "Legs" }
        XCTAssertEqual(model.maxVolumeMuscleID, legs?.id)
    }

    func testMaxVolumeMuscleDeterministicOnTie() {
        let model = StatsModel(repository: MockStatsRepository())
        let a = VolumeByMuscle(muscle: "A", value: 10, valueDisplay: "10", pct: 1)
        let b = VolumeByMuscle(muscle: "B", value: 10, valueDisplay: "10", pct: 1)
        XCTAssertEqual(model.maxVolumeMuscleID(in: [a, b]), a.id) // first max wins
    }

    func testVolumeChartMaxUsesSeriesMax() {
        let model = StatsModel(repository: MockStatsRepository())
        XCTAssertEqual(model.volumeChartMax(for: [10, 40, 90, 20]), 90)
    }

    func testVolumeChartMaxFloorsAllZeroSeries() {
        let model = StatsModel(repository: MockStatsRepository())
        // an all-zero series must not yield a 0 divisor (would collapse bars)
        XCTAssertGreaterThan(model.volumeChartMax(for: Array(repeating: 0, count: 12)), 0)
    }

    func testVolumeChartMaxFloorsSingleNonZero() {
        let model = StatsModel(repository: MockStatsRepository())
        XCTAssertEqual(model.volumeChartMax(for: [0, 0, 5, 0]), 5)
    }
```

- [ ] **Step 11: Run to verify they fail**

Run the same `-only-testing:PulseTests/StatsModelTests` command. Expected: FAIL — `maxVolumeMuscleID` / `volumeChartMax` undefined.

- [ ] **Step 12: Add the derived logic to `StatsModel`**

```swift
    /// The `VolumeByMuscle` row that gets the `accent2` bar (the single highest).
    /// Deterministic on ties: the first maximum in list order wins.
    var maxVolumeMuscleID: VolumeByMuscle.ID? {
        maxVolumeMuscleID(in: summary?.volumeByMuscle ?? [])
    }

    func maxVolumeMuscleID(in muscles: [VolumeByMuscle]) -> VolumeByMuscle.ID? {
        guard !muscles.isEmpty else { return nil }
        var best = muscles[0]
        for m in muscles.dropFirst() where m.value > best.value { best = m }
        return best.id
    }

    /// Denominator for scaling the 12-bar chart. Floored to 1 so an all-zero
    /// series never divides by zero (bars render flat, not invisible).
    func volumeChartMax(for series: [Int]) -> Int {
        max(series.max() ?? 0, 1)
    }
```

- [ ] **Step 13: Run to verify pass; commit**

Run the same `-only-testing:PulseTests/StatsModelTests` command. Expected: PASS.
```bash
git add Pulse/Features/Stats/StatsModel.swift PulseTests/Features/Stats/StatsModelTests.swift
git commit -m "feat: StatsModel derived maxVolumeMuscleID + volumeChartMax floor"
```

### Step group D — empty, error, retry

- [ ] **Step 14: Add failing tests for empty/error/retry**

Append to `StatsModelTests`:
```swift
    func testEmptyResultSetsEmptyPhase() async {
        let model = StatsModel(repository: MockStatsRepository(mode: .empty))
        await model.load()
        XCTAssertEqual(model.phase, .empty)
    }

    func testFailingRepositorySetsErrorPhase() async {
        let model = StatsModel(repository: MockStatsRepository(mode: .failing))
        await model.load()
        XCTAssertEqual(model.phase, .error)
        XCTAssertNil(model.summary)
    }

    func testRetryRecoversWhenRepositorySucceeds() async {
        let repo = ToggleStatsRepository()
        let model = StatsModel(repository: repo)
        await model.load()
        XCTAssertEqual(model.phase, .error)

        repo.succeed = true
        await model.retry()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.summary?.volumeDisplay, "184K")
    }
}

/// Fails until `succeed` is flipped, to exercise retry().
private final class ToggleStatsRepository: StatsRepository, @unchecked Sendable {
    var succeed = false
    struct Err: Error {}
    func summary(range: StatsRange) async throws -> StatsSummary {
        if succeed { return try await MockStatsRepository().summary(range: range) }
        throw Err()
    }
}
```

(Move the closing brace of `StatsModelTests` so the `ToggleStatsRepository` sits at file scope below the class.)

- [ ] **Step 15: Run to verify they fail**

Run the same `-only-testing:PulseTests/StatsModelTests` command. Expected: FAIL — `retry()` undefined.

- [ ] **Step 16: Add `retry()` to `StatsModel`**

```swift
    func retry() async {
        await load()
    }
```

- [ ] **Step 17: Run to verify the whole `StatsModelTests` suite passes; commit**

Run the same `-only-testing:PulseTests/StatsModelTests` command. Expected: PASS (all groups A–D).
```bash
git add Pulse/Features/Stats/StatsModel.swift PulseTests/Features/Stats/StatsModelTests.swift
git commit -m "feat: StatsModel empty/error phases + retry"
```

---

## Task 6: View building blocks — shared-component shims & local subviews

**Files:**
- Create: `Pulse/Features/Stats/StatsComponents.swift`

These are the small presentational pieces the screen composes. Validate via `#Preview` (visual) + the Task 8 UI test (presence). No line-by-line TDD — these are layout, not logic. Use `Theme` tokens only; no hardcoded colors/spacing. Where BAK-7 owns a component, a shim is provided behind the same name so Stats is unblocked; replace with the shared version when BAK-7 lands.

- [ ] **Step 1: Write `Pulse/Features/Stats/StatsComponents.swift`**

```swift
import SwiftUI

// MARK: - BAK-7 shims (delete when the shared design-system components exist)

/// Uppercase, tracked, Geist Mono micro-label. // BAK-7: replace with shared Eyebrow.
struct Eyebrow: View {
    let text: String
    var color: Color?
    @Environment(Theme.self) private var theme
    init(_ text: String, color: Color? = nil) { self.text = text; self.color = color }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold).monospaced())
            .tracking(1.5)
            .foregroundStyle(color ?? theme.inkSoft)
    }
}

/// Single range pill. // BAK-7: replace with shared FilterChip.
struct FilterChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void
    @Environment(Theme.self) private var theme
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isOn ? theme.onAccent : theme.ink)
                .padding(.horizontal, theme.spacing[4])
                .padding(.vertical, theme.spacing[1])
                .background(isOn ? theme.accent : theme.surface,
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

/// Back chevron + eyebrow + trailing glyph. // BAK-7: replace with shared TopBar.
struct StatsTopBar: View {
    let onBack: () -> Void
    @Environment(Theme.self) private var theme
    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left").foregroundStyle(theme.ink)
            }
            .accessibilityIdentifier("stats.back")
            Spacer()
            Eyebrow("STATS")
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("stats.overflow") // inert per product decision
        }
    }
}

// MARK: - Stats-specific subviews

/// One sub-stat card in the 2×2 grid.
struct SmallStatCard: View {
    let label: String
    let value: String
    var unit: String?
    let sub: String
    var valueColor: Color?
    var labelColor: Color?
    @Environment(Theme.self) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[0]) {
            Eyebrow(label, color: labelColor)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.custom("Oswald", size: 32).weight(.bold))
                    .foregroundStyle(valueColor ?? theme.ink)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(theme.ink.opacity(0.6))
                }
            }
            Eyebrow(sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing[3])
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
    }
}

/// One row of the volume-by-muscle list.
struct MuscleBarRow: View {
    let muscle: VolumeByMuscle
    let isMax: Bool
    @Environment(Theme.self) private var theme
    var body: some View {
        HStack(spacing: theme.spacing[2]) {
            Text(muscle.muscle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.ink)
                .frame(width: 64, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(theme.inkFaint)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isMax ? theme.accent2 : theme.accent)
                        .frame(width: max(geo.size.width * muscle.pct, 4)) // floor so near-zero is visible
                }
            }
            .frame(height: 18)
            Text(muscle.valueDisplay)
                .font(.custom("Oswald", size: 16).weight(.bold))
                .foregroundStyle(theme.ink)
                .frame(width: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("muscle.\(muscle.muscle)")
    }
}

#Preview("SmallStatCard") {
    SmallStatCard(label: "STREAK", value: "27", unit: "d", sub: "PERSONAL BEST")
        .environment(Theme())
        .padding()
}
```

- [ ] **Step 2: Regenerate, build, commit**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.
```bash
git add Pulse/Features/Stats/StatsComponents.swift project.yml
git commit -m "feat: Stats view components (chip, top bar, stat card, muscle row)"
```

---

## Task 7: `StatsView` — the screen (view assembly + preview)

**Files:**
- Create: `Pulse/Features/Stats/StatsView.swift`

The screen renders one of four states by `model.phase`. Hero card uses `card accent` styling (`accent` fill, `onAccent` highlight graphics/text — never `accent2` on the accent card, per design rules). Validate by `#Preview` and the Task 8 UI test.

- [ ] **Step 1: Write `Pulse/Features/Stats/StatsView.swift`**

```swift
import SwiftUI

struct StatsView: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var model: StatsModel

    init(repository: StatsRepository) {
        _model = State(initialValue: StatsModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing[3]) {
                StatsTopBar(onBack: { dismiss() })

                Text("Your numbers.")
                    .font(.custom("HankenGrotesk-Bold", size: 30))
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("stats.h1")

                rangeChips

                content
            }
            .padding(theme.spacing[5])
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .task { await model.load() }
    }

    private var rangeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing[1]) {
                ForEach(StatsRange.allCases, id: \.self) { range in
                    FilterChip(label: range.chipLabel,
                               isOn: range == model.selectedRange) {
                        Task { await model.select(range) }
                    }
                    .accessibilityIdentifier("range.\(range.chipLabel)")
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityIdentifier("stats.loading")
        case .error:
            errorState
        case .empty:
            emptyState
        case .loaded:
            if let summary = model.summary { loaded(summary) }
        }
    }

    @ViewBuilder
    private func loaded(_ summary: StatsSummary) -> some View {
        heroCard(summary)
        grid(summary)
        Eyebrow("VOLUME BY MUSCLE")
        ForEach(summary.volumeByMuscle) { muscle in
            MuscleBarRow(muscle: muscle, isMax: muscle.id == model.maxVolumeMuscleID)
        }
    }

    private func heroCard(_ summary: StatsSummary) -> some View {
        let chartMax = model.volumeChartMax(for: summary.volumeSeries)
        return VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Eyebrow("\(model.selectedRange.eyebrowToken) VOLUME · \(model.unitsLabel)",
                    color: theme.onAccent.opacity(0.85))
            HStack(alignment: .firstTextBaseline) {
                Text(summary.volumeDisplay)
                    .font(.custom("Oswald", size: 64).weight(.bold))
                    .foregroundStyle(theme.onAccent)
                    .accessibilityIdentifier("stats.volume")
                Spacer()
                Text(trendString(summary.volumeTrendPct))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                    .accessibilityIdentifier("stats.trend")
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(summary.volumeSeries.enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.onAccent.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(CGFloat(h) / CGFloat(chartMax) * 50, 2))
                }
            }
            .frame(height: 50)
            .accessibilityIdentifier("stats.chart")
        }
        .padding(theme.spacing[4])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radiusCard))
    }

    private func grid(_ summary: StatsSummary) -> some View {
        let cols = [GridItem(.flexible(), spacing: theme.spacing[1]),
                    GridItem(.flexible(), spacing: theme.spacing[1])]
        return LazyVGrid(columns: cols, spacing: theme.spacing[1]) {
            SmallStatCard(label: "SESSIONS",
                          value: "\(summary.sessions)", unit: "/\(summary.sessionsPlanned)",
                          sub: "OF PLAN")
            SmallStatCard(label: "NEW PRS", value: "\(summary.newPRs)", sub: "THIS MONTH",
                          valueColor: theme.accent, labelColor: theme.accent2)
            SmallStatCard(label: "AVG TIME",
                          value: "\(summary.avgTimeMinutes)", unit: "m", sub: "PER SESSION")
            SmallStatCard(label: "STREAK",
                          value: "\(summary.streakDays)", unit: "d", sub: "PERSONAL BEST",
                          valueColor: theme.accent2, labelColor: theme.accent2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: theme.spacing[2]) {
            Eyebrow("NO DATA YET")
            Text("Log a workout to see your numbers here.")
                .font(.system(size: 15))
                .foregroundStyle(theme.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityIdentifier("stats.empty")
    }

    private var errorState: some View {
        VStack(spacing: theme.spacing[2]) {
            Text("Couldn't load your stats.")
                .font(.system(size: 15))
                .foregroundStyle(theme.ink)
            Button("Retry") { Task { await model.retry() } }
                .foregroundStyle(theme.accent)
                .accessibilityIdentifier("stats.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityIdentifier("stats.error")
    }

    /// "+12% vs prev" / "-8% vs prev" / "—" when there is no prior period.
    private func trendString(_ pct: Int?) -> String {
        guard let pct else { return "—" }
        return "\(pct >= 0 ? "+" : "")\(pct)% vs prev"
    }
}

#Preview("Loaded") {
    NavigationStack { StatsView(repository: MockStatsRepository()) }
        .environment(Theme())
}

#Preview("Empty") {
    NavigationStack { StatsView(repository: MockStatsRepository(mode: .empty)) }
        .environment(Theme())
}

#Preview("Error") {
    NavigationStack { StatsView(repository: MockStatsRepository(mode: .failing)) }
        .environment(Theme())
}
```

- [ ] **Step 2: Regenerate, build, commit**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.
```bash
git add Pulse/Features/Stats/StatsView.swift project.yml
git commit -m "feat: StatsView screen (hero card, grid, muscle list, states)"
```

---

## Task 8: Wire the You → Stats navigation hook

**Files:**
- Modify: `Pulse/Features/You/YouView.swift`

The You tab is a placeholder today (BAK-13 owns its full content). Add the minimal "YOUR DATA → Stats" `NavigationLink` so Stats is reachable and testable. When BAK-13 lands its real You screen, it keeps this same destination.

- [ ] **Step 1: Replace `Pulse/Features/You/YouView.swift`**

```swift
import SwiftUI

struct YouView: View {
    @Environment(Theme.self) private var theme

    var body: some View {
        NavigationStack {
            List {
                Section("YOUR DATA") {
                    NavigationLink {
                        StatsView(repository: MockStatsRepository())
                    } label: {
                        Text("Stats")
                    }
                    .accessibilityIdentifier("you.stats")
                }
            }
            .navigationTitle("You")
        }
    }
}

#Preview { YouView().environment(Theme()) }
```

(Note: the `MockStatsRepository()` here is the UI-first injection point. When BAK-6 lands, this is swapped for the live repository — ideally resolved from the environment rather than constructed inline; that DI refactor is BAK-6's responsibility.)

- [ ] **Step 2: Confirm `Theme` is injected at the app root**

Open `Pulse/App/PulseApp.swift`. If `AppShell()` is not yet given a `Theme`, add it so every screen can read `@Environment(Theme.self)`:
```swift
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
(If BAK-7 already injects `Theme` at the root, leave it as-is.)

- [ ] **Step 3: Regenerate, build, commit**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.
```bash
git add Pulse/Features/You/YouView.swift Pulse/App/PulseApp.swift project.yml
git commit -m "feat: wire You → Stats navigation"
```

---

## Task 9: Acceptance / UI tests (XCUITest)

**Files:**
- Create: `PulseUITests/StatsTests.swift`

These map directly to the spec's acceptance criteria. They drive the app against the in-app `MockStatsRepository` and assert key elements exist.

- [ ] **Step 1: Write `PulseUITests/StatsTests.swift`**

```swift
import XCTest

final class StatsTests: XCTestCase {
    private func openStats(_ app: XCUIApplication) {
        app.launch()
        app.tabBars.buttons["You"].tap()
        app.buttons["you.stats"].tap()
    }

    // AC 1–2: navigation, TopBar STATS, H1.
    func testNavigatesAndShowsHeader() {
        let app = XCUIApplication()
        openStats(app)
        XCTAssertTrue(app.staticTexts["STATS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["stats.h1"].exists
                      || app.staticTexts["Your numbers."].exists)
    }

    // AC 1: back returns to You.
    func testBackReturnsToYou() {
        let app = XCUIApplication()
        openStats(app)
        app.buttons["stats.back"].tap()
        XCTAssertTrue(app.navigationBars["You"].waitForExistence(timeout: 5))
    }

    // AC 3–4: chips present, 30D default active, tapping 7D updates content.
    func testRangeChipsAndSelection() {
        let app = XCUIApplication()
        openStats(app)
        for label in ["7D", "30D", "3M", "YR", "ALL"] {
            XCTAssertTrue(app.buttons["range.\(label)"].exists, label)
        }
        XCTAssertTrue(app.buttons["range.30D"].isSelected)
        app.buttons["range.7D"].tap()
        XCTAssertTrue(app.buttons["range.7D"].isSelected)
        XCTAssertFalse(app.buttons["range.30D"].isSelected)
    }

    // AC 5: hero eyebrow, volume numeral, trend, chart present.
    func testHeroCard() {
        let app = XCUIApplication()
        openStats(app)
        XCTAssertTrue(app.staticTexts["30D VOLUME · KG"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["stats.volume"].exists)
        XCTAssertTrue(app.staticTexts["stats.trend"].exists)
        XCTAssertTrue(app.otherElements["stats.chart"].exists)
    }

    // AC 6: 2×2 grid labels in order.
    func testSubStatGrid() {
        let app = XCUIApplication()
        openStats(app)
        for label in ["SESSIONS", "NEW PRS", "AVG TIME", "STREAK"] {
            XCTAssertTrue(app.staticTexts[label].waitForExistence(timeout: 5), label)
        }
    }

    // AC 7: volume-by-muscle rows render.
    func testMuscleList() {
        let app = XCUIApplication()
        openStats(app)
        XCTAssertTrue(app.staticTexts["VOLUME BY MUSCLE"].waitForExistence(timeout: 5))
        for m in ["Chest", "Back", "Legs", "Shoulders", "Arms"] {
            XCTAssertTrue(app.otherElements["muscle.\(m)"].exists, m)
        }
    }
}
```

- [ ] **Step 2: Run the UI tests**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseUITests/StatsTests
```
Expected: PASS (all six UI tests).

- [ ] **Step 3: Commit**

```bash
git add PulseUITests/StatsTests.swift
git commit -m "test: Stats acceptance UI tests (AC 1-7)"
```

---

## Task 10: Empty & error state UI tests via launch arguments

**Files:**
- Modify: `Pulse/App/PulseApp.swift`
- Modify: `Pulse/Features/You/YouView.swift`
- Modify: `PulseUITests/StatsTests.swift`

AC 8–10 require driving the empty and error states through the UI. Add a launch-argument switch that selects the mock mode, then assert the state UIs.

- [ ] **Step 1: Add a launch-argument-driven repository mode in `PulseApp.swift`**

Add a small helper the app and You screen can read:
```swift
enum UITestConfig {
    static var statsMode: MockStatsRepository.Mode {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-stats-empty") { return .empty }
        if args.contains("-stats-failing") { return .failing }
        return .populated
    }
}
```
(Place this in `PulseApp.swift` below the `App` struct, or a new `Pulse/App/UITestConfig.swift` — either is fine; if new, add it and rerun `xcodegen generate`.)

- [ ] **Step 2: Use it in `YouView.swift`**

```swift
                    NavigationLink {
                        StatsView(repository: MockStatsRepository(mode: UITestConfig.statsMode))
                    } label: {
                        Text("Stats")
                    }
                    .accessibilityIdentifier("you.stats")
```

- [ ] **Step 3: Add the empty/error UI tests to `StatsTests.swift`**

```swift
    // AC 10: empty range shows the empty state, no misleading bars.
    func testEmptyState() {
        let app = XCUIApplication()
        app.launchArguments += ["-stats-empty"]
        openStats(app)
        XCTAssertTrue(app.otherElements["stats.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["stats.chart"].exists)
    }

    // AC 9: repository failure shows error + retry.
    func testErrorStateShowsRetry() {
        let app = XCUIApplication()
        app.launchArguments += ["-stats-failing"]
        openStats(app)
        XCTAssertTrue(app.otherElements["stats.error"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["stats.retry"].exists)
    }
```

(`openStats` already calls `app.launch()`; ensure `launchArguments` are set before it runs — set them before calling `openStats`, as shown.)

- [ ] **Step 4: Regenerate, run the full Stats UI suite, commit**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test \
  -only-testing:PulseUITests/StatsTests
```
Expected: PASS (eight UI tests now).
```bash
git add Pulse/App PulseUITests/StatsTests.swift Pulse/Features/You/YouView.swift project.yml
git commit -m "test: Stats empty + error state UI tests (AC 8-10)"
```

---

## Task 11: Theme-switch acceptance (AC 11) + full suite green

**Files:**
- Modify: `PulseUITests/StatsTests.swift`

AC 11: switching Coastal ↔ Mint restyles with no layout shift. A full palette-picker UI lives in BAK-13; here we assert the screen renders identically-structured under both palettes by toggling the persisted palette default via a launch argument.

- [ ] **Step 1: Add a palette launch-argument hook in `UITestConfig`**

```swift
    static var forcedPalette: Palette? {
        if ProcessInfo.processInfo.arguments.contains("-palette-mint") { return .mint }
        if ProcessInfo.processInfo.arguments.contains("-palette-coastal") { return .coastal }
        return nil
    }
```
And in `PulseApp.swift`, apply it when constructing the `Theme`:
```swift
    @State private var theme: Theme = {
        let t = Theme()
        if let p = UITestConfig.forcedPalette { t.palette = p }
        return t
    }()
```

- [ ] **Step 2: Add the theme-switch UI test to `StatsTests.swift`**

```swift
    // AC 11: same structure under Mint as under Coastal (no layout shift / missing elements).
    func testRendersUnderMintPalette() {
        let app = XCUIApplication()
        app.launchArguments += ["-palette-mint"]
        openStats(app)
        XCTAssertTrue(app.staticTexts["STATS"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["30D VOLUME · KG"].exists)
        XCTAssertTrue(app.otherElements["stats.chart"].exists)
        for m in ["Chest", "Back", "Legs", "Shoulders", "Arms"] {
            XCTAssertTrue(app.otherElements["muscle.\(m)"].exists, m)
        }
    }
```

- [ ] **Step 3: Regenerate and run the ENTIRE test suite (build gate before PR)**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test
```
Expected: `TEST SUCCEEDED` — all unit tests (StatsModels, StatsRange, MockStatsRepository, LoadPhase, StatsModel) and all UI tests (StatsTests) pass, alongside the pre-existing Palette/WorkoutModels tests.

- [ ] **Step 4: Commit**

```bash
git add Pulse/App PulseUITests/StatsTests.swift project.yml
git commit -m "test: Stats renders under Mint palette (AC 11)"
```

---

## Task 12: Review, push, open PR (⏸ human gate)

- [ ] **Step 1: Self-review against the acceptance criteria**

Walk AC 1–11 against the implemented behavior; confirm no hardcoded colors/spacing (grep for hex literals and magic numbers in `Pulse/Features/Stats/`):
```bash
grep -rn "Color(red:\|#[0-9A-Fa-f]\{6\}\|\.padding([0-9]" Pulse/Features/Stats || echo "clean: tokens only"
```
Expected: `clean: tokens only` (all styling via `Theme`).

- [ ] **Step 2: Run `code-reviewer` and `/security-review`** (per CLAUDE.md workflow).

- [ ] **Step 3: Push and open the PR (confirm with the user first)**

Run:
```bash
git push -u origin feature/BAK-15-stats
gh pr create --fill --base main
```
Use the PR template; link Linear BAK-15; reference the spec and this plan. CI must be green.

⏸ **Human gate: review the PR.**

---

## Self-Review notes

- **Spec coverage:** models (Task 1), range enum (Task 2), repository + mock with the exact 30D design sample (Task 3), shared `LoadPhase` (Task 4), the `@Observable StatsModel` with all required methods and derived values (Task 5), view components (Task 6), the full screen with loading/loaded/empty/error states (Task 7), You → Stats navigation (Task 8), and UI tests mapping AC 1–11 (Tasks 9–11). Every acceptance criterion and every "Tests required" bullet from the spec is exercised.
- **Product decisions honored:** units shown as `KG` (not LBS); `volumeTrendPct` optional with `—` for `ALL`; Streak/New PRs values are displayed as produced by the analytics layer (not recomputed on-screen); `maxVolumeMuscleID` is first-max-wins deterministic; chart/bar scaling is floored so zero/near-zero series never collapse to invisible.
- **Out of scope (per spec):** real Supabase aggregation, the `⋯` overflow actions (inert glyph), tappable sub-stat drill-downs, units conversion math, custom date pickers, widgets. None are built.
- **Dependency discipline:** the screen binds only to the `StatsRepository` protocol + in-memory mock; BAK-7 components are shimmed behind their final names so the call sites survive the swap; the You hook is the single injection point BAK-6 later rewires to the live repo.
- **TDD policy:** all logic (models, repository, `StatsModel`, derived helpers) is built failing-test-first with exact commands and expected FAIL→PASS; pure view assembly (Tasks 6–7) is validated by `#Preview` + the XCUITest presence checks rather than line-by-line unit tests.
