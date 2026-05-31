# Personal Records (BAK-16) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Models/repos/helpers follow strict TDD (failing test → run → minimal impl → run → commit); pure SwiftUI views are validated by `#Preview` + XCUITest.

**Goal:** Build the read-only **Personal Records** screen pushed from You → Personal records. It shows a count summary sub-line, a horizontally scrollable muscle-filter chip row, a single accent **hero PR card**, and a 2-column grid of PR cards (fresh PRs flagged `NEW` with an accent-2 border). UI-first: the screen binds to a `PersonalRecordRepository` protocol backed by an in-memory mock with the design's sample data — no Supabase here.

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. The screen is a `View` (`PersonalRecordsView`) plus an `@Observable` model (`PersonalRecordsModel`) in `Pulse/Features/PersonalRecords/`. The model talks only to the `PersonalRecordRepository` protocol (never Supabase). Colors/spacing/radii/typography come exclusively from the injected `Theme`. Weight formatting goes through one helper (`WeightFormatter`) so a future units toggle is localized. Project is generated from `project.yml` via XcodeGen.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency (`async`/`await`), XCTest + XCUITest, XcodeGen.

**Prerequisites (must be built first):**
- **Design System (BAK-7)** — `Theme`/`Palette` tokens and the Geist Mono / Hanken Grotesk / Oswald fonts. The foundation layer (PR #1) already provides `Pulse/Core/DesignSystem/Theme.swift` + `Palette.swift`; this plan assumes those exist and adds the small reusable view atoms (eyebrow text, filter chip) it needs.
- **Data layer (BAK-6)** — repository protocols + in-memory mocks and the `PersonalRecord` domain model. This plan **defines** the `PersonalRecord` struct, the `PersonalRecordRepository` protocol, and the `MockPersonalRecordRepository` if BAK-6 has not landed them yet; if BAK-6 already provides them, reuse those and skip the create steps (the test contracts here are the same).
- **You screen (BAK-15)** — provides the `Personal records` NavRow entry point. Task 7 wires navigation; if BAK-15's `YouView` is still the placeholder, Task 7 adds a minimal `NavigationStack` + `NavigationLink` so the screen is reachable and UI-testable.

**Product decisions honored** (from `docs/superpowers/specs/2026-05-31-product-decisions.md`, authoritative over the spec's Open questions):
- **kg only for v1.** The unit suffix is `kg` (the prototype's `lb` copy is replaced). All weight display goes through `WeightFormatter`.
- **PR = est-1RM (Epley), derived.** Real PR computation lives in BAK-6's analytics helper. This screen is UI-first and renders the mock's already-computed `PersonalRecord` values; it does not compute 1RM. The mock seeds realistic est-1RM-derived bests.
- **`isFresh` = "new this month"** = record `achievedAt` falls in the current calendar month using `Calendar.current` (device-local). The model computes `freshThisMonthCount` from this; the mock sets `isFresh` consistently with its seeded dates so tests are deterministic.
- **Hero fallback:** when no record in the current filter is flagged `isHero`, the hero is the record with the **highest `weight`** in the filter (ties broken by most recent `achievedAt`).
- **`⋯` overflow is an inert placeholder** (no menu wired) per the product decisions.
- **PR cards are not interactive** (no drill-down) — the spec's Open question 4 resolves to read-only.

---

## Task 1: `PersonalRecord` domain model (TDD)

**Files:**
- Create: `Pulse/Core/Models/PersonalRecord.swift`
- Create: `PulseTests/PersonalRecordTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/PersonalRecordTests.swift`**

```swift
import XCTest
@testable import Pulse

final class PersonalRecordTests: XCTestCase {
    private func make(weight: Double = 100, reps: Int = 1,
                      muscle: String = "Chest", fresh: Bool = false,
                      hero: Bool = false) -> PersonalRecord {
        PersonalRecord(exerciseID: nil, exerciseName: "Bench press",
                       muscleGroup: muscle, weight: weight, reps: reps,
                       achievedAt: Date(timeIntervalSince1970: 0),
                       isFresh: fresh, isHero: hero)
    }

    func testCodableRoundTrip() throws {
        let original = make(weight: 275, reps: 1, fresh: true, hero: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PersonalRecord.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEquatableAndIdentifiable() {
        let a = make()
        XCTAssertEqual(a, a)
        XCTAssertNotEqual(a.id, make().id) // fresh UUID per value
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
Expected: FAIL — `PersonalRecord` is undefined (compile error).

- [ ] **Step 3: Write `Pulse/Core/Models/PersonalRecord.swift`**

```swift
import Foundation

/// A best lift surfaced on the Personal Records screen. In v1 the value is the
/// derived est-1RM PR computed in the analytics helper (BAK-6); this struct is
/// the display-ready record. Weight is stored canonically in kilograms.
struct PersonalRecord: Codable, Equatable, Identifiable {
    var id = UUID()
    var exerciseID: Exercise.ID?   // link to the catalog; nil for one-offs
    var exerciseName: String
    var muscleGroup: String        // display label, e.g. "Chest"
    var weight: Double             // kilograms (canonical)
    var reps: Int
    var achievedAt: Date
    var isFresh: Bool              // set this calendar month
    var isHero: Bool               // standout record for the hero card
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (`PersonalRecordTests` green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Core/Models/PersonalRecord.swift PulseTests/PersonalRecordTests.swift
git commit -m "feat: PersonalRecord domain model"
```

---

## Task 2: `WeightFormatter` helper (TDD)

The single place weight + unit display is formatted, so a future units toggle is localized (product decision: kg only for v1).

**Files:**
- Create: `Pulse/Core/DesignSystem/WeightFormatter.swift`
- Create: `PulseTests/WeightFormatterTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/WeightFormatterTests.swift`**

```swift
import XCTest
@testable import Pulse

final class WeightFormatterTests: XCTestCase {
    func testUnitSuffixIsKilogramsForV1() {
        XCTAssertEqual(WeightFormatter.unitSuffix, "kg")
    }

    func testWholeNumberDropsDecimals() {
        XCTAssertEqual(WeightFormatter.value(275), "275")
        XCTAssertEqual(WeightFormatter.value(100.0), "100")
    }

    func testFractionalKeepsOneDecimal() {
        XCTAssertEqual(WeightFormatter.value(72.5), "72.5")
    }

    func testRepsFormat() {
        XCTAssertEqual(WeightFormatter.reps(1), "×1")
        XCTAssertEqual(WeightFormatter.reps(8), "×8")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: FAIL — `WeightFormatter` is undefined.

- [ ] **Step 3: Write `Pulse/Core/DesignSystem/WeightFormatter.swift`**

```swift
import Foundation

/// The single source of weight + unit display formatting. v1 is kilograms only
/// (product decision); a units preference + conversion is a later feature, so
/// all weight rendering routes through here to keep that change localized.
enum WeightFormatter {
    /// Display suffix for the current unit. kg for v1.
    static let unitSuffix = "kg"

    /// Formats a canonical (kg) weight: whole numbers drop the decimal,
    /// fractional weights keep one decimal place.
    static func value(_ weight: Double) -> String {
        if weight.rounded() == weight {
            return String(Int(weight))
        }
        return String(format: "%.1f", weight)
    }

    /// Rep count as shown beside a weight, e.g. "×1".
    static func reps(_ reps: Int) -> String { "×\(reps)" }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (`WeightFormatterTests` green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Core/DesignSystem/WeightFormatter.swift PulseTests/WeightFormatterTests.swift
git commit -m "feat: WeightFormatter (kg-only v1, single formatting helper)"
```

---

## Task 3: Repository protocol + in-memory mock (TDD)

**Files:**
- Create: `Pulse/Core/Data/PersonalRecordRepository.swift`
- Create: `Pulse/Core/Data/Mock/MockPersonalRecordRepository.swift`
- Create: `PulseTests/MockPersonalRecordRepositoryTests.swift`

> If BAK-6 already defines `PersonalRecordRepository` and the mock, reuse them and skip Steps 3–4; keep the test (Step 1) as the contract.

- [ ] **Step 1: Write the failing test `PulseTests/MockPersonalRecordRepositoryTests.swift`**

```swift
import XCTest
@testable import Pulse

final class MockPersonalRecordRepositoryTests: XCTestCase {
    func testSeedReturnsTrackedRecords() async throws {
        let repo = MockPersonalRecordRepository()
        let records = try await repo.personalRecords()
        XCTAssertEqual(records.count, 8, "design summary is 8 lifts tracked")
        XCTAssertEqual(records.filter(\.isFresh).count, 4,
                       "design summary is 4 new this month")
        XCTAssertEqual(records.filter(\.isHero).count, 1,
                       "exactly one global hero is flagged")
    }

    func testEmptyVariantReturnsNoRecords() async throws {
        let repo = MockPersonalRecordRepository(result: .empty)
        let records = try await repo.personalRecords()
        XCTAssertTrue(records.isEmpty)
    }

    func testFailingVariantThrows() async {
        let repo = MockPersonalRecordRepository(result: .failure)
        do {
            _ = try await repo.personalRecords()
            XCTFail("expected throw")
        } catch {
            XCTAssertTrue(error is MockError)
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
Expected: FAIL — `MockPersonalRecordRepository` / `PersonalRecordRepository` / `MockError` undefined.

- [ ] **Step 3: Write `Pulse/Core/Data/PersonalRecordRepository.swift`**

```swift
import Foundation

/// Read access to the user's personal records. Views/models depend on this
/// protocol only; the live implementation (Supabase) lands with BAK-6 behind
/// the same contract.
protocol PersonalRecordRepository {
    /// All tracked PRs for the current user (already derived est-1RM bests).
    func personalRecords() async throws -> [PersonalRecord]
}
```

- [ ] **Step 4: Write `Pulse/Core/Data/Mock/MockPersonalRecordRepository.swift`**

```swift
import Foundation

/// Generic error surfaced by the in-memory mocks so tests can assert on it.
struct MockError: Error, Equatable {}

/// In-memory `PersonalRecordRepository` seeded with the design's sample data.
/// Drives the entire Personal Records screen UI-first; no Supabase.
struct MockPersonalRecordRepository: PersonalRecordRepository {
    enum Result { case seeded, empty, failure }
    var result: Result = .seeded

    init(result: Result = .seeded) { self.result = result }

    func personalRecords() async throws -> [PersonalRecord] {
        switch result {
        case .failure: throw MockError()
        case .empty:   return []
        case .seeded:  return Self.seed
        }
    }

    /// 8 records total, 4 fresh (this month), 1 hero — matching the design's
    /// "8 lifts tracked · 4 new this month" summary. Dates are anchored to the
    /// current month so `isFresh` stays consistent in any run.
    static var seed: [PersonalRecord] {
        let cal = Calendar.current
        let now = Date()
        func thisMonth(_ daysAgo: Int) -> Date {
            cal.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        }
        func monthsAgo(_ n: Int) -> Date {
            cal.date(byAdding: .month, value: -n, to: now) ?? now
        }
        return [
            PersonalRecord(exerciseID: nil, exerciseName: "Bench press",
                           muscleGroup: "Chest", weight: 125, reps: 1,
                           achievedAt: thisMonth(3), isFresh: true, isHero: true),
            PersonalRecord(exerciseID: nil, exerciseName: "Deadlift",
                           muscleGroup: "Back", weight: 190, reps: 1,
                           achievedAt: thisMonth(6), isFresh: true, isHero: false),
            PersonalRecord(exerciseID: nil, exerciseName: "Incline DB",
                           muscleGroup: "Chest", weight: 35, reps: 8,
                           achievedAt: thisMonth(5), isFresh: true, isHero: false),
            PersonalRecord(exerciseID: nil, exerciseName: "Front squat",
                           muscleGroup: "Legs", weight: 110, reps: 3,
                           achievedAt: thisMonth(1), isFresh: true, isHero: false),
            PersonalRecord(exerciseID: nil, exerciseName: "Squat",
                           muscleGroup: "Legs", weight: 165, reps: 1,
                           achievedAt: monthsAgo(2), isFresh: false, isHero: false),
            PersonalRecord(exerciseID: nil, exerciseName: "OHP",
                           muscleGroup: "Delts", weight: 75, reps: 3,
                           achievedAt: monthsAgo(2), isFresh: false, isHero: false),
            PersonalRecord(exerciseID: nil, exerciseName: "Pulldown",
                           muscleGroup: "Back", weight: 80, reps: 8,
                           achievedAt: monthsAgo(1), isFresh: false, isHero: false),
            PersonalRecord(exerciseID: nil, exerciseName: "Barbell curl",
                           muscleGroup: "Arms", weight: 45, reps: 6,
                           achievedAt: monthsAgo(3), isFresh: false, isHero: false),
        ]
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (`MockPersonalRecordRepositoryTests` green).

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/Data/PersonalRecordRepository.swift \
  Pulse/Core/Data/Mock/MockPersonalRecordRepository.swift \
  PulseTests/MockPersonalRecordRepositoryTests.swift
git commit -m "feat: PersonalRecordRepository protocol + seeded in-memory mock"
```

---

## Task 4: `PersonalRecordsModel` — load, filter, derived state (TDD)

**Files:**
- Create: `Pulse/Features/PersonalRecords/PersonalRecordsModel.swift`
- Create: `PulseTests/PersonalRecordsModelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/PersonalRecordsModelTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class PersonalRecordsModelTests: XCTestCase {

    // AC 1 / AC 7: load populates records and reaches .loaded.
    func testLoadPopulatesRecordsAndSetsLoaded() async {
        let model = PersonalRecordsModel(repository: MockPersonalRecordRepository())
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.records.count, 8)
        XCTAssertEqual(model.trackedCount, 8)
        XCTAssertEqual(model.freshThisMonthCount, 4)
    }

    // AC 2: muscleFilters = nil-equivalent "All" handled by the view; the model
    // exposes distinct muscles in first-seen (stable) order.
    func testMuscleFiltersAreDistinctInStableOrder() async {
        let model = PersonalRecordsModel(repository: MockPersonalRecordRepository())
        await model.load()
        XCTAssertEqual(model.muscleFilters, ["Chest", "Back", "Legs", "Delts", "Arms"])
    }

    // AC 3: selecting a muscle filters filtered/grid/hero; nil clears.
    func testSelectFiltersAndClears() async {
        let model = PersonalRecordsModel(repository: MockPersonalRecordRepository())
        await model.load()

        model.select("Chest")
        XCTAssertEqual(model.selectedMuscle, "Chest")
        XCTAssertTrue(model.filtered.allSatisfy { $0.muscleGroup == "Chest" })
        XCTAssertEqual(model.filtered.count, 2) // Bench press + Incline DB

        model.select(nil)
        XCTAssertNil(model.selectedMuscle)
        XCTAssertEqual(model.filtered.count, 8)
    }

    // AC 4: hero is the isHero record within the filter.
    func testHeroIsFlaggedRecordWithinFilter() async {
        let model = PersonalRecordsModel(repository: MockPersonalRecordRepository())
        await model.load()
        XCTAssertEqual(model.hero?.exerciseName, "Bench press")
    }

    // AC 4 edge case + product decision: with no isHero in the filter, hero is
    // the heaviest record in that filter.
    func testHeroFallsBackToHeaviestWhenNoneFlagged() async {
        let model = PersonalRecordsModel(repository: MockPersonalRecordRepository())
        await model.load()
        model.select("Back") // no isHero in Back; Deadlift 190 is heaviest
        XCTAssertEqual(model.hero?.exerciseName, "Deadlift")
    }

    // AC 5: gridRecords excludes the hero.
    func testGridRecordsExcludeHero() async {
        let model = PersonalRecordsModel(repository: MockPersonalRecordRepository())
        await model.load()
        XCTAssertFalse(model.gridRecords.contains { $0.id == model.hero?.id })
        XCTAssertEqual(model.gridRecords.count, model.filtered.count - 1)
    }

    // AC 8: empty repo result → .empty, no hero.
    func testEmptyRepoSetsEmptyPhase() async {
        let model = PersonalRecordsModel(
            repository: MockPersonalRecordRepository(result: .empty))
        await model.load()
        XCTAssertEqual(model.phase, .empty)
        XCTAssertNil(model.hero)
        XCTAssertTrue(model.gridRecords.isEmpty)
    }

    // AC 9: filter with no matches → empty filtered, chips still usable.
    func testFilterWithNoMatchesIsEmptyButRecoverable() async {
        let model = PersonalRecordsModel(repository: MockPersonalRecordRepository())
        await model.load()
        model.select("Calves") // not present
        XCTAssertTrue(model.filtered.isEmpty)
        XCTAssertNil(model.hero)
        model.select(nil)
        XCTAssertEqual(model.filtered.count, 8)
    }

    // AC 10: repo throw → .error, no stale records retained.
    func testRepositoryThrowSetsErrorAndKeepsNoStaleData() async {
        let model = PersonalRecordsModel(
            repository: MockPersonalRecordRepository(result: .failure))
        await model.load()
        guard case .error = model.phase else {
            return XCTFail("expected .error, got \(model.phase)")
        }
        XCTAssertTrue(model.records.isEmpty)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: FAIL — `PersonalRecordsModel` undefined.

- [ ] **Step 3: Write `Pulse/Features/PersonalRecords/PersonalRecordsModel.swift`**

```swift
import Foundation

@MainActor
@Observable
final class PersonalRecordsModel {
    enum Phase: Equatable { case loading, loaded, empty, error(String) }

    private(set) var phase: Phase = .loading
    private(set) var records: [PersonalRecord] = []
    var selectedMuscle: String?            // nil == "All"

    private let repository: PersonalRecordRepository

    init(repository: PersonalRecordRepository) {
        self.repository = repository
    }

    /// Distinct muscle groups in first-seen order (the chip row prepends "All").
    var muscleFilters: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for record in records where !seen.contains(record.muscleGroup) {
            seen.insert(record.muscleGroup)
            ordered.append(record.muscleGroup)
        }
        return ordered
    }

    /// Records matching the active filter (all records when nil).
    var filtered: [PersonalRecord] {
        guard let muscle = selectedMuscle else { return records }
        return records.filter { $0.muscleGroup == muscle }
    }

    /// The hero record in the current filter: the flagged one, else the
    /// heaviest (ties broken by most recent).
    var hero: PersonalRecord? {
        if let flagged = filtered.first(where: \.isHero) { return flagged }
        return filtered.max {
            ($0.weight, $0.achievedAt) < ($1.weight, $1.achievedAt)
        }
    }

    /// Every filtered record except the hero, for the 2-column grid.
    var gridRecords: [PersonalRecord] {
        guard let hero else { return filtered }
        return filtered.filter { $0.id != hero.id }
    }

    var trackedCount: Int { records.count }
    var freshThisMonthCount: Int { records.filter(\.isFresh).count }

    func load() async {
        phase = .loading
        do {
            let result = try await repository.personalRecords()
            records = result
            phase = result.isEmpty ? .empty : .loaded
        } catch {
            records = []                    // never retain stale data on error
            phase = .error("Couldn't load your personal records.")
        }
    }

    func select(_ muscle: String?) { selectedMuscle = muscle }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (all `PersonalRecordsModelTests` green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/PersonalRecords/PersonalRecordsModel.swift \
  PulseTests/PersonalRecordsModelTests.swift
git commit -m "feat: PersonalRecordsModel (load, filter, hero, summary counts)"
```

---

## Task 5: Reusable view atoms — `Eyebrow` and `FilterChip`

Small shared SwiftUI atoms the screen needs, using Theme tokens and the design's fonts. These are pure layout (no branching logic), validated by `#Preview`. If BAK-7 already ships equivalents, reuse those and skip this task.

**Files:**
- Create: `Pulse/Core/DesignSystem/Components/Eyebrow.swift`
- Create: `Pulse/Core/DesignSystem/Components/FilterChip.swift`

- [ ] **Step 1: Write `Pulse/Core/DesignSystem/Components/Eyebrow.swift`**

```swift
import SwiftUI

/// Uppercase, letter-spaced label (Geist Mono) used for eyebrows and flags.
struct Eyebrow: View {
    let text: String
    var color: Color?
    var size: CGFloat = 9
    @Environment(Theme.self) private var theme

    var body: some View {
        Text(text.uppercased())
            .font(.custom("GeistMono-Regular", size: size))
            .tracking(size * 0.14)
            .foregroundStyle(color ?? theme.inkSoft)
    }
}

#Preview {
    @Previewable @State var theme = Theme()
    return VStack(alignment: .leading, spacing: 8) {
        Eyebrow(text: "Personal Records")
        Eyebrow(text: "New", color: theme.accent2)
    }
    .padding()
    .background(theme.bg)
    .environment(theme)
}
```

- [ ] **Step 2: Write `Pulse/Core/DesignSystem/Components/FilterChip.swift`**

```swift
import SwiftUI

/// A pill filter chip. Active = accent fill with onAccent text; inactive =
/// faint outline with ink-soft text.
struct FilterChip: View {
    let label: String
    let isActive: Bool
    let action: () -> Void
    @Environment(Theme.self) private var theme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.custom("HankenGrotesk-SemiBold", size: 13))
                .foregroundStyle(isActive ? theme.onAccent : theme.inkSoft)
                .padding(.horizontal, theme.spacing[3]) // 12
                .padding(.vertical, theme.spacing[1])    // 8
                .background(
                    Capsule().fill(isActive ? theme.accent : Color.clear)
                )
                .overlay(
                    Capsule().stroke(isActive ? Color.clear : theme.inkFaint,
                                     lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filterChip.\(label)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var theme = Theme()
    return HStack(spacing: 6) {
        FilterChip(label: "All", isActive: true) {}
        FilterChip(label: "Chest", isActive: false) {}
    }
    .padding()
    .background(theme.bg)
    .environment(theme)
}
```

- [ ] **Step 3: Build to confirm the atoms compile and previews resolve**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Pulse/Core/DesignSystem/Components
git commit -m "feat: Eyebrow and FilterChip design-system atoms"
```

---

## Task 6: `PersonalRecordsView` — screen assembly (View + Preview + UI test)

Pure SwiftUI assembly bound to `PersonalRecordsModel`. Built with concrete structure + `#Preview`, validated by the XCUITest in Task 8. Accessibility identifiers are added so the UI tests can find elements.

**Files:**
- Create: `Pulse/Features/PersonalRecords/PersonalRecordsView.swift`

- [ ] **Step 1: Write `Pulse/Features/PersonalRecords/PersonalRecordsView.swift`**

```swift
import SwiftUI

struct PersonalRecordsView: View {
    @State private var model: PersonalRecordsModel
    @Environment(Theme.self) private var theme

    init(repository: PersonalRecordRepository = MockPersonalRecordRepository()) {
        _model = State(initialValue: PersonalRecordsModel(repository: repository))
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            content
        }
        .navigationBarBackButtonHidden(false)
        .toolbar { topBar }
        .task { await model.load() }
    }

    // MARK: TopBar

    @ToolbarContentBuilder
    private var topBar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Eyebrow(text: "Personal Records")
                .accessibilityIdentifier("pr.eyebrow")
        }
        ToolbarItem(placement: .topBarTrailing) {
            // Inert overflow placeholder (product decision: ⋯ not wired in v1).
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("pr.overflow")
        }
    }

    // MARK: Phase switch

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .tint(theme.accent)
                .accessibilityIdentifier("pr.loading")
        case .error(let message):
            errorState(message)
        case .empty:
            emptyState
        case .loaded:
            loaded
        }
    }

    // MARK: Loaded

    private var loaded: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            header
            chipRow
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing[1]) {
                    if let hero = model.hero {
                        heroCard(hero)
                    }
                    if model.filtered.isEmpty {
                        filterEmptyState
                    } else {
                        grid
                    }
                }
                .padding(.top, theme.spacing[3])
            }
        }
        .padding(.horizontal, theme.spacing[5]) // 18
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing[0]) {
            Text("PRs.")
                .font(.custom("HankenGrotesk-Bold", size: 30))
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("pr.h1")
            Text("\(model.trackedCount) lifts tracked · \(model.freshThisMonthCount) new this month")
                .font(.custom("HankenGrotesk-Regular", size: 13))
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("pr.subline")
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing[0]) {
                FilterChip(label: "All", isActive: model.selectedMuscle == nil) {
                    model.select(nil)
                }
                ForEach(model.muscleFilters, id: \.self) { muscle in
                    FilterChip(label: muscle,
                               isActive: model.selectedMuscle == muscle) {
                        model.select(muscle)
                    }
                }
            }
        }
    }

    // MARK: Hero card

    private func heroCard(_ pr: PersonalRecord) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing[0]) {
            HStack(alignment: .top) {
                if pr.isFresh {
                    Text("NEW · \(relativeDate(pr.achievedAt))".uppercased())
                        .font(.custom("GeistMono-Regular", size: 9))
                        .tracking(9 * 0.14)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, theme.spacing[1])
                        .padding(.vertical, 2)
                        .background(Capsule().fill(theme.onAccent))
                        .accessibilityIdentifier("pr.hero.newPill")
                }
                Spacer()
                Eyebrow(text: pr.muscleGroup, color: theme.onAccent.opacity(0.85))
            }
            Text(pr.exerciseName)
                .font(.custom("HankenGrotesk-ExtraBold", size: 18))
                .foregroundStyle(theme.onAccent)
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing[4]) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(WeightFormatter.value(pr.weight))
                        .font(.custom("Oswald-Bold", size: 64))
                        .foregroundStyle(theme.onAccent)
                    Text(WeightFormatter.unitSuffix)
                        .font(.custom("HankenGrotesk-ExtraBold", size: 14))
                        .foregroundStyle(theme.onAccent.opacity(0.85))
                }
                Text(WeightFormatter.reps(pr.reps))
                    .font(.custom("Oswald-Bold", size: 34))
                    .foregroundStyle(theme.accent2)
            }
        }
        .padding(.horizontal, theme.spacing[5])
        .padding(.vertical, theme.spacing[5])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.radiusCard).fill(theme.accent)
        )
        .accessibilityIdentifier("pr.heroCard")
    }

    // MARK: Grid

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: theme.spacing[0]),
                      GridItem(.flexible(), spacing: theme.spacing[0])],
            spacing: theme.spacing[0]
        ) {
            ForEach(model.gridRecords) { pr in
                gridCard(pr)
            }
        }
    }

    private func gridCard(_ pr: PersonalRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: pr.muscleGroup)
                Spacer()
                if pr.isFresh {
                    Eyebrow(text: "New", color: theme.accent2)
                }
            }
            Text(pr.exerciseName)
                .font(.custom("HankenGrotesk-Bold", size: 13))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: theme.spacing[2]) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(WeightFormatter.value(pr.weight))
                        .font(.custom("Oswald-Bold", size: 24))
                        .foregroundStyle(theme.ink)
                    Text(WeightFormatter.unitSuffix)
                        .font(.custom("HankenGrotesk-ExtraBold", size: 10))
                        .foregroundStyle(theme.inkSoft)
                }
                Text(WeightFormatter.reps(pr.reps))
                    .font(.custom("Oswald-Bold", size: 14))
                    .foregroundStyle(theme.accent2)
            }
            Eyebrow(text: relativeDate(pr.achievedAt))
        }
        .padding(.horizontal, theme.spacing[4])
        .padding(.vertical, theme.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: theme.radiusCard)
                .stroke(pr.isFresh ? theme.accent2 : theme.inkFaint,
                        lineWidth: pr.isFresh ? 2 : 1.5)
        )
        .accessibilityIdentifier("pr.gridCard")
    }

    // MARK: Non-loaded states

    private var emptyState: some View {
        VStack(spacing: theme.spacing[2]) {
            Text("No personal records yet")
                .font(.custom("HankenGrotesk-Bold", size: 18))
                .foregroundStyle(theme.ink)
            Text("Log a few working sets and your bests will show up here.")
                .font(.custom("HankenGrotesk-Regular", size: 13))
                .foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
        }
        .padding(theme.spacing[6])
        .accessibilityIdentifier("pr.empty")
    }

    private var filterEmptyState: some View {
        Text("No PRs for \(model.selectedMuscle ?? "") yet")
            .font(.custom("HankenGrotesk-Regular", size: 13))
            .foregroundStyle(theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, theme.spacing[6])
            .accessibilityIdentifier("pr.filterEmpty")
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: theme.spacing[2]) {
            Text(message)
                .font(.custom("HankenGrotesk-Regular", size: 14))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await model.load() } }
                .font(.custom("HankenGrotesk-SemiBold", size: 14))
                .foregroundStyle(theme.onAccent)
                .padding(.horizontal, theme.spacing[5])
                .padding(.vertical, theme.spacing[2])
                .background(Capsule().fill(theme.accent))
                .accessibilityIdentifier("pr.retry")
        }
        .padding(theme.spacing[6])
        .accessibilityIdentifier("pr.error")
    }

    // Lightweight relative date for the card sub-line / hero pill.
    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

#Preview("Loaded") {
    @Previewable @State var theme = Theme()
    return NavigationStack {
        PersonalRecordsView(repository: MockPersonalRecordRepository())
    }
    .environment(theme)
}

#Preview("Empty") {
    @Previewable @State var theme = Theme()
    return NavigationStack {
        PersonalRecordsView(repository: MockPersonalRecordRepository(result: .empty))
    }
    .environment(theme)
}

#Preview("Error") {
    @Previewable @State var theme = Theme()
    return NavigationStack {
        PersonalRecordsView(repository: MockPersonalRecordRepository(result: .failure))
    }
    .environment(theme)
}
```

- [ ] **Step 2: Build to confirm the view compiles**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`. Open the file in Xcode and confirm the three previews render (Loaded shows hero + grid; Empty shows the empty message; Error shows the retry button).

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/PersonalRecords/PersonalRecordsView.swift
git commit -m "feat: PersonalRecordsView (header, chips, hero card, grid, states)"
```

---

## Task 7: Wire the entry point in You and inject Theme

The foundation `YouView` is a placeholder and `AppShell` does not yet inject `Theme`. Add a `NavigationStack` + `NavigationLink` so the screen is reachable, and inject a shared `Theme` at the app root so `@Environment(Theme.self)` resolves. If BAK-15 already provides the You list and Theme injection, only add the `Personal records` NavRow that pushes `PersonalRecordsView`.

**Files:**
- Modify: `Pulse/App/AppShell.swift`
- Modify: `Pulse/Features/You/YouView.swift`

- [ ] **Step 1: Inject a shared `Theme` in `Pulse/App/AppShell.swift`**

Replace the body so the tab view has a `Theme` in its environment:

```swift
import SwiftUI

struct AppShell: View {
    @State private var theme = Theme()

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "bolt.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            YouView()
                .tabItem { Label("You", systemImage: "person.fill") }
        }
        .environment(theme)
    }
}

#Preview { AppShell() }
```

- [ ] **Step 2: Add the navigable `Personal records` row in `Pulse/Features/You/YouView.swift`**

```swift
import SwiftUI

struct YouView: View {
    @Environment(Theme.self) private var theme

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    PersonalRecordsView()
                } label: {
                    Text("Personal records")
                }
                .accessibilityIdentifier("you.personalRecordsRow")
            }
            .navigationTitle("You")
        }
    }
}

#Preview {
    @Previewable @State var theme = Theme()
    return YouView().environment(theme)
}
```

- [ ] **Step 3: Build to confirm wiring compiles**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Pulse/App/AppShell.swift Pulse/Features/You/YouView.swift
git commit -m "feat: inject shared Theme and add You → Personal records nav entry"
```

---

## Task 8: Acceptance / UI tests (`PersonalRecordsUITests`)

XCUITest covering the spec's acceptance criteria. These drive the seeded mock through the real navigation path (You → Personal records).

**Files:**
- Create: `PulseUITests/PersonalRecordsUITests.swift`

- [ ] **Step 1: Write `PulseUITests/PersonalRecordsUITests.swift`**

```swift
import XCTest

final class PersonalRecordsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate You → Personal records.
        app.tabBars.buttons["You"].tap()
        app.cells["you.personalRecordsRow"].tap()
    }

    // AC 1: header eyebrow + H1 + sub-line render.
    func testHeaderAndSublineRender() {
        XCTAssertTrue(app.staticTexts["pr.h1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["pr.subline"].exists)
        XCTAssertTrue(app.otherElements["pr.overflow"].exists
                      || app.images["pr.overflow"].exists)
    }

    // AC 2 / AC 3: chip row with All default-active; selecting a chip filters.
    func testFilterChipsFilterContent() {
        XCTAssertTrue(app.buttons["filterChip.All"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["filterChip.Chest"].exists)

        let heroBefore = app.otherElements["pr.heroCard"]
        XCTAssertTrue(heroBefore.waitForExistence(timeout: 5))

        app.buttons["filterChip.Chest"].tap()
        // Chest filter keeps a hero (Bench press) and a smaller grid.
        XCTAssertTrue(app.otherElements["pr.heroCard"].waitForExistence(timeout: 5))
    }

    // AC 4 / AC 5 / AC 6: hero card + grid cards render.
    func testHeroAndGridRender() {
        XCTAssertTrue(app.otherElements["pr.heroCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["pr.hero.newPill"].exists)
        XCTAssertGreaterThan(
            app.otherElements.matching(identifier: "pr.gridCard").count, 0)
    }

    // AC 9: a filter with no matches shows the per-filter empty state.
    // (Uses "All" → no path to an empty muscle via chips, so verified at the
    //  model layer; here we confirm chips stay interactive after filtering.)
    func testChipsRemainInteractive() {
        app.buttons["filterChip.Legs"].tap()
        XCTAssertTrue(app.buttons["filterChip.All"].isHittable)
        app.buttons["filterChip.All"].tap()
        XCTAssertTrue(app.otherElements["pr.heroCard"].waitForExistence(timeout: 5))
    }
}
```

> Note on AC 8 / AC 10 (empty + error states): these are exercised by the model unit tests (Task 4) and by the `#Preview("Empty")` / `#Preview("Error")` previews, since the shipped navigation always uses the seeded mock. Driving them through the UI would require a launch-argument repository override; that override is **out of scope** for this read-only screen and noted as a follow-up.

- [ ] **Step 2: Run the UI tests to confirm they pass**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseUITests/PersonalRecordsUITests test
```
Expected: PASS (all four UI tests green).

- [ ] **Step 3: Run the full test suite**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS — `PersonalRecordTests`, `WeightFormatterTests`, `MockPersonalRecordRepositoryTests`, `PersonalRecordsModelTests`, `PersonalRecordsUITests` all green; no regressions.

- [ ] **Step 4: Commit**

```bash
git add PulseUITests/PersonalRecordsUITests.swift
git commit -m "test: PersonalRecords acceptance UI tests"
```

---

## Task 9: Palette-switch verification (AC 11)

Confirm the screen re-renders correctly in both palettes with no hardcoded values.

**Files:**
- (No source changes; verification only. If a defect is found, fix the offending view to use a `Theme` token and re-run.)

- [ ] **Step 1: Visually verify both palettes via previews**

In Xcode, in `PersonalRecordsView.swift`, temporarily set the preview's theme palette to `.mint` (`theme.palette = .mint`) on the "Loaded" preview and confirm: hero card `onAccent` text stays legible on the Mint accent, accent-2 reps remain legible, fresh-card accent-2 borders render. Revert the temporary change.

- [ ] **Step 2: Grep for hardcoded colors/spacing in the feature**

Run:
```bash
grep -REn "Color\.(red|blue|green|orange|gray|black|white)|\.foregroundColor\(\.|#[0-9A-Fa-f]{6}" \
  Pulse/Features/PersonalRecords Pulse/Core/DesignSystem/Components || echo "no hardcoded colors"
```
Expected: `no hardcoded colors` (every color comes from `theme.*`).

- [ ] **Step 3: Confirm the build is still green**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

---

## Self-Review notes

- **Spec coverage:** AC 1 (header/eyebrow/sub-line) — Task 6 header + Task 8 `testHeaderAndSublineRender`; AC 2/3 (chips + filtering) — Task 4 filter tests + Task 6 chipRow + Task 8 `testFilterChipsFilterContent`; AC 4 (hero card) — Task 4 hero tests + Task 6 heroCard + Task 8 `testHeroAndGridRender`; AC 5/6 (grid + fresh borders) — Task 6 grid/gridCard + Task 8; AC 7 (loading) — model `.loading` + `pr.loading`; AC 8 (empty) — Task 4 + `#Preview("Empty")`; AC 9 (filter empty) — Task 4 + Task 6 `filterEmptyState`; AC 10 (error/retry) — Task 4 + Task 6 `errorState` + `#Preview("Error")`; AC 11 (palette) — Task 9.
- **Product decisions honored:** kg-only suffix via `WeightFormatter` (Task 2); hero fallback = heaviest (Task 4); `isFresh` = current calendar month via `Calendar.current` reflected in mock seed + `freshThisMonthCount`; `⋯` inert placeholder; PR cards non-interactive; values are mock-provided (no 1RM computation here, per UI-first).
- **TDD vs view assembly:** model, repo/mock, `PersonalRecord`, and `WeightFormatter` use strict failing-test-first TDD; `Eyebrow`/`FilterChip`/`PersonalRecordsView` are assembled with concrete code + `#Preview` and validated by XCUITest — matching the granularity policy.
- **No Supabase:** the model depends only on `PersonalRecordRepository`; the screen is driven by `MockPersonalRecordRepository`.
- **Out of scope (per spec):** real PR derivation, units conversion, drill-down navigation, `⋯` menu contents, editing PRs, widgets. The empty/error UI-driven paths are noted as a follow-up (launch-argument repo override).
- **Prerequisites flagged:** Design System (BAK-7), Data layer (BAK-6), You screen (BAK-15) — each task notes the reuse-or-create fallback so this plan runs whether or not those have fully landed.
