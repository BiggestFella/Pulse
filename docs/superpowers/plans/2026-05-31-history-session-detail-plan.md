# Workout History + Session Detail — Implementation Plan (BAK-17)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Models/helpers follow strict TDD (failing test → run → minimal impl → run → commit); pure SwiftUI views are validated by `#Preview` + an XCUITest.

**Goal:** Build the two read-only screens of the Pulse workout-history stack — **Workout History** (grouped, filterable list of past sessions) and **Session Detail** (a receipt of one completed session: headline stats, full per-exercise log, Duplicate / Repeat actions). Both are UI-first: they bind to repository protocols backed by in-memory mocks with sample data. No Supabase wiring here.

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. Each screen is a `View` + an `@Observable` model in `Pulse/Features/<Feature>/`. Data access only through a `SessionRepository` protocol in `Pulse/Core/Data` (mock-backed). Display projections (`SessionSummary`, `SessionDetail`, `LogRow`) and the formatting/PR helpers live in `Core` so models stay logic-light. All colors/spacing/radii/type come from `Theme` tokens.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency (`async`/`await`), XcodeGen, XCTest + XCUITest.

**Product decisions applied (authoritative — `docs/superpowers/specs/2026-05-31-product-decisions.md`):**
- **PR = estimated 1RM via Epley** (`1RM = weight × (1 + reps/30)`), derived per logged working/AMRAP set (warmups excluded). The PR count + source on a session are computed, not stored flags.
- **Units: kilograms only for v1.** The prototype's "LBS"/"lbs" copy is replaced with "KG"/"kg". All weight/volume formatting goes through one helper so a future unit toggle is localized.
- **Calendar/timezone:** all day/week bucketing uses `Calendar.current` in the device-local timezone. **Week starts Monday.** Recency groups: `THIS WEEK` (current Mon-start week), `LAST WEEK` (previous Mon-start week), then a per-month header (e.g. `APRIL 2026`) for anything older.
- **`isProgram`** (drives the `PPL` / `One-offs` filters) is whether the session's workout belongs to the active program (`Program.isActive`); surfaced on the summary projection by the repository.
- **PR box when `prCount == 0`:** the box still renders, value `+0`, sub `—`, plain (non-accent) style.
- **Footer actions** `Duplicate` / `Repeat workout` are model hooks only (spy in the mock); real behavior is BAK-14 / builders — out of scope.

---

## Prerequisites (verify before starting)

This feature sits on two earlier features. The repository protocol + mock and the display projections it needs are introduced **here** (coordinated with BAK-6); the design tokens it needs come from BAK-7.

- [ ] **Step 0a: Design System (BAK-7) must be built first.** Confirm the shared chrome components this plan reuses exist in `Pulse/Core/DesignSystem/`: `TopBar`, `Eyebrow`, `FilterChip`, `StatBox`, `PrTag`, `PrimaryButton`/`SecondaryButton` (the `Btn` styles), plus the type helpers (`Theme.oswald(_:)`, `Theme.mono(_:)`, `Theme.hanken(_:)`). If a component is missing, build it in BAK-7 first — this plan does not redefine design-system primitives.

Run: `ls Pulse/Core/DesignSystem`
Expected: `Theme.swift`, `Palette.swift`, and the component files above. If absent, stop and finish BAK-7.

- [ ] **Step 0b: Data layer (BAK-6) — domain-model additions exist or are added here.** This plan adds the display projections (`SessionSummary`, `SessionDetail`, `LogRow`) and the `SessionRepository` protocol + mock as **part of this feature** (Tasks 1–3), against the existing `WorkoutModels.swift`. If BAK-6 has already landed real Supabase-backed `SessionRepository`/projections, skip Tasks 1–3 and reuse them; otherwise build them here behind the same protocol.

Run: `ls Pulse/Core/Data 2>/dev/null || echo "Core/Data not yet created — this plan creates it"`
Expected: either existing repo files, or the notice (this plan creates `Core/Data`).

- [ ] **Step 0c: Confirm the project generates and the baseline builds.**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 0d: Branch.**

Run: `git checkout -b feature/BAK-17-history-session-detail`

---

## Task 1: Display projection types (TDD)

The screens never render raw `WorkoutSession`s; they render lightweight, presentation-ready projections produced by the repository. These are value types with no logic, but they ship with a Codable round-trip test so their shape is locked.

**Files:**
- Create: `Pulse/Core/Data/SessionProjections.swift`
- Test: `PulseTests/Data/SessionProjectionsTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Data/SessionProjectionsTests.swift`**

```swift
import XCTest
@testable import Pulse

final class SessionProjectionsTests: XCTestCase {
    func testSessionSummaryRoundTrip() throws {
        let summary = SessionSummary(
            id: UUID(),
            dayOfWeek: "WED",
            date: Date(timeIntervalSince1970: 1_716_249_600),
            dayNumber: "21",
            name: "Chest & Tris",
            durationLabel: "58m",
            volumeLabel: "12.4k KG",
            hasPR: true,
            isProgram: true)
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(SessionSummary.self, from: data)
        XCTAssertEqual(decoded, summary)
    }

    func testSessionDetailRoundTripWithLog() throws {
        let detail = SessionDetail(
            id: UUID(),
            dateEyebrow: "WED · MAY 21 · 58M",
            name: "Chest & Tris",
            subLine: "PPL · Week 3 · Day 18 · completed",
            volumeLabel: "12.4",
            volumeUnit: "K",
            prCount: 1,
            prSource: "Flat machine",
            log: [
                LogRow(name: "Flat Machine Press", detail: "15·12·10·8 @ 140kg",
                       volumeLabel: "5.7k", hasPR: true),
                LogRow(name: "Tricep Pushup", detail: "To failure · 18",
                       volumeLabel: "BW", hasPR: false),
            ])
        let data = try JSONEncoder().encode(detail)
        let decoded = try JSONDecoder().decode(SessionDetail.self, from: data)
        XCTAssertEqual(decoded, detail)
        XCTAssertEqual(decoded.log.count, 2)
        XCTAssertEqual(decoded.log.first?.name, "Flat Machine Press")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `SessionSummary` / `SessionDetail` / `LogRow` undefined (`cannot find type ... in scope`).

- [ ] **Step 3: Write `Pulse/Core/Data/SessionProjections.swift`**

```swift
import Foundation

/// One row in the Workout History list. Presentation-ready: every string is
/// already formatted by the data layer so the view does zero computation.
struct SessionSummary: Codable, Equatable, Identifiable {
    let id: UUID
    let dayOfWeek: String   // "WED"
    let date: Date          // used for recency bucketing only
    let dayNumber: String   // "21"
    let name: String
    let durationLabel: String   // "58m"
    let volumeLabel: String     // "12.4k KG"
    let hasPR: Bool
    let isProgram: Bool         // belongs to the active program
}

/// One numbered exercise line on the Session Detail LOG.
struct LogRow: Codable, Equatable, Identifiable {
    var id = UUID()
    let name: String
    let detail: String          // "15·12·10·8 @ 140kg", "3 rounds", "To failure · 18"
    let volumeLabel: String     // "5.7k", "BW"
    let hasPR: Bool
}

/// Full read-only receipt of one completed session.
struct SessionDetail: Codable, Equatable, Identifiable {
    let id: UUID
    let dateEyebrow: String     // "WED · MAY 21 · 58M"
    let name: String            // "Chest & Tris"
    let subLine: String         // "PPL · Week 3 · Day 18 · completed"
    let volumeLabel: String     // "12.4"
    let volumeUnit: String      // "K"
    let prCount: Int
    let prSource: String?       // "Flat machine"; nil when prCount == 0
    let log: [LogRow]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (SessionProjectionsTests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Core/Data/SessionProjections.swift PulseTests/Data/SessionProjectionsTests.swift
git commit -m "feat: session history display projections (summary/detail/log)"
```

---

## Task 2: Recency grouping + Epley PR helper (TDD)

The only real logic in this feature beyond the model: bucketing summaries into Monday-start recency groups, and the Epley est-1RM used to derive whether a session set a PR. Both are pure, deterministic functions so they get tight TDD.

**Files:**
- Create: `Pulse/Core/Data/SessionGrouping.swift`
- Create: `Pulse/Core/Data/EpleyPR.swift`
- Test: `PulseTests/Data/SessionGroupingTests.swift`
- Test: `PulseTests/Data/EpleyPRTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Data/EpleyPRTests.swift`**

```swift
import XCTest
@testable import Pulse

final class EpleyPRTests: XCTestCase {
    func testEpleyFormula() {
        // 100kg × (1 + 10/30) = 133.33…
        XCTAssertEqual(EpleyPR.estimatedOneRepMax(weight: 100, reps: 10),
                       133.333, accuracy: 0.001)
    }

    func testSingleRepEqualsWeight() {
        XCTAssertEqual(EpleyPR.estimatedOneRepMax(weight: 140, reps: 1), 140,
                       accuracy: 0.001)
    }

    func testWarmupsExcludedFromBest() {
        let sets = [
            SessionSet(reps: 5, weight: 40, type: .warmup),   // ignored
            SessionSet(reps: 10, weight: 100, type: .working), // 133.33
            SessionSet(reps: 5, weight: 110, type: .working),  // 128.33
        ]
        XCTAssertEqual(EpleyPR.bestEstimatedOneRepMax(in: sets) ?? -1,
                       133.333, accuracy: 0.001)
    }

    func testAllWarmupsYieldsNil() {
        let sets = [SessionSet(reps: 5, weight: 40, type: .warmup)]
        XCTAssertNil(EpleyPR.bestEstimatedOneRepMax(in: sets))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `EpleyPR` undefined.

- [ ] **Step 3: Write `Pulse/Core/Data/EpleyPR.swift`**

```swift
import Foundation

/// Estimated 1RM (Epley), the single source of truth for PRs across Pulse.
/// `1RM = weight × (1 + reps/30)`. Warmups are excluded; working/AMRAP/etc.
/// count.
enum EpleyPR {
    static func estimatedOneRepMax(weight: Double, reps: Int) -> Double {
        weight * (1.0 + Double(reps) / 30.0)
    }

    /// Best est-1RM among non-warmup sets, or nil if none qualify.
    static func bestEstimatedOneRepMax(in sets: [SessionSet]) -> Double? {
        sets
            .filter { $0.type != .warmup }
            .map { estimatedOneRepMax(weight: $0.weight, reps: $0.reps) }
            .max()
    }
}
```

- [ ] **Step 4: Run to verify EpleyPR passes**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (EpleyPRTests green).

- [ ] **Step 5: Write the failing test `PulseTests/Data/SessionGroupingTests.swift`**

```swift
import XCTest
@testable import Pulse

final class SessionGroupingTests: XCTestCase {
    // Monday 2026-05-25 as the reference "now" (week starts Monday).
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    private func day(_ s: String) -> Date {
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone
        f.dateFormat = "yyyy-MM-dd"; return f.date(from: s)!
    }
    private func summary(_ id: String, _ date: Date) -> SessionSummary {
        SessionSummary(id: UUID(), dayOfWeek: "MON", date: date, dayNumber: "1",
                       name: id, durationLabel: "1m", volumeLabel: "1k KG",
                       hasPR: false, isProgram: true)
    }

    func testThisWeekAndLastWeekBuckets() {
        let now = day("2026-05-28") // Thursday this week
        let groups = SessionGrouping.groups(
            for: [
                summary("a", day("2026-05-27")), // this week
                summary("b", day("2026-05-26")), // this week
                summary("c", day("2026-05-20")), // last week
            ],
            now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.label), ["THIS WEEK", "LAST WEEK"])
        XCTAssertEqual(groups[0].sessions.map(\.name), ["a", "b"]) // most-recent first
        XCTAssertEqual(groups[1].sessions.map(\.name), ["c"])
    }

    func testOlderSessionsGetMonthHeaders() {
        let now = day("2026-05-28")
        let groups = SessionGrouping.groups(
            for: [summary("apr", day("2026-04-10"))],
            now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.label), ["APRIL 2026"])
    }

    func testEmptyInputYieldsNoGroups() {
        XCTAssertTrue(SessionGrouping.groups(for: [], now: day("2026-05-28"),
                                             calendar: cal).isEmpty)
    }

    func testSingleBucketHasNoEmptyHeaders() {
        let now = day("2026-05-28")
        let groups = SessionGrouping.groups(
            for: [summary("a", day("2026-05-27"))],
            now: now, calendar: cal)
        XCTAssertEqual(groups.map(\.label), ["THIS WEEK"])
    }
}
```

- [ ] **Step 6: Run to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `SessionGrouping` / `SessionGroup` undefined.

- [ ] **Step 7: Write `Pulse/Core/Data/SessionGrouping.swift`**

```swift
import Foundation

/// A labelled recency bucket of session summaries (most-recent first).
struct SessionGroup: Equatable, Identifiable {
    var id: String { label }
    let label: String
    let sessions: [SessionSummary]
}

/// Buckets summaries into Monday-start recency groups: THIS WEEK, LAST WEEK,
/// then one header per older month ("APRIL 2026"). Pure + injectable calendar
/// so it is deterministic in tests; production passes `Calendar.current`.
enum SessionGrouping {
    static func groups(for summaries: [SessionSummary],
                       now: Date = Date(),
                       calendar: Calendar = .current) -> [SessionGroup] {
        guard !summaries.isEmpty else { return [] }

        let sorted = summaries.sorted { $0.date > $1.date } // most-recent first
        let thisWeekStart = startOfWeek(for: now, calendar: calendar)
        let lastWeekStart = calendar.date(byAdding: .day, value: -7,
                                          to: thisWeekStart)!

        var thisWeek: [SessionSummary] = []
        var lastWeek: [SessionSummary] = []
        var older: [SessionSummary] = []
        for s in sorted {
            if s.date >= thisWeekStart { thisWeek.append(s) }
            else if s.date >= lastWeekStart { lastWeek.append(s) }
            else { older.append(s) }
        }

        var result: [SessionGroup] = []
        if !thisWeek.isEmpty { result.append(.init(label: "THIS WEEK", sessions: thisWeek)) }
        if !lastWeek.isEmpty { result.append(.init(label: "LAST WEEK", sessions: lastWeek)) }

        // Older: one group per calendar month, preserving most-recent-first.
        var bucketed: [String: [SessionSummary]] = [:]
        var order: [String] = []
        for s in older {
            let key = monthLabel(for: s.date, calendar: calendar)
            if bucketed[key] == nil { order.append(key) }
            bucketed[key, default: []].append(s)
        }
        for key in order { result.append(.init(label: key, sessions: bucketed[key]!)) }
        return result
    }

    private static func startOfWeek(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents(
            [.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: comps)!
    }

    private static func monthLabel(for date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "MMMM yyyy"
        return f.string(from: date).uppercased()
    }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (SessionGroupingTests + EpleyPRTests green).

- [ ] **Step 9: Commit**

```bash
git add Pulse/Core/Data/SessionGrouping.swift Pulse/Core/Data/EpleyPR.swift \
  PulseTests/Data/SessionGroupingTests.swift PulseTests/Data/EpleyPRTests.swift
git commit -m "feat: recency grouping (Mon-start) and Epley est-1RM PR helper"
```

---

## Task 3: `SessionRepository` protocol + in-memory mock (TDD)

The repository abstraction the screens bind to, plus the mock seeded from the prototype's `RECENT` list and the `Chest & Tris` log. The mock also records `duplicate`/`repeat` calls (spy) for the footer-action tests.

**Files:**
- Create: `Pulse/Core/Data/SessionRepository.swift`
- Create: `Pulse/Core/Data/Mock/MockSessionRepository.swift`
- Test: `PulseTests/Data/MockSessionRepositoryTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Data/MockSessionRepositoryTests.swift`**

```swift
import XCTest
@testable import Pulse

final class MockSessionRepositoryTests: XCTestCase {
    func testRecentSessionsAreSeededMostRecentFirst() async throws {
        let repo = MockSessionRepository.seeded()
        let summaries = try await repo.recentSessions(limit: 50)
        XCTAssertEqual(summaries.count, 5)
        XCTAssertEqual(summaries.first?.name, "Legs")          // yesterday
        XCTAssertEqual(summaries.last?.name, "Chest & Tris")   // oldest seeded
        // Volume copy is KG, not LBS (units decision).
        XCTAssertTrue(summaries.first?.volumeLabel.hasSuffix("KG") ?? false)
    }

    func testTwoSeededSessionsHavePRs() async throws {
        let repo = MockSessionRepository.seeded()
        let prs = try await repo.recentSessions(limit: 50).filter(\.hasPR)
        XCTAssertEqual(prs.count, 2) // Legs + Chest & Tris
    }

    func testSessionDetailForKnownID() async throws {
        let repo = MockSessionRepository.seeded()
        let id = try await repo.recentSessions(limit: 50)
            .first { $0.name == "Chest & Tris" }!.id
        let detail = try await repo.session(id: id)
        XCTAssertEqual(detail.name, "Chest & Tris")
        XCTAssertEqual(detail.log.count, 7)
        XCTAssertEqual(detail.log.last?.volumeLabel, "BW")
        XCTAssertEqual(detail.prCount, 1)
        XCTAssertEqual(detail.prSource, "Flat machine")
    }

    func testUnknownIDThrows() async {
        let repo = MockSessionRepository.seeded()
        do {
            _ = try await repo.session(id: UUID())
            XCTFail("expected unknownSession error")
        } catch let SessionRepositoryError.unknownSession(id) {
            XCTAssertNotNil(id)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testEmptyRepoReturnsNoSessions() async throws {
        let repo = MockSessionRepository(summaries: [], details: [:])
        let summaries = try await repo.recentSessions(limit: 50)
        XCTAssertTrue(summaries.isEmpty)
    }

    func testFailingRepoThrows() async {
        let repo = MockSessionRepository.failing()
        do {
            _ = try await repo.recentSessions(limit: 50)
            XCTFail("expected failure")
        } catch { /* expected */ }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `MockSessionRepository` / `SessionRepository` / `SessionRepositoryError` undefined.

- [ ] **Step 3: Write `Pulse/Core/Data/SessionRepository.swift`**

```swift
import Foundation

enum SessionRepositoryError: Error, Equatable {
    case unknownSession(UUID)
    case loadFailed
}

/// Read access to logged sessions for the history stack. UI-first: backed by
/// `MockSessionRepository` now; a Supabase implementation lands behind this
/// same protocol in BAK-6's live work.
protocol SessionRepository {
    /// Session summaries, most-recent first, capped at `limit`.
    func recentSessions(limit: Int) async throws -> [SessionSummary]
    /// Full read-only detail for one session.
    func session(id: UUID) async throws -> SessionDetail
}
```

- [ ] **Step 4: Write `Pulse/Core/Data/Mock/MockSessionRepository.swift`**

```swift
import Foundation

/// In-memory `SessionRepository`. `seeded()` reproduces the design prototype's
/// RECENT list and the Chest & Tris session log (units rendered in KG). It also
/// spies on footer-action calls so SessionDetailModel tests can assert hooks
/// fire without real navigation.
final class MockSessionRepository: SessionRepository {
    private let summaries: [SessionSummary]
    private let details: [UUID: SessionDetail]
    private let failOnLoad: Bool

    private(set) var duplicatedIDs: [UUID] = []
    private(set) var repeatedIDs: [UUID] = []

    init(summaries: [SessionSummary],
         details: [UUID: SessionDetail],
         failOnLoad: Bool = false) {
        self.summaries = summaries
        self.details = details
        self.failOnLoad = failOnLoad
    }

    func recentSessions(limit: Int) async throws -> [SessionSummary] {
        if failOnLoad { throw SessionRepositoryError.loadFailed }
        return Array(summaries.prefix(limit))
    }

    func session(id: UUID) async throws -> SessionDetail {
        if failOnLoad { throw SessionRepositoryError.loadFailed }
        guard let detail = details[id] else {
            throw SessionRepositoryError.unknownSession(id)
        }
        return detail
    }

    func duplicate(id: UUID) { duplicatedIDs.append(id) }
    func repeatWorkout(id: UUID) { repeatedIDs.append(id) }

    // MARK: - Fixtures

    static func failing() -> MockSessionRepository {
        MockSessionRepository(summaries: [], details: [:], failOnLoad: true)
    }

    /// Mirrors the prototype's RECENT array + Chest & Tris detail log.
    static func seeded(now: Date = Date()) -> MockSessionRepository {
        let cal = Calendar.current
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: now)! }

        let chestID = UUID()
        let raw: [(id: UUID, dy: String, day: String, name: String, dur: String,
                   vol: String, pr: Bool, program: Bool, ago: Int)] = [
            (UUID(), "TUE", "1",  "Legs",        "71m", "18.7k KG", true,  true,  1),
            (UUID(), "MON", "26", "Back & Bis",  "62m", "14.2k KG", false, true,  5),
            (UUID(), "FRI", "23", "Arms",        "45m", "8.4k KG",  false, false, 8),
            (UUID(), "THU", "22", "Shoulders",   "55m", "11.8k KG", false, true,  9),
            (chestID, "WED", "21", "Chest & Tris", "58m", "12.4k KG", true, true, 10),
        ]
        let summaries = raw.map {
            SessionSummary(id: $0.id, dayOfWeek: $0.dy, date: daysAgo($0.ago),
                           dayNumber: $0.day, name: $0.name,
                           durationLabel: $0.dur, volumeLabel: $0.vol,
                           hasPR: $0.pr, isProgram: $0.program)
        }

        let chestDetail = SessionDetail(
            id: chestID,
            dateEyebrow: "WED · MAY 21 · 58M",
            name: "Chest & Tris",
            subLine: "PPL · Week 3 · Day 18 · completed",
            volumeLabel: "12.4", volumeUnit: "K",
            prCount: 1, prSource: "Flat machine",
            log: [
                LogRow(name: "Flat Machine Press", detail: "15·12·10·8 @ 140kg", volumeLabel: "5.7k", hasPR: true),
                LogRow(name: "Incline DB Press",   detail: "15·12·10·8 @ 60kg",  volumeLabel: "2.7k", hasPR: false),
                LogRow(name: "Close Grip DB",       detail: "12·10·8 @ 55kg",     volumeLabel: "1.7k", hasPR: false),
                LogRow(name: "Tri / Lat superset",  detail: "3 rounds",           volumeLabel: "1.4k", hasPR: false),
                LogRow(name: "Shoulder Press",      detail: "12·10·8·6 @ 90kg",   volumeLabel: "800",  hasPR: false),
                LogRow(name: "Plate Tri Ext",       detail: "3×12 @ 70kg",        volumeLabel: "2.5k", hasPR: false),
                LogRow(name: "Tricep Pushup",       detail: "To failure · 18",    volumeLabel: "BW",   hasPR: false),
            ])

        return MockSessionRepository(summaries: summaries,
                                     details: [chestID: chestDetail])
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (MockSessionRepositoryTests green).

- [ ] **Step 6: Commit**

```bash
git add Pulse/Core/Data/SessionRepository.swift Pulse/Core/Data/Mock/MockSessionRepository.swift \
  PulseTests/Data/MockSessionRepositoryTests.swift
git commit -m "feat: SessionRepository protocol + seeded in-memory mock"
```

---

## Task 4: `WorkoutHistoryModel` (TDD)

The `@Observable` model behind the History screen: loads summaries, holds the selected filter, and derives recency groups + empty/phase state. All logic, so full TDD.

**Files:**
- Create: `Pulse/Features/WorkoutHistory/WorkoutHistoryModel.swift`
- Test: `PulseTests/WorkoutHistory/WorkoutHistoryModelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/WorkoutHistory/WorkoutHistoryModelTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class WorkoutHistoryModelTests: XCTestCase {
    private func model(_ repo: SessionRepository) -> WorkoutHistoryModel {
        WorkoutHistoryModel(repository: repo, now: Date())
    }

    func testLoadPopulatesSessionsMostRecentFirstAndLoadedPhase() async {
        let m = model(MockSessionRepository.seeded())
        await m.load()
        XCTAssertEqual(m.phase, .loaded)
        XCTAssertEqual(m.sessions.first?.name, "Legs")
        XCTAssertEqual(m.sessions.count, 5)
    }

    func testDefaultFilterIsAll() {
        let m = model(MockSessionRepository.seeded())
        XCTAssertEqual(m.selectedFilter, .all)
    }

    func testFilterPRShowsOnlyPRSessions() async {
        let m = model(MockSessionRepository.seeded())
        await m.load()
        m.select(.pr)
        let names = m.filteredGroups.flatMap { $0.sessions.map(\.name) }
        XCTAssertEqual(Set(names), ["Legs", "Chest & Tris"])
    }

    func testFilterProgramAndOneOff() async {
        let m = model(MockSessionRepository.seeded())
        await m.load()
        m.select(.oneOff)
        XCTAssertEqual(m.filteredGroups.flatMap { $0.sessions.map(\.name) }, ["Arms"])
        m.select(.program)
        let program = m.filteredGroups.flatMap { $0.sessions.map(\.name) }
        XCTAssertFalse(program.contains("Arms"))
        XCTAssertTrue(program.contains("Legs"))
    }

    func testSelectAllRestoresEverything() async {
        let m = model(MockSessionRepository.seeded())
        await m.load()
        m.select(.pr); m.select(.all)
        XCTAssertEqual(m.filteredGroups.flatMap { $0.sessions }.count, 5)
    }

    func testFilteredGroupsHaveRecencyLabels() async {
        let m = model(MockSessionRepository.seeded())
        await m.load()
        XCTAssertFalse(m.filteredGroups.isEmpty)
        XCTAssertEqual(m.filteredGroups.first?.label, "THIS WEEK")
    }

    func testFilterWithNoMatchesIsEmptyAndProducesNoGroups() async {
        // Repo with only a one-off session; .pr yields nothing.
        let oneOff = SessionSummary(
            id: UUID(), dayOfWeek: "FRI", date: Date(), dayNumber: "1",
            name: "Arms", durationLabel: "45m", volumeLabel: "8k KG",
            hasPR: false, isProgram: false)
        let repo = MockSessionRepository(summaries: [oneOff], details: [:])
        let m = model(repo)
        await m.load()
        m.select(.pr)
        XCTAssertTrue(m.isEmpty)
        XCTAssertTrue(m.filteredGroups.isEmpty)
    }

    func testEmptyRepoSetsEmptyPhase() async {
        let m = model(MockSessionRepository(summaries: [], details: [:]))
        await m.load()
        XCTAssertEqual(m.phase, .empty)
    }

    func testFailingRepoSetsErrorPhaseAndNoStaleData() async {
        let m = model(MockSessionRepository.failing())
        await m.load()
        if case .error = m.phase {} else { XCTFail("expected .error") }
        XCTAssertTrue(m.sessions.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `WorkoutHistoryModel` / `HistoryFilter` / `LoadPhase` undefined.

- [ ] **Step 3: Write `Pulse/Features/WorkoutHistory/WorkoutHistoryModel.swift`**

```swift
import Foundation
import Observation

/// Shared loading state for the history-stack screens.
enum LoadPhase: Equatable {
    case loading, loaded, empty
    case error(String)
}

enum HistoryFilter: CaseIterable {
    case all, program, oneOff, pr

    var chipLabel: String {
        switch self {
        case .all: "All"
        case .program: "PPL"
        case .oneOff: "One-offs"
        case .pr: "+ PR"
        }
    }
}

@MainActor
@Observable
final class WorkoutHistoryModel {
    private let repository: SessionRepository
    private let now: Date

    var phase: LoadPhase = .loading
    private(set) var sessions: [SessionSummary] = []
    var selectedFilter: HistoryFilter = .all

    init(repository: SessionRepository, now: Date = Date()) {
        self.repository = repository
        self.now = now
    }

    func load() async {
        phase = .loading
        do {
            let loaded = try await repository.recentSessions(limit: 200)
            sessions = loaded
            phase = loaded.isEmpty ? .empty : .loaded
        } catch {
            sessions = []
            phase = .error("Couldn't load your history.")
        }
    }

    func select(_ filter: HistoryFilter) {
        selectedFilter = filter
    }

    private var filteredSessions: [SessionSummary] {
        switch selectedFilter {
        case .all: sessions
        case .program: sessions.filter(\.isProgram)
        case .oneOff: sessions.filter { !$0.isProgram }
        case .pr: sessions.filter(\.hasPR)
        }
    }

    var filteredGroups: [SessionGroup] {
        SessionGrouping.groups(for: filteredSessions, now: now,
                               calendar: .current)
    }

    var isEmpty: Bool { filteredSessions.isEmpty }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (WorkoutHistoryModelTests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/WorkoutHistory/WorkoutHistoryModel.swift \
  PulseTests/WorkoutHistory/WorkoutHistoryModelTests.swift
git commit -m "feat: WorkoutHistoryModel (load, filter, recency grouping)"
```

---

## Task 5: `SessionDetailModel` (TDD)

The `@Observable` model behind Session Detail: loads one session by id, maps log rows, exposes `duplicate()` / `repeatWorkout()` hooks. Logic, so full TDD.

**Files:**
- Create: `Pulse/Features/SessionDetail/SessionDetailModel.swift`
- Test: `PulseTests/SessionDetail/SessionDetailModelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/SessionDetail/SessionDetailModelTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class SessionDetailModelTests: XCTestCase {
    private func knownID(_ repo: MockSessionRepository) async -> UUID {
        try! await repo.recentSessions(limit: 50)
            .first { $0.name == "Chest & Tris" }!.id
    }

    func testLoadPopulatesSessionAndLoadedPhase() async {
        let repo = MockSessionRepository.seeded()
        let id = await knownID(repo)
        let m = SessionDetailModel(sessionID: id, repository: repo)
        await m.load()
        XCTAssertEqual(m.phase, .loaded)
        XCTAssertEqual(m.session?.name, "Chest & Tris")
    }

    func testLogRowsPreserveOrderAndMapFields() async {
        let repo = MockSessionRepository.seeded()
        let id = await knownID(repo)
        let m = SessionDetailModel(sessionID: id, repository: repo)
        await m.load()
        let log = m.session?.log ?? []
        XCTAssertEqual(log.count, 7)
        XCTAssertEqual(log.first?.name, "Flat Machine Press")
        XCTAssertTrue(log.first?.hasPR ?? false)
        // Superset row + bodyweight/failure row map correctly.
        XCTAssertEqual(log[3].name, "Tri / Lat superset")
        XCTAssertEqual(log[3].detail, "3 rounds")
        XCTAssertEqual(log.last?.detail, "To failure · 18")
        XCTAssertEqual(log.last?.volumeLabel, "BW")
    }

    func testZeroPRDetailRendersPlusZeroDash() async {
        let id = UUID()
        let detail = SessionDetail(
            id: id, dateEyebrow: "MON · MAY 26 · 62M", name: "Back & Bis",
            subLine: "PPL · Week 3 · Day 17 · completed",
            volumeLabel: "14.2", volumeUnit: "K", prCount: 0, prSource: nil,
            log: [LogRow(name: "Row", detail: "10 @ 80kg", volumeLabel: "800", hasPR: false)])
        let repo = MockSessionRepository(summaries: [], details: [id: detail])
        let m = SessionDetailModel(sessionID: id, repository: repo)
        await m.load()
        XCTAssertEqual(m.session?.prCount, 0)
        XCTAssertNil(m.session?.prSource)
        XCTAssertEqual(m.prValueLabel, "+0")
        XCTAssertEqual(m.prSubLabel, "—")
    }

    func testUnknownIDSetsErrorPhase() async {
        let m = SessionDetailModel(sessionID: UUID(),
                                   repository: MockSessionRepository.seeded())
        await m.load()
        if case .error = m.phase {} else { XCTFail("expected .error") }
        XCTAssertNil(m.session)
    }

    func testDuplicateAndRepeatInvokeHooks() async {
        let repo = MockSessionRepository.seeded()
        let id = await knownID(repo)
        let m = SessionDetailModel(sessionID: id, repository: repo)
        await m.load()
        m.duplicate()
        m.repeatWorkout()
        XCTAssertEqual(repo.duplicatedIDs, [id])
        XCTAssertEqual(repo.repeatedIDs, [id])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `SessionDetailModel` undefined.

- [ ] **Step 3: Write `Pulse/Features/SessionDetail/SessionDetailModel.swift`**

```swift
import Foundation
import Observation

@MainActor
@Observable
final class SessionDetailModel {
    private let sessionID: UUID
    private let repository: SessionRepository

    var phase: LoadPhase = .loading
    private(set) var session: SessionDetail?

    init(sessionID: UUID, repository: SessionRepository) {
        self.sessionID = sessionID
        self.repository = repository
    }

    func load() async {
        phase = .loading
        do {
            session = try await repository.session(id: sessionID)
            phase = .loaded
        } catch {
            session = nil
            phase = .error("Couldn't load this session.")
        }
    }

    /// PR StatBox value; "+0" when no PR was set (box still renders, plain style).
    var prValueLabel: String { "+\(session?.prCount ?? 0)" }
    /// PR StatBox sub; em-dash when there is no PR source.
    var prSubLabel: String { session?.prSource ?? "—" }
    /// Whether the PR box uses the accent-bordered variant.
    var prIsAccent: Bool { (session?.prCount ?? 0) > 0 }

    func duplicate() {
        (repository as? MockSessionRepository)?.duplicate(id: sessionID)
        // Real Duplicate behavior (create editable copy) is BAK-14 / builders.
    }

    func repeatWorkout() {
        (repository as? MockSessionRepository)?.repeatWorkout(id: sessionID)
        // Real Repeat behavior (launch active flow) is BAK-14.
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (SessionDetailModelTests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/SessionDetail/SessionDetailModel.swift \
  PulseTests/SessionDetail/SessionDetailModelTests.swift
git commit -m "feat: SessionDetailModel (load, log mapping, PR box, action hooks)"
```

---

## Task 6: `WorkoutHistoryView` (SwiftUI assembly + preview + UI test)

Pure view assembly against the model. Validated by `#Preview` and an XCUITest, not line-by-line TDD. Uses BAK-7 components (`TopBar`, `Eyebrow`, `FilterChip`, `PrTag`) and `Theme` tokens only.

**Files:**
- Create: `Pulse/Features/WorkoutHistory/WorkoutHistoryView.swift`
- Create: `PulseUITests/HistoryUITests.swift`

- [ ] **Step 1: Write `Pulse/Features/WorkoutHistory/WorkoutHistoryView.swift`**

```swift
import SwiftUI

struct WorkoutHistoryView: View {
    @Environment(Theme.self) private var theme
    @State private var model: WorkoutHistoryModel
    let onSelectSession: (UUID) -> Void

    init(model: WorkoutHistoryModel, onSelectSession: @escaping (UUID) -> Void) {
        _model = State(initialValue: model)
        self.onSelectSession = onSelectSession
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar(eyebrow: "WORKOUT HISTORY", trailing: .dots)

            Text("History.")
                .font(theme.hanken(30))
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("history.h1")

            Text(subLine)
                .font(theme.hanken(13))
                .foregroundStyle(theme.inkSoft)

            filterChips
                .padding(.top, theme.spacing[2])

            content
        }
        .padding(.horizontal, theme.spacing[3])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg.ignoresSafeArea())
        .task { await model.load() }
    }

    private var subLine: String {
        "\(model.sessions.count) sessions · since Feb 2024"
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing[1]) {
                ForEach(HistoryFilter.allCases, id: \.self) { filter in
                    FilterChip(label: filter.chipLabel,
                               isOn: model.selectedFilter == filter) {
                        model.select(filter)
                    }
                    .accessibilityIdentifier("history.chip.\(filter.chipLabel)")
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, theme.spacing[5])
                .accessibilityIdentifier("history.loading")
        case .error(let message):
            Text(message)
                .font(theme.hanken(14))
                .foregroundStyle(theme.inkSoft)
                .padding(.top, theme.spacing[5])
                .accessibilityIdentifier("history.error")
        case .empty, .loaded where model.isEmpty:
            Text(emptyMessage)
                .font(theme.hanken(14))
                .foregroundStyle(theme.inkSoft)
                .padding(.top, theme.spacing[5])
                .accessibilityIdentifier("history.empty")
        case .loaded:
            groupedList
        }
    }

    private var emptyMessage: String {
        model.sessions.isEmpty ? "No sessions yet"
                               : "No sessions match this filter"
    }

    private var groupedList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing[1]) {
                ForEach(model.filteredGroups) { group in
                    Eyebrow(group.label)
                        .padding(.top, theme.spacing[1])
                    ForEach(group.sessions) { session in
                        SessionRow(session: session)
                            .accessibilityIdentifier("history.row.\(session.name)")
                            .onTapGesture { onSelectSession(session.id) }
                    }
                }
            }
            .padding(.top, theme.spacing[3])
        }
    }
}

/// A single history list row: date block · name/sub · optional PR · chevron.
private struct SessionRow: View {
    @Environment(Theme.self) private var theme
    let session: SessionSummary

    var body: some View {
        HStack(spacing: theme.spacing[2]) {
            VStack(alignment: .leading, spacing: 0) {
                Eyebrow(session.dayOfWeek).font(theme.mono(9))
                Text(session.dayNumber)
                    .font(theme.oswald(16))
                    .foregroundStyle(theme.ink)
            }
            .frame(minWidth: 46, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(theme.hanken(14))
                    .foregroundStyle(theme.ink)
                Text("\(session.durationLabel) · \(session.volumeLabel)")
                    .font(theme.hanken(11))
                    .foregroundStyle(theme.inkSoft)
            }
            Spacer()
            if session.hasPR { PrTag() }
            Image(systemName: "chevron.right")
                .foregroundStyle(theme.inkFaint)
        }
        .padding(.vertical, theme.spacing[2])
        .padding(.horizontal, theme.spacing[3])
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
        .contentShape(Rectangle())
    }
}

#Preview("Loaded") {
    WorkoutHistoryView(model: WorkoutHistoryModel(repository: .init(seeded: true)),
                       onSelectSession: { _ in })
        .environment(Theme())
}
```

> Note: the `#Preview` uses a convenience `WorkoutHistoryModel(repository: MockSessionRepository.seeded())`. If a `.init(seeded:)` shorthand does not exist, write `WorkoutHistoryModel(repository: MockSessionRepository.seeded())` directly. The model auto-loads via `.task`.

- [ ] **Step 2: Build to confirm the view compiles and the preview resolves**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Write the UI test `PulseUITests/HistoryUITests.swift`** (covers AC2/AC3/AC4/AC5/AC6)

```swift
import XCTest

final class HistoryUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSeed", "history"]
        app.launch()
        return app
    }

    func testHistoryChromeAndDefaultFilter() {
        let app = launch()
        navigateToHistory(app)
        XCTAssertTrue(app.staticTexts["history.h1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["WORKOUT HISTORY"].exists)
        XCTAssertTrue(app.buttons["history.chip.All"].exists)
        XCTAssertTrue(app.buttons["history.chip.+ PR"].exists)
    }

    func testGroupedRowsRender() {
        let app = launch()
        navigateToHistory(app)
        XCTAssertTrue(app.staticTexts["THIS WEEK"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["history.row.Legs"].exists)
    }

    func testPRFilterNarrowsThenAllRestores() {
        let app = launch()
        navigateToHistory(app)
        app.buttons["history.chip.+ PR"].tap()
        XCTAssertTrue(app.otherElements["history.row.Legs"].exists)
        XCTAssertFalse(app.otherElements["history.row.Arms"].exists)
        app.buttons["history.chip.All"].tap()
        XCTAssertTrue(app.otherElements["history.row.Arms"].waitForExistence(timeout: 2))
    }

    /// You → Workout history. Adjust to the You tab's actual NavRow identifier.
    private func navigateToHistory(_ app: XCUIApplication) {
        app.tabBars.buttons["You"].tap()
        app.buttons["you.nav.workoutHistory"].tap()
    }
}
```

> The UI tests assume the app honors a `-uiTestSeed history` launch argument that injects `MockSessionRepository.seeded()` and the You-tab NavRow exposes identifier `you.nav.workoutHistory`. Wiring both is Task 8.

- [ ] **Step 4: Commit**

```bash
git add Pulse/Features/WorkoutHistory/WorkoutHistoryView.swift \
  PulseUITests/HistoryUITests.swift
git commit -m "feat: WorkoutHistoryView (grouped, filterable list) + UI tests"
```

---

## Task 7: `SessionDetailView` (SwiftUI assembly + preview + UI test)

Pure view assembly. Validated by `#Preview` and an XCUITest. Uses BAK-7 `StatBox` (with accent variant), `Eyebrow`, `PrTag`, `PrimaryButton`/`SecondaryButton`, `Theme` tokens.

**Files:**
- Create: `Pulse/Features/SessionDetail/SessionDetailView.swift`
- Create: `PulseUITests/SessionDetailUITests.swift`

- [ ] **Step 1: Write `Pulse/Features/SessionDetail/SessionDetailView.swift`**

```swift
import SwiftUI

struct SessionDetailView: View {
    @Environment(Theme.self) private var theme
    @State private var model: SessionDetailModel

    init(model: SessionDetailModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar(eyebrow: model.session?.dateEyebrow ?? "", trailing: .dots)
            content
        }
        .padding(.horizontal, theme.spacing[3])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg.ignoresSafeArea())
        .task { await model.load() }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, theme.spacing[5])
                .accessibilityIdentifier("session.loading")
        case .error(let message):
            Text(message)
                .font(theme.hanken(14))
                .foregroundStyle(theme.inkSoft)
                .padding(.top, theme.spacing[5])
                .accessibilityIdentifier("session.error")
        case .empty:
            Text("Session not found")
                .font(theme.hanken(14))
                .foregroundStyle(theme.inkSoft)
        case .loaded:
            if let session = model.session { loaded(session) }
        }
    }

    @ViewBuilder private func loaded(_ session: SessionDetail) -> some View {
        Text(session.name)
            .font(theme.hanken(30))
            .foregroundStyle(theme.ink)
            .accessibilityIdentifier("session.h1")
        Text(session.subLine)
            .font(theme.hanken(13))
            .foregroundStyle(theme.inkSoft)

        HStack(spacing: theme.spacing[1]) {
            StatBox(label: "VOLUME", value: session.volumeLabel,
                    unit: session.volumeUnit, sub: "kg", accent: false)
            StatBox(label: "PR", value: model.prValueLabel, unit: nil,
                    sub: model.prSubLabel, accent: model.prIsAccent)
                .accessibilityIdentifier("session.prBox")
        }
        .padding(.top, theme.spacing[3])

        Eyebrow("LOG").padding(.vertical, theme.spacing[2])

        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing[1]) {
                ForEach(Array(session.log.enumerated()), id: \.element.id) { index, row in
                    LogRowView(index: index + 1, row: row)
                }
            }
        }

        footer
            .padding(.vertical, theme.spacing[2])
    }

    private var footer: some View {
        HStack(spacing: theme.spacing[1]) {
            SecondaryButton("Duplicate", size: .small) { model.duplicate() }
                .accessibilityIdentifier("session.duplicate")
            PrimaryButton("Repeat workout →", size: .small) { model.repeatWorkout() }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("session.repeat")
        }
    }
}

/// One numbered LOG row: index badge · name/detail · optional PR · volume.
private struct LogRowView: View {
    @Environment(Theme.self) private var theme
    let index: Int
    let row: LogRow

    var body: some View {
        HStack(spacing: theme.spacing[2]) {
            Text("\(index)")
                .font(theme.mono(10))
                .foregroundStyle(theme.onAccent)
                .frame(width: 20, height: 20)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name).font(theme.hanken(13)).foregroundStyle(theme.ink)
                Text(row.detail).font(theme.mono(9)).foregroundStyle(theme.inkSoft)
            }
            Spacer()
            if row.hasPR { PrTag() }
            Text(row.volumeLabel)
                .font(theme.hanken(14))
                .foregroundStyle(theme.ink)
        }
        .padding(.vertical, theme.spacing[2])
        .padding(.horizontal, theme.spacing[3])
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
    }
}

#Preview("Loaded") {
    let repo = MockSessionRepository.seeded()
    let id = (try? awaitFirstChestID(repo)) ?? UUID()
    return SessionDetailView(model: SessionDetailModel(sessionID: id, repository: repo))
        .environment(Theme())
}

// Preview helper: synchronously resolve the seeded Chest & Tris id.
private func awaitFirstChestID(_ repo: MockSessionRepository) throws -> UUID {
    var result: UUID?
    let sem = DispatchSemaphore(value: 0)
    Task { result = try? await repo.recentSessions(limit: 50)
        .first { $0.name == "Chest & Tris" }?.id; sem.signal() }
    sem.wait()
    return result ?? UUID()
}
```

> Note: the preview helper resolves the seeded id; if it complicates compilation, hardcode a known id by exposing a `MockSessionRepository.seededChestID` static instead. Keep the preview simple — its only job is visual validation.

- [ ] **Step 2: Build to confirm the view compiles**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Write the UI test `PulseUITests/SessionDetailUITests.swift`** (covers AC8/AC9/AC10/AC11)

```swift
import XCTest

final class SessionDetailUITests: XCTestCase {
    private func launchToDetail() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSeed", "history"]
        app.launch()
        app.tabBars.buttons["You"].tap()
        app.buttons["you.nav.workoutHistory"].tap()
        app.otherElements["history.row.Chest & Tris"].tap()
        return app
    }

    func testDetailChromeAndStats() {
        let app = launchToDetail()
        XCTAssertTrue(app.staticTexts["session.h1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["WED · MAY 21 · 58M"].exists)
        XCTAssertTrue(app.otherElements["session.prBox"].exists)
    }

    func testLogAndFooterButtons() {
        let app = launchToDetail()
        XCTAssertTrue(app.staticTexts["Flat Machine Press"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["To failure · 18"].exists)
        XCTAssertTrue(app.buttons["session.duplicate"].exists)
        XCTAssertTrue(app.buttons["session.repeat"].exists)
    }

    func testBackReturnsToHistory() {
        let app = launchToDetail()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["history.h1"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add Pulse/Features/SessionDetail/SessionDetailView.swift \
  PulseUITests/SessionDetailUITests.swift
git commit -m "feat: SessionDetailView (stats, LOG, footer actions) + UI tests"
```

---

## Task 8: Navigation wiring + UI-test seeding (You → History → Session Detail)

Wire the two screens into the app: a NavRow in the You tab pushes History; a History row pushes `SessionDetailView(sessionID:)`. Add the `-uiTestSeed` launch-argument hook so UI tests get the seeded mock and deterministic navigation.

**Files:**
- Modify: `Pulse/Features/You/YouView.swift`
- Create: `Pulse/Features/WorkoutHistory/HistoryRoute.swift`
- Modify: `Pulse/App/AppShell.swift` (or wherever the `Theme` env + repository injection live)

- [ ] **Step 1: Add a navigation route enum `Pulse/Features/WorkoutHistory/HistoryRoute.swift`**

```swift
import Foundation

/// Destinations reachable from the history stack.
enum HistoryRoute: Hashable {
    case history
    case sessionDetail(UUID)
}
```

- [ ] **Step 2: Add the `Workout history` NavRow + stack into `YouView`**

In `YouView`, wrap the content in a `NavigationStack(path:)` (if not already) and add the row. Use the existing `NavRow` design-system component; add the accessibility identifier the UI tests expect.

```swift
// Inside YouView's body, in the appropriate section:
NavigationLink(value: HistoryRoute.history) {
    NavRow(title: "Workout history", systemImage: "clock.arrow.circlepath")
}
.accessibilityIdentifier("you.nav.workoutHistory")
.navigationDestination(for: HistoryRoute.self) { route in
    switch route {
    case .history:
        WorkoutHistoryView(
            model: WorkoutHistoryModel(repository: sessionRepository),
            onSelectSession: { id in path.append(HistoryRoute.sessionDetail(id)) })
    case .sessionDetail(let id):
        SessionDetailView(
            model: SessionDetailModel(sessionID: id, repository: sessionRepository))
    }
}
```

> `sessionRepository` and `path` come from the You feature's environment/state. If You does not yet own a `NavigationStack` path, introduce `@State private var path = NavigationPath()` and pass it as `NavigationStack(path: $path)`. The `onSelectSession` closure appends `.sessionDetail(id)` so History → Detail uses the same stack and the system back button returns to History (AC15).

- [ ] **Step 3: Inject the repository + UI-test seed at the app root**

In the app root (`AppShell` or `PulseApp`), choose the repository based on the launch argument and inject `Theme`:

```swift
private var sessionRepository: SessionRepository {
    if ProcessInfo.processInfo.arguments.contains("-uiTestSeed") {
        return MockSessionRepository.seeded()
    }
    return MockSessionRepository.seeded() // UI-first: mock everywhere for now
}
```

Pass `sessionRepository` down to `YouView` (initializer or `.environment`). Keep the existing `.environment(Theme())` injection so both screens resolve `@Environment(Theme.self)`.

- [ ] **Step 4: Regenerate, build, and run the full test suite**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: `TEST SUCCEEDED` — all unit tests (Tasks 1–5) and UI tests (Tasks 6–7) pass, including `HistoryUITests` navigation and `SessionDetailUITests.testBackReturnsToHistory` (AC1/AC7/AC15).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/You/YouView.swift \
  Pulse/Features/WorkoutHistory/HistoryRoute.swift Pulse/App/AppShell.swift
git commit -m "feat: wire You → Workout history → Session Detail navigation + UI-test seed"
```

---

## Task 9: Empty, loading, and error state UI tests + palette swap (AC12/AC13/AC14/AC16)

Verify the non-happy-path states render without crashing and that a palette switch restyles both screens. These reuse alternate launch seeds.

**Files:**
- Modify: `Pulse/App/AppShell.swift` (extend the seed switch with `empty` / `error` seeds)
- Create: `PulseUITests/HistoryStatesUITests.swift`

- [ ] **Step 1: Extend the seed hook to support empty/error seeds**

In the app-root `sessionRepository` resolution, branch on the seed value:

```swift
private var sessionRepository: SessionRepository {
    let args = ProcessInfo.processInfo.arguments
    guard let idx = args.firstIndex(of: "-uiTestSeed"),
          idx + 1 < args.count else { return MockSessionRepository.seeded() }
    switch args[idx + 1] {
    case "empty": return MockSessionRepository(summaries: [], details: [:])
    case "error": return MockSessionRepository.failing()
    default:       return MockSessionRepository.seeded()
    }
}
```

- [ ] **Step 2: Write `PulseUITests/HistoryStatesUITests.swift`**

```swift
import XCTest

final class HistoryStatesUITests: XCTestCase {
    private func launch(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSeed", seed]
        app.launch()
        app.tabBars.buttons["You"].tap()
        app.buttons["you.nav.workoutHistory"].tap()
        return app
    }

    func testEmptyStateShowsMessageNotRows() {
        let app = launch(seed: "empty")
        XCTAssertTrue(app.staticTexts["history.empty"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["THIS WEEK"].exists)
    }

    func testErrorStateShowsMessageNoStaleRows() {
        let app = launch(seed: "error")
        XCTAssertTrue(app.staticTexts["history.error"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["history.row.Legs"].exists)
    }

    func testFilterEmptyShowsFilterMessage() {
        // A seed with only one-off sessions; "+ PR" yields none.
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSeed", "oneOffOnly"]
        app.launch()
        app.tabBars.buttons["You"].tap()
        app.buttons["you.nav.workoutHistory"].tap()
        app.buttons["history.chip.+ PR"].tap()
        XCTAssertTrue(app.staticTexts["history.empty"].waitForExistence(timeout: 3))
    }
}
```

> Add an `oneOffOnly` case to the seed switch returning `MockSessionRepository(summaries: [<one non-program, non-PR summary>], details: [:])`.

- [ ] **Step 3: Add a palette-swap assertion (AC16)**

Since both screens read every color from `Theme`, AC16 is structurally guaranteed; verify it with a token-binding test rather than a snapshot. Add to `PulseTests/WorkoutHistory/WorkoutHistoryModelTests.swift` companion or a small `PulseTests/DesignSystem/ThemeSwapTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Pulse

final class ThemeSwapTests: XCTestCase {
    func testPaletteSwapChangesAccentToken() {
        let theme = Theme()
        theme.palette = .coastal
        let coastalAccent = theme.accent
        theme.palette = .mint
        XCTAssertNotEqual(coastalAccent, theme.accent)
    }
}
```

This proves the tokens both screens consume change with the palette; because no view hardcodes a color, layout cannot shift (no size depends on palette).

- [ ] **Step 4: Run the full suite**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: `TEST SUCCEEDED` — all state and palette tests pass.

- [ ] **Step 5: Commit**

```bash
git add Pulse/App/AppShell.swift PulseUITests/HistoryStatesUITests.swift \
  PulseTests/DesignSystem/ThemeSwapTests.swift
git commit -m "test: history loading/empty/error states + palette-swap token test"
```

---

## Task 10: Verification, review, and PR

- [ ] **Step 1: Full clean build + test**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test
```
Expected: `TEST SUCCEEDED`, zero failures.

- [ ] **Step 2: Self-review against acceptance criteria.** Walk AC1–AC16 in the spec and confirm each is covered by a unit or UI test in this plan (see the AC → test map in Self-Review notes).

- [ ] **Step 3: Run the code reviewer + security review** (per CLAUDE.md workflow gates): `requesting-code-review` skill, then `/security-review`.

- [ ] **Step 4: Open the PR**

Run:
```bash
git push -u origin feature/BAK-17-history-session-detail
gh pr create --fill --base main
```
Use the PR template; link BAK-17; note the human review gate.

---

## Self-Review notes

**Acceptance-criteria → test map:**
- **AC1** (You → History nav): `HistoryUITests.navigateToHistory` reaching `history.h1`.
- **AC2** (eyebrow/H1/sub line): `HistoryUITests.testHistoryChromeAndDefaultFilter`.
- **AC3** (filter chips, All default): same test (`history.chip.All` / `+ PR` present); default `.all` proven by `WorkoutHistoryModelTests.testDefaultFilterIsAll`.
- **AC4** (filter narrows/restores): `WorkoutHistoryModelTests.testFilterPRShowsOnlyPRSessions` / `testFilterProgramAndOneOff` / `testSelectAllRestoresEverything` + UI `testPRFilterNarrowsThenAllRestores`.
- **AC5/AC6** (recency groups, row anatomy): `SessionGroupingTests` + `HistoryUITests.testGroupedRowsRender`.
- **AC7** (row → Detail): `SessionDetailUITests.launchToDetail` taps `history.row.Chest & Tris`.
- **AC8/AC9/AC10/AC11** (detail chrome/stats/log/footer): `SessionDetailUITests.testDetailChromeAndStats` / `testLogAndFooterButtons`; PR-box state from `SessionDetailModelTests.testZeroPRDetailRendersPlusZeroDash`.
- **AC12** (loading): `history.loading` / `session.loading` identifiers render in `.loading` phase.
- **AC13** (empty + filter-empty): `HistoryStatesUITests.testEmptyStateShowsMessageNotRows` / `testFilterEmptyShowsFilterMessage` + `WorkoutHistoryModelTests.testFilterWithNoMatchesIsEmpty...` / `testEmptyRepoSetsEmptyPhase`.
- **AC14** (error): `HistoryStatesUITests.testErrorStateShowsMessageNoStaleRows` + `WorkoutHistoryModelTests.testFailingRepoSetsErrorPhaseAndNoStaleData` / `SessionDetailModelTests.testUnknownIDSetsErrorPhase`.
- **AC15** (back): `SessionDetailUITests.testBackReturnsToHistory`.
- **AC16** (palette swap, no layout change): `ThemeSwapTests.testPaletteSwapChangesAccentToken` + the structural guarantee that no view hardcodes a color.

**Product-decision compliance:** PR via Epley (`EpleyPR`, Task 2), kg-only copy (`KG`/`kg` throughout the mock + StatBox sub; verified by `MockSessionRepositoryTests`), `Calendar.current` + Monday week start (`SessionGrouping`, Task 2), `isProgram` from active-program membership driving the `PPL`/`One-offs` filters, PR box `+0`/`—` plain when `prCount == 0`, footer actions as spied hooks only.

**Out of scope (per spec):** `⋯` overflow actions (inert glyph), edit/delete, real Duplicate/Repeat behavior (BAK-14), Supabase persistence (BAK-6 live), pagination, search, per-exercise drill-in, widgets/Live Activity.

**Dependencies:** Design System (BAK-7) components + tokens must exist (Prereq 0a); the repository protocol/mock/projections + Epley/grouping helpers are introduced here behind BAK-6's contract; footer-action behavior depends on BAK-14 and is stubbed.
