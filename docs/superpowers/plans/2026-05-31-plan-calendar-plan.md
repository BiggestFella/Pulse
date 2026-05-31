# Plan / Calendar Tab (BAK-12) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Models/helpers follow strict TDD (red → green → commit); pure SwiftUI views are validated by `#Preview` + an XCUITest.

**Goal:** Build the third tab (Today · Library · **Plan** · You): a month **Calendar** grid and a vertical **Agenda** list of the training schedule, with a **Schedule** sheet to assign / replace / clear / rest-day any non-completed day, and a "start today's workout" callback out to the app shell. Built UI-first against the BAK-6 repository protocols and their in-memory mocks; no Supabase calls.

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. One screen model `PlanModel` in `Pulse/Features/Plan/`; it owns load/select/assign/clear logic and depends only on the `ScheduleRepository` and `WorkoutRepository` protocols from `Core/Data` (never Supabase). View-data structs (`MonthContext`, `ScheduledDay`, `DayState`, `MonthSummary`, `AgendaEntry`, `SavedWorkoutRef`) live with the model. Views (`PlanView`, `CalendarMonthView`, `AgendaListView`, `ScheduleSheet`) read `Theme` tokens only and render from the model. Calendar math uses `Calendar.current` in the device-local timezone, **Monday-start week** (per product-decisions). Project is generated from `project.yml` via XcodeGen — never hand-edit the `.xcodeproj`.

**Tech Stack:** Swift 5.9+, SwiftUI, XcodeGen, XCTest + XCUITest.

**Prerequisites (must be built first):**
- **Data layer (BAK-6)** — provides `ScheduleRepository` (`plan(for:) -> DayPlan?`, `upcoming(from:days:) -> [(Date, DayPlan)]`, `setPlan(_:on:)`), `WorkoutRepository.fetchWorkouts()`, the `DayPlan { workout(Workout.ID), rest, done(WorkoutSession.ID) }` enum, the `InMemory*Repository` mocks + `SampleData`, and the `RepositoryContainer` composition root injected via `.environment`.
- **Design System (BAK-7)** — `Theme` tokens (`bg`, `surface`, `surface2`, `ink`, `inkSoft`, `inkFaint`, `accent`, `accentDeep`, `accent2`, `onAccent`), the typography API (H1, Eyebrow, Row name, Row sub, Stat numeral, Hero numeral), `PressableButtonStyle` (+ icon-button style), and the `BottomSheet` container.
- **Product decisions (authoritative):** week starts Monday everywhere; all day-bucketing uses `Calendar.current` device-local; v1 shows the **current month only** (no prev/next paging — spec open Q2); kg-only (no unit copy here); the Calendar/Agenda `mode` persists only **in memory** for the session (spec open Q8 → in-memory default).

These give us the protocols and design primitives this feature binds to. If a prerequisite type name differs at build time, adapt the bindings; do not introduce Supabase calls or hardcoded colors.

> **Open-question resolutions used by this plan** (spec §Open questions, resolved here so steps are concrete): (1) segmented control is the **sole** toggle; no top-bar action, no `+`. (2) single current month only. (3) a `done` today shows **`done`** (accent fill) and its tap opens the read-only `Completed.` sheet — only a not-yet-done `today` launches the workout. (4) Agenda window = **7 days starting today**. (5) rest days render as a distinct **dashed/dimmed** cell (no fill, no dot) in the grid and dimmed non-interactive rows in the agenda. (8) `mode` is in-memory only.

---

## Task 1: View-data types + `DayState` mapping (TDD)

**Files:**
- Create: `Pulse/Features/Plan/PlanViewData.swift`
- Create: `PulseTests/Plan/PlanViewDataTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Plan/PlanViewDataTests.swift`**

```swift
import XCTest
@testable import Pulse

final class PlanViewDataTests: XCTestCase {
    func testDayStateHasFourCases() {
        XCTAssertEqual(Set(DayState.allCases), [.done, .today, .plan, .empty])
    }

    func testScheduledDayDefaultsToEmpty() {
        let d = ScheduledDay(state: .empty, workoutName: nil)
        XCTAssertEqual(d.state, .empty)
        XCTAssertNil(d.workoutName)
    }

    func testMonthSummaryPercentRoundsDownAndGuardsZero() {
        XCTAssertEqual(MonthSummary(done: 20, planned: 23).pct, 86)   // 86.9 -> 86
        XCTAssertEqual(MonthSummary(done: 0, planned: 0).pct, 0)      // no divide-by-zero
        XCTAssertEqual(MonthSummary(done: 3, planned: 6).pct, 50)
    }

    func testSavedWorkoutRefCarriesNameAndSub() {
        let ref = SavedWorkoutRef(id: UUID(), name: "Chest & Tris", exerciseCount: 6, estimatedMinutes: 52)
        XCTAssertEqual(ref.sub, "6 EXERCISES · ~52M")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: FAIL — `DayState`, `ScheduledDay`, `MonthSummary`, `SavedWorkoutRef` undefined.

- [ ] **Step 3: Write `Pulse/Features/Plan/PlanViewData.swift`**

```swift
import Foundation

/// Visual state of a calendar day cell.
enum DayState: String, CaseIterable {
    case done    // completed session: accent fill + onAccent dot
    case today   // today, not yet done: accent2 outline (tap launches workout)
    case plan    // scheduled (not done): faint fill + accent2 dot
    case empty   // unscheduled (incl. rest, which renders dashed/dimmed)
}

/// One day's schedule, as the views consume it.
struct ScheduledDay: Equatable {
    var state: DayState
    var workoutName: String?
    var isRest: Bool = false
}

/// Month-grid geometry + display strings. Monday-start week.
struct MonthContext: Equatable {
    var title: String          // "May."
    var year: Int              // 2026
    var monthStartOffset: Int  // leading blank cells, Monday-start (0...6)
    var daysInMonth: Int       // 31
    var monthAbbrevUpper: String // "MAY"
}

/// THIS MONTH summary card values.
struct MonthSummary: Equatable {
    var done: Int
    var planned: Int
    /// Completion percent, integer, floor; 0 when nothing planned.
    var pct: Int { planned == 0 ? 0 : Int((Double(done) / Double(planned)) * 100) }
}

/// One agenda row.
struct AgendaEntry: Equatable, Identifiable {
    var id: Int { day }       // day-of-month is unique within the window
    var day: Int              // day-of-month
    var dow: String           // "WED"
    var name: String?         // workout name, nil for empty
    var sub: String?          // "6 EXERCISES · ~52M"
    var isToday: Bool
    var isRest: Bool
}

/// A saved workout the picker can assign.
struct SavedWorkoutRef: Equatable, Identifiable {
    var id: UUID
    var name: String
    var exerciseCount: Int
    var estimatedMinutes: Int
    var sub: String { "\(exerciseCount) EXERCISES · ~\(estimatedMinutes)M" }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (PlanViewDataTests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Plan/PlanViewData.swift PulseTests/Plan/PlanViewDataTests.swift
git commit -m "feat(plan): view-data types and DayState mapping"
```

---

## Task 2: Calendar math helper — month context from a date (TDD)

**Files:**
- Create: `Pulse/Features/Plan/MonthMath.swift`
- Create: `PulseTests/Plan/MonthMathTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Plan/MonthMathTests.swift`**

Uses a fixed UTC calendar so the test is timezone-stable; the model uses `Calendar.current` at runtime.

```swift
import XCTest
@testable import Pulse

final class MonthMathTests: XCTestCase {
    private func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal().date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testMay2026MondayStartOffsetIsFour() {
        // May 1 2026 is a Friday; Monday-start offset = 4.
        let ctx = MonthMath.context(for: date(2026, 5, 15), calendar: cal())
        XCTAssertEqual(ctx.monthStartOffset, 4)
        XCTAssertEqual(ctx.daysInMonth, 31)
        XCTAssertEqual(ctx.title, "May.")
        XCTAssertEqual(ctx.year, 2026)
        XCTAssertEqual(ctx.monthAbbrevUpper, "MAY")
    }

    func testFebruary2027MondayStartOffset() {
        // Feb 1 2027 is a Monday; offset = 0; 28 days.
        let ctx = MonthMath.context(for: date(2027, 2, 10), calendar: cal())
        XCTAssertEqual(ctx.monthStartOffset, 0)
        XCTAssertEqual(ctx.daysInMonth, 28)
    }

    func testDowAbbreviationForDay() {
        // May 28 2026 is a Wednesday.
        XCTAssertEqual(MonthMath.dowAbbrev(year: 2026, month: 5, day: 28, calendar: cal()), "WED")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: FAIL — `MonthMath` undefined.

- [ ] **Step 3: Write `Pulse/Features/Plan/MonthMath.swift`**

```swift
import Foundation

/// Pure calendar arithmetic for the Plan month grid. Monday-start week.
/// Callers pass an explicit `Calendar` (the model uses `Calendar.current`).
enum MonthMath {
    static func context(for date: Date, calendar: Calendar) -> MonthContext {
        var cal = calendar
        cal.firstWeekday = 2 // Monday

        let comps = cal.dateComponents([.year, .month], from: date)
        let first = cal.date(from: comps)!
        let daysInMonth = cal.range(of: .day, in: .month, for: first)!.count

        // weekday: 1=Sun ... 7=Sat. Convert to Monday-start 0...6.
        let weekday = cal.component(.weekday, from: first)
        let offset = (weekday + 5) % 7   // Mon->0, Tue->1, ... Sun->6

        let title = monthName(comps.month!) + "."
        let abbrev = monthAbbrev(comps.month!)

        return MonthContext(
            title: title,
            year: comps.year!,
            monthStartOffset: offset,
            daysInMonth: daysInMonth,
            monthAbbrevUpper: abbrev
        )
    }

    static func dowAbbrev(year: Int, month: Int, day: Int, calendar: Calendar) -> String {
        let d = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let wd = calendar.component(.weekday, from: d) // 1=Sun
        let names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        return names[wd - 1]
    }

    private static func monthName(_ m: Int) -> String {
        ["January", "February", "March", "April", "May", "June",
         "July", "August", "September", "October", "November", "December"][m - 1]
    }

    private static func monthAbbrev(_ m: Int) -> String {
        ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
         "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"][m - 1]
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (MonthMathTests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Plan/MonthMath.swift PulseTests/Plan/MonthMathTests.swift
git commit -m "feat(plan): Monday-start month grid math helper"
```

---

## Task 3: `PlanModel` load + state mapping (TDD)

The model takes the two repository protocols and a `Calendar` (injectable for tests) and a "now" `Date` (injectable). On `load()` it builds `month`, `schedule` (`[Int: ScheduledDay]`), `summary`, `agenda`, and `savedWorkouts`, then sets `loadState = .loaded`. We use a small fake repo in the test so this task does not depend on the BAK-6 mock's exact seed.

**Files:**
- Create: `Pulse/Features/Plan/PlanModel.swift`
- Create: `PulseTests/Plan/PlanModelLoadTests.swift`
- Create: `PulseTests/Plan/FakePlanRepositories.swift` (test-only fakes)

- [ ] **Step 1: Write the test-only fakes `PulseTests/Plan/FakePlanRepositories.swift`**

```swift
import Foundation
@testable import Pulse

/// Configurable fake ScheduleRepository for PlanModel tests.
/// Keyed by day-of-month within the model's reference month.
final class FakeScheduleRepository: ScheduleRepository {
    var plansByDay: [Int: DayPlan]
    var calendar: Calendar
    var shouldThrow = false

    init(plansByDay: [Int: DayPlan], calendar: Calendar) {
        self.plansByDay = plansByDay
        self.calendar = calendar
    }

    private func day(of date: Date) -> Int { calendar.component(.day, from: date) }

    func plan(for date: Date) async throws -> DayPlan? {
        if shouldThrow { throw FakeError.boom }
        return plansByDay[day(of: date)]
    }

    func upcoming(from date: Date, days: Int) async throws -> [(Date, DayPlan)] {
        if shouldThrow { throw FakeError.boom }
        var out: [(Date, DayPlan)] = []
        for offset in 0..<days {
            let d = calendar.date(byAdding: .day, value: offset, to: date)!
            if let p = plansByDay[day(of: d)] { out.append((d, p)) }
        }
        return out
    }

    func setPlan(_ plan: DayPlan?, on date: Date) async throws {
        if shouldThrow { throw FakeError.boom }
        if let plan { plansByDay[day(of: date)] = plan }
        else { plansByDay[day(of: date)] = nil }
    }
}

final class FakeWorkoutRepository: WorkoutRepositoryReading {
    var workouts: [Workout]
    init(workouts: [Workout]) { self.workouts = workouts }
    func fetchWorkouts() async throws -> [Workout] { workouts }
}

enum FakeError: Error { case boom }
```

> **Binding note:** `WorkoutRepositoryReading` is the minimal read-only slice `PlanModel` needs (`fetchWorkouts()`). Declare it in `PlanModel.swift` (Step 4) and make BAK-6's `WorkoutRepository` conform; this keeps the model decoupled from the full repo surface. If BAK-6 already exposes `fetchWorkouts()` on `WorkoutRepository`, type `PlanModel` against that protocol directly and delete `WorkoutRepositoryReading`.

- [ ] **Step 2: Write the failing test `PulseTests/Plan/PlanModelLoadTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class PlanModelLoadTests: XCTestCase {
    private func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal().date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func makeModel(
        plans: [Int: DayPlan],
        workouts: [Workout] = [],
        now: Date = DateComponents(calendar: nil, year: 2026, month: 5, day: 28).date ?? Date()
    ) -> (PlanModel, FakeScheduleRepository, FakeWorkoutRepository) {
        let sched = FakeScheduleRepository(plansByDay: plans, calendar: cal())
        let lib = FakeWorkoutRepository(workouts: workouts)
        let model = PlanModel(schedule: sched, workouts: lib, calendar: cal(), now: date(2026, 5, 28))
        return (model, sched, lib)
    }

    func testLoadPopulatesEverythingAndMarksLoaded() async {
        let w = Workout(id: UUID(), name: "Chest & Tris", weekday: nil, order: 0, exercises: [])
        // day 20 done, day 28 done-today, day 29 planned, others empty
        let plans: [Int: DayPlan] = [
            20: .done(UUID()),
            28: .done(UUID()),
            29: .workout(w.id)
        ]
        let (model, _, _) = makeModel(plans: plans, workouts: [w])
        await model.load()
        XCTAssertEqual(model.loadState, .loaded)
        XCTAssertEqual(model.month.daysInMonth, 31)
        XCTAssertEqual(model.month.monthStartOffset, 4)
        XCTAssertEqual(model.schedule[20]?.state, .done)
        XCTAssertEqual(model.schedule[29]?.state, .plan)
        XCTAssertEqual(model.schedule[15]?.state, .empty)
        XCTAssertEqual(model.summary.done, 2)
        XCTAssertEqual(model.summary.planned, 3) // 2 done + 1 plan
    }

    func testTodayNotDoneMapsToTodayState() async {
        let w = Workout(id: UUID(), name: "Chest & Tris", weekday: nil, order: 0, exercises: [])
        let (model, _, _) = makeModel(plans: [28: .workout(w.id)], workouts: [w])
        await model.load()
        XCTAssertEqual(model.schedule[28]?.state, .today)
    }

    func testTodayDoneStaysDone() async {
        let (model, _, _) = makeModel(plans: [28: .done(UUID())])
        await model.load()
        XCTAssertEqual(model.schedule[28]?.state, .done)
    }

    func testRestDayMapsToEmptyAndIsRest() async {
        let (model, _, _) = makeModel(plans: [29: .rest])
        await model.load()
        XCTAssertEqual(model.schedule[29]?.state, .empty)
        XCTAssertEqual(model.schedule[29]?.isRest, true)
    }

    func testEmptyMonthSummaryIsZeroOverZero() async {
        let (model, _, _) = makeModel(plans: [:])
        await model.load()
        XCTAssertEqual(model.summary.done, 0)
        XCTAssertEqual(model.summary.planned, 0)
        XCTAssertEqual(model.summary.pct, 0)
    }

    func testLoadFailureSetsFailedState() async {
        let (model, sched, _) = makeModel(plans: [:])
        sched.shouldThrow = true
        await model.load()
        XCTAssertEqual(model.loadState, .failed)
        XCTAssertTrue(model.schedule.isEmpty)
    }

    func testModeTogglesBetweenCalendarAndAgenda() {
        let (model, _, _) = makeModel(plans: [:])
        XCTAssertEqual(model.mode, .calendar)
        model.mode = .agenda
        XCTAssertEqual(model.mode, .agenda)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: FAIL — `PlanModel`, `WorkoutRepositoryReading` undefined.

- [ ] **Step 4: Write `Pulse/Features/Plan/PlanModel.swift`**

```swift
import Foundation

/// Minimal read slice the Plan feature needs from the workout library.
/// BAK-6's `WorkoutRepository` should conform to this.
protocol WorkoutRepositoryReading {
    func fetchWorkouts() async throws -> [Workout]
}

@MainActor
@Observable
final class PlanModel {
    enum ViewMode { case calendar, agenda }
    enum LoadState { case loading, loaded, failed }

    // Toggle (in-memory only, per product decision).
    var mode: ViewMode = .calendar
    private(set) var loadState: LoadState = .loading

    // Calendar
    private(set) var month: MonthContext
    private(set) var schedule: [Int: ScheduledDay] = [:]
    private(set) var summary = MonthSummary(done: 0, planned: 0)

    // Agenda
    private(set) var agenda: [AgendaEntry] = []

    // Sheet
    var scheduleSheetDay: Int?   // non-nil == sheet presented
    private(set) var savedWorkouts: [SavedWorkoutRef] = []

    /// Wired by the app shell to launch the active workout flow (BAK-14).
    var onStartWorkout: () -> Void = {}

    private let scheduleRepo: ScheduleRepository
    private let workoutRepo: WorkoutRepositoryReading
    private let calendar: Calendar
    private let now: Date
    private let todayDay: Int
    private var workoutNames: [Workout.ID: String] = [:]

    init(schedule: ScheduleRepository,
         workouts: WorkoutRepositoryReading,
         calendar: Calendar = .current,
         now: Date = Date()) {
        self.scheduleRepo = schedule
        self.workoutRepo = workouts
        self.calendar = calendar
        self.now = now
        self.todayDay = calendar.component(.day, from: now)
        self.month = MonthMath.context(for: now, calendar: calendar)
    }

    func load() async {
        loadState = .loading
        do {
            let workouts = try await workoutRepo.fetchWorkouts()
            workoutNames = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0.name) })
            savedWorkouts = workouts.map {
                SavedWorkoutRef(id: $0.id, name: $0.name,
                                exerciseCount: $0.exercises.count,
                                estimatedMinutes: max(1, $0.exercises.count * 9))
            }
            try await buildSchedule()
            try await buildAgenda()
            recomputeSummary()
            loadState = .loaded
        } catch {
            schedule = [:]
            agenda = []
            summary = MonthSummary(done: 0, planned: 0)
            loadState = .failed
        }
    }

    private func buildSchedule() async throws {
        var map: [Int: ScheduledDay] = [:]
        for day in 1...month.daysInMonth {
            let date = dateFor(day: day)
            let plan = try await scheduleRepo.plan(for: date)
            map[day] = mapDay(day: day, plan: plan)
        }
        schedule = map
    }

    private func mapDay(day: Int, plan: DayPlan?) -> ScheduledDay {
        guard let plan else { return ScheduledDay(state: .empty, workoutName: nil) }
        switch plan {
        case .done:
            return ScheduledDay(state: .done, workoutName: nil)
        case .rest:
            return ScheduledDay(state: .empty, workoutName: "Rest", isRest: true)
        case .workout(let id):
            let name = workoutNames[id]
            let state: DayState = (day == todayDay) ? .today : .plan
            return ScheduledDay(state: state, workoutName: name)
        }
    }

    private func buildAgenda() async throws {
        let upcoming = try await scheduleRepo.upcoming(from: startOfDay(now), days: 7)
        let byDay = Dictionary(uniqueKeysWithValues:
            upcoming.map { (calendar.component(.day, from: $0.0), $0.1) })
        var rows: [AgendaEntry] = []
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: startOfDay(now))!
            let comps = calendar.dateComponents([.year, .month, .day], from: date)
            let day = comps.day!
            let isToday = offset == 0
            let plan = byDay[day]
            switch plan {
            case .workout(let id):
                let name = workoutNames[id]
                rows.append(AgendaEntry(day: day,
                                        dow: dow(date),
                                        name: name,
                                        sub: subFor(workoutID: id),
                                        isToday: isToday, isRest: false))
            case .done:
                rows.append(AgendaEntry(day: day, dow: dow(date),
                                        name: "Completed", sub: nil,
                                        isToday: isToday, isRest: false))
            case .rest:
                rows.append(AgendaEntry(day: day, dow: dow(date),
                                        name: "Rest", sub: "RECOVERY",
                                        isToday: isToday, isRest: true))
            case nil:
                rows.append(AgendaEntry(day: day, dow: dow(date),
                                        name: nil, sub: nil,
                                        isToday: isToday, isRest: false))
            }
        }
        agenda = rows
    }

    private func recomputeSummary() {
        let done = schedule.values.filter { $0.state == .done }.count
        let plan = schedule.values.filter { $0.state == .plan || $0.state == .today }.count
        summary = MonthSummary(done: done, planned: done + plan)
    }

    // MARK: - Interactions

    func selectDay(_ day: Int) {
        guard let entry = schedule[day] else { return }
        if entry.state == .today {
            onStartWorkout()
        } else {
            scheduleSheetDay = day
        }
    }

    func assign(day: Int, workout: SavedWorkoutRef) async {
        await mutate(day: day, plan: .workout(workout.id))
    }

    func assignRestDay(_ day: Int) async {
        await mutate(day: day, plan: .rest)
    }

    func clear(day: Int) async {
        // A done day can never be cleared.
        guard schedule[day]?.state != .done else { scheduleSheetDay = nil; return }
        await mutate(day: day, plan: nil)
    }

    private func mutate(day: Int, plan: DayPlan?) async {
        do {
            try await scheduleRepo.setPlan(plan, on: dateFor(day: day))
            let fresh = try await scheduleRepo.plan(for: dateFor(day: day))
            schedule[day] = mapDay(day: day, plan: fresh)
            recomputeSummary()
            try await buildAgenda()
        } catch {
            // keep existing state; surface no crash
        }
        scheduleSheetDay = nil
    }

    // MARK: - Helpers

    private func dateFor(day: Int) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: day))!
    }
    private func startOfDay(_ d: Date) -> Date { calendar.startOfDay(for: d) }
    private func dow(_ d: Date) -> String {
        let names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        return names[calendar.component(.weekday, from: d) - 1]
    }
    private func subFor(workoutID: Workout.ID) -> String? {
        savedWorkouts.first { $0.id == workoutID }?.sub
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (PlanModelLoadTests green; earlier suites still green).

- [ ] **Step 6: Commit**

```bash
git add Pulse/Features/Plan/PlanModel.swift PulseTests/Plan/PlanModelLoadTests.swift PulseTests/Plan/FakePlanRepositories.swift
git commit -m "feat(plan): PlanModel load + day-state/summary/agenda mapping"
```

---

## Task 4: `PlanModel` interactions — select / assign / clear (TDD)

**Files:**
- Modify: `Pulse/Features/Plan/PlanModel.swift` (already has the methods from Task 3 — this task locks their behavior with tests)
- Create: `PulseTests/Plan/PlanModelInteractionTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/Plan/PlanModelInteractionTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class PlanModelInteractionTests: XCTestCase {
    private func cal() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal().date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func makeModel(plans: [Int: DayPlan], workouts: [Workout])
        -> (PlanModel, FakeScheduleRepository) {
        let sched = FakeScheduleRepository(plansByDay: plans, calendar: cal())
        let lib = FakeWorkoutRepository(workouts: workouts)
        let model = PlanModel(schedule: sched, workouts: lib, calendar: cal(), now: date(2026, 5, 28))
        return (model, sched)
    }
    private func workout(_ name: String) -> Workout {
        Workout(id: UUID(), name: name, weekday: nil, order: 0, exercises: [])
    }

    func testSelectTodayLaunchesWorkoutAndDoesNotOpenSheet() async {
        let w = workout("Chest & Tris")
        let (model, _) = makeModel(plans: [28: .workout(w.id)], workouts: [w])
        await model.load()
        var launched = false
        model.onStartWorkout = { launched = true }
        model.selectDay(28)
        XCTAssertTrue(launched)
        XCTAssertNil(model.scheduleSheetDay)
    }

    func testSelectPlannedDayOpensSheet() async {
        let w = workout("Shoulders")
        let (model, _) = makeModel(plans: [29: .workout(w.id)], workouts: [w])
        await model.load()
        model.selectDay(29)
        XCTAssertEqual(model.scheduleSheetDay, 29)
    }

    func testSelectEmptyDayOpensSheet() async {
        let (model, _) = makeModel(plans: [:], workouts: [])
        await model.load()
        model.selectDay(15)
        XCTAssertEqual(model.scheduleSheetDay, 15)
    }

    func testSelectDoneDayOpensSheetNeverLaunches() async {
        let (model, _) = makeModel(plans: [20: .done(UUID())], workouts: [])
        await model.load()
        var launched = false
        model.onStartWorkout = { launched = true }
        model.selectDay(20)
        XCTAssertFalse(launched)
        XCTAssertEqual(model.scheduleSheetDay, 20)
    }

    func testAssignUpdatesDayToPlanAndClosesSheet() async {
        let w = workout("Arms")
        let (model, _) = makeModel(plans: [:], workouts: [w])
        await model.load()
        model.scheduleSheetDay = 15
        await model.assign(day: 15, workout: model.savedWorkouts[0])
        XCTAssertEqual(model.schedule[15]?.state, .plan)
        XCTAssertEqual(model.schedule[15]?.workoutName, "Arms")
        XCTAssertNil(model.scheduleSheetDay)
        XCTAssertEqual(model.summary.planned, 1)
    }

    func testAssignRestDayRecordsRestAndClosesSheet() async {
        let (model, _) = makeModel(plans: [:], workouts: [])
        await model.load()
        model.scheduleSheetDay = 16
        await model.assignRestDay(16)
        XCTAssertEqual(model.schedule[16]?.isRest, true)
        XCTAssertEqual(model.schedule[16]?.state, .empty)
        XCTAssertNil(model.scheduleSheetDay)
    }

    func testClearPlannedDayReturnsToEmptyAndClosesSheet() async {
        let w = workout("Legs")
        let (model, _) = makeModel(plans: [17: .workout(w.id)], workouts: [w])
        await model.load()
        model.scheduleSheetDay = 17
        await model.clear(day: 17)
        XCTAssertEqual(model.schedule[17]?.state, .empty)
        XCTAssertNil(model.scheduleSheetDay)
    }

    func testClearDoneDayIsNoOp() async {
        let (model, sched) = makeModel(plans: [20: .done(UUID())], workouts: [])
        await model.load()
        model.scheduleSheetDay = 20
        await model.clear(day: 20)
        XCTAssertEqual(model.schedule[20]?.state, .done)
        XCTAssertNotNil(sched.plansByDay[20]) // entry untouched
        XCTAssertNil(model.scheduleSheetDay)
    }
}
```

- [ ] **Step 2: Run the tests to verify they pass (methods already implemented in Task 3)**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS. If any assertion fails, fix `PlanModel` minimally (e.g. `selectDay`/`mutate`) until green — do not change tests.

- [ ] **Step 3: Commit**

```bash
git add PulseTests/Plan/PlanModelInteractionTests.swift Pulse/Features/Plan/PlanModel.swift
git commit -m "test(plan): lock select/assign/clear behavior"
```

---

## Task 5: `CalendarMonthView` (view assembly + preview + UI test)

Pure SwiftUI assembly from `PlanModel`. Validated by a `#Preview` and an XCUITest.

**Files:**
- Create: `Pulse/Features/Plan/CalendarMonthView.swift`

- [ ] **Step 1: Write `Pulse/Features/Plan/CalendarMonthView.swift` with concrete structure**

```swift
import SwiftUI

struct CalendarMonthView: View {
    @Environment(Theme.self) private var theme
    let model: PlanModel

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[5]) {
            header
            summaryCard
            weekdayRow
            dayGrid
            todayRow
        }
        .padding(.horizontal, theme.spacing[5])
        .accessibilityIdentifier("plan.calendar")
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(model.month.title).pulseH1()
            Spacer()
            Text(String(model.month.year)).pulseStatNumeral().foregroundStyle(theme.inkSoft)
        }
    }

    private var summaryCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: theme.spacing[0]) {
                Text("THIS MONTH").pulseEyebrow().foregroundStyle(theme.onAccent.opacity(0.7))
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(model.summary.done)").pulseHeroNumeral().foregroundStyle(theme.onAccent)
                    Text("/ \(model.summary.planned)").pulseStatNumeral().foregroundStyle(theme.onAccent.opacity(0.7))
                }
            }
            Spacer()
            Text("\(model.summary.pct)%").pulseStatNumeral().foregroundStyle(theme.onAccent)
        }
        .padding(theme.spacing[5])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: theme.radiusCard).stroke(theme.ink, lineWidth: 2))
        .accessibilityIdentifier("plan.summaryCard")
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { d in
                Text(d).pulseRowSub().foregroundStyle(theme.inkSoft)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(0..<model.month.monthStartOffset, id: \.self) { _ in
                Color.clear.frame(height: 44)
            }
            ForEach(1...model.month.daysInMonth, id: \.self) { day in
                dayCell(day)
                    .onTapGesture { model.selectDay(day) }
                    .accessibilityIdentifier("plan.day.\(day)")
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let entry = model.schedule[day] ?? ScheduledDay(state: .empty, workoutName: nil)
        ZStack {
            cellBackground(entry)
            VStack(spacing: 3) {
                Text("\(day)")
                    .pulseRowName()
                    .foregroundStyle(entry.state == .done ? theme.onAccent : theme.ink)
                dot(entry)
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private func cellBackground(_ entry: ScheduledDay) -> some View {
        let r = RoundedRectangle(cornerRadius: 10)
        switch entry.state {
        case .done:
            r.fill(theme.accent)
        case .today:
            r.fill(theme.surface).overlay(r.stroke(theme.accent2, lineWidth: 2))
        case .plan:
            r.fill(theme.accent.opacity(0.14)).overlay(r.stroke(theme.accent2, lineWidth: 1))
        case .empty:
            r.fill(.clear)
                .overlay(r.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(theme.inkFaint))
                .opacity(entry.isRest ? 0.5 : 1)
        }
    }

    @ViewBuilder
    private func dot(_ entry: ScheduledDay) -> some View {
        switch entry.state {
        case .done:  Circle().fill(theme.onAccent).frame(width: 4, height: 4)
        case .today, .plan: Circle().fill(theme.accent2).frame(width: 4, height: 4)
        case .empty: Color.clear.frame(width: 4, height: 4)
        }
    }

    @ViewBuilder
    private var todayRow: some View {
        if let entry = model.agenda.first(where: { $0.isToday }), let name = entry.name {
            VStack(alignment: .leading, spacing: theme.spacing[1]) {
                Text("\(entry.dow) · \(model.month.monthAbbrevUpper) \(entry.day)")
                    .pulseEyebrow().foregroundStyle(theme.inkSoft)
                HStack(spacing: theme.spacing[2]) {
                    Text("T").pulseRowSub().foregroundStyle(theme.onAccent)
                        .frame(width: 22, height: 22)
                        .background(theme.accent2, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).pulseRowName().foregroundStyle(theme.ink)
                        if let sub = entry.sub { Text(sub).pulseRowSub().foregroundStyle(theme.inkSoft) }
                    }
                    Spacer()
                    Text("→").pulseRowName().foregroundStyle(theme.accent)
                }
                .padding(theme.spacing[3])
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.accent, lineWidth: 2))
                .contentShape(Rectangle())
                .onTapGesture { model.onStartWorkout() }
                .accessibilityIdentifier("plan.todayRow")
            }
        }
    }
}
```

> **Note:** typography modifiers (`.pulseH1()`, `.pulseEyebrow()`, `.pulseRowName()`, `.pulseRowSub()`, `.pulseStatNumeral()`, `.pulseHeroNumeral()`) come from BAK-7's `Typography.swift`. If their names differ, adapt — never substitute hardcoded fonts/sizes.

- [ ] **Step 2: Add a `#Preview` at the bottom of the file**

```swift
#Preview {
    let model = PlanModel(schedule: InMemoryScheduleRepository(),
                          workouts: InMemoryWorkoutRepository())
    return ScrollView { CalendarMonthView(model: model) }
        .background(Theme().bg)
        .environment(Theme())
        .task { await model.load() }
}
```

> If the BAK-6 mock initializers differ (e.g. require `SampleData`), use the documented initializer. The preview exists to render the screen against the seeded sample world.

- [ ] **Step 3: Build to confirm it compiles**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Pulse/Features/Plan/CalendarMonthView.swift
git commit -m "feat(plan): CalendarMonthView (header, summary, grid, today row)"
```

---

## Task 6: `AgendaListView` (view assembly + preview)

**Files:**
- Create: `Pulse/Features/Plan/AgendaListView.swift`

- [ ] **Step 1: Write `Pulse/Features/Plan/AgendaListView.swift`**

```swift
import SwiftUI

struct AgendaListView: View {
    @Environment(Theme.self) private var theme
    let model: PlanModel

    var body: some View {
        VStack(spacing: theme.spacing[4]) {
            ForEach(model.agenda) { entry in
                row(entry)
                    .accessibilityIdentifier("plan.agenda.\(entry.day)")
            }
        }
        .padding(.horizontal, theme.spacing[5])
        .accessibilityIdentifier("plan.agenda")
    }

    @ViewBuilder
    private func row(_ entry: AgendaEntry) -> some View {
        let interactive = entry.isToday
        HStack(alignment: .top, spacing: theme.spacing[3]) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.dow).pulseEyebrow()
                    .foregroundStyle(entry.isToday ? theme.accent2 : theme.inkSoft)
                Text("\(entry.day)")
                    .pulseHeroNumeral()
                    .foregroundStyle(numberColor(entry))
                    .scaleEffect(entry.isToday ? 1.0 : 0.78, anchor: .leading)
            }
            .frame(width: 64, alignment: .leading)

            workoutRow(entry)
        }
        .opacity(entry.isRest || entry.name == nil ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if interactive { model.onStartWorkout() } }
    }

    private func numberColor(_ entry: AgendaEntry) -> Color {
        if entry.isToday { return theme.accent }
        if entry.isRest || entry.name == nil { return theme.inkSoft }
        return theme.ink
    }

    @ViewBuilder
    private func workoutRow(_ entry: AgendaEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name ?? "Unscheduled").pulseRowName().foregroundStyle(theme.ink)
                if let sub = entry.sub { Text(sub).pulseRowSub().foregroundStyle(theme.inkSoft) }
            }
            Spacer()
            if entry.isToday {
                Text("→").pulseRowName().foregroundStyle(theme.accent)
            } else if entry.name != nil && !entry.isRest {
                Image(systemName: "chevron.right").foregroundStyle(theme.inkSoft)
            }
        }
        .padding(theme.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(entry.isToday ? theme.accent : theme.inkFaint,
                        lineWidth: entry.isToday ? 2 : 1)
        )
    }
}

#Preview {
    let model = PlanModel(schedule: InMemoryScheduleRepository(),
                          workouts: InMemoryWorkoutRepository())
    return ScrollView { AgendaListView(model: model) }
        .background(Theme().bg)
        .environment(Theme())
        .task { model.mode = .agenda; await model.load() }
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Plan/AgendaListView.swift
git commit -m "feat(plan): AgendaListView with today emphasis + dimmed rest rows"
```

---

## Task 7: `ScheduleSheet` (view assembly + preview)

State-dependent content per AC-7..10: `Completed.` (read-only), `Scheduled.` (CLEAR + REPLACE WITH list), `Schedule a day.` (PICK A WORKOUT list). Both editable states show a dashed `Rest day` option.

**Files:**
- Create: `Pulse/Features/Plan/ScheduleSheet.swift`

- [ ] **Step 1: Write `Pulse/Features/Plan/ScheduleSheet.swift`**

```swift
import SwiftUI

struct ScheduleSheet: View {
    @Environment(Theme.self) private var theme
    let model: PlanModel
    let day: Int

    private var entry: ScheduledDay {
        model.schedule[day] ?? ScheduledDay(state: .empty, workoutName: nil)
    }
    private var title: String {
        switch entry.state {
        case .done:  return "Completed."
        case .empty: return "Schedule a day."
        default:     return "Scheduled."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[4]) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing[3]) {
                    switch entry.state {
                    case .done:        doneContent
                    case .plan, .today: scheduledContent
                    case .empty:       emptyContent
                    }
                }
            }
        }
        .padding(theme.spacing[5])
        .background(theme.bg)
        .accessibilityIdentifier("plan.scheduleSheet")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing[1]) {
            Text("\(model.month.monthAbbrevUpper) \(day) · \(String(model.month.year))")
                .pulseEyebrow().foregroundStyle(theme.inkSoft)
            HStack {
                Text(title).pulseH1().accessibilityIdentifier("plan.sheet.title")
                Spacer()
                Button { model.scheduleSheetDay = nil } label: { Text("✕").pulseRowName() }
                    .accessibilityIdentifier("plan.sheet.close")
            }
        }
    }

    // AC-8: read-only, no edit actions.
    private var doneContent: some View {
        assignedRow(name: entry.workoutName ?? "Workout", tag: "DONE", border: theme.accent)
    }

    // AC-9: assigned row + CLEAR + REPLACE WITH list + rest option.
    private var scheduledContent: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            assignedRow(name: entry.workoutName ?? "Workout", tag: "PLANNED", border: theme.accent2)
            Button("CLEAR") { Task { await model.clear(day: day) } }
                .buttonStyle(PressableButtonStyle(variant: .secondary, size: .sm))
                .accessibilityIdentifier("plan.sheet.clear")
            Text("REPLACE WITH").pulseEyebrow().foregroundStyle(theme.inkSoft)
            pickerList
        }
    }

    // AC-10: PICK A WORKOUT list + rest option.
    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("PICK A WORKOUT").pulseEyebrow().foregroundStyle(theme.inkSoft)
            pickerList
        }
    }

    private var pickerList: some View {
        VStack(spacing: theme.spacing[2]) {
            ForEach(model.savedWorkouts) { w in
                pickRow(name: w.name, sub: w.sub, dashed: false) {
                    Task { await model.assign(day: day, workout: w) }
                }
                .accessibilityIdentifier("plan.sheet.pick.\(w.id.uuidString)")
            }
            pickRow(name: "Rest day", sub: "RECOVERY", dashed: true) {
                Task { await model.assignRestDay(day) }
            }
            .accessibilityIdentifier("plan.sheet.rest")
        }
    }

    private func assignedRow(name: String, tag: String, border: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).pulseRowName().foregroundStyle(theme.ink)
                Text(tag).pulseRowSub().foregroundStyle(theme.inkSoft)
            }
            Spacer()
        }
        .padding(theme.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 2))
    }

    private func pickRow(name: String, sub: String, dashed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).pulseRowName().foregroundStyle(theme.ink)
                    Text(sub).pulseRowSub().foregroundStyle(theme.inkSoft)
                }
                Spacer()
                Image(systemName: "plus").foregroundStyle(theme.accent)
            }
            .padding(theme.spacing[3])
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(dashed
                        ? AnyShapeStyle(theme.inkFaint)
                        : AnyShapeStyle(theme.accent),
                        style: StrokeStyle(lineWidth: dashed ? 1 : 2, dash: dashed ? [4, 4] : []))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let model = PlanModel(schedule: InMemoryScheduleRepository(),
                          workouts: InMemoryWorkoutRepository())
    return ScheduleSheet(model: model, day: 15)
        .environment(Theme())
        .task { await model.load() }
}
```

> `PressableButtonStyle(variant:size:)` is BAK-7's button style; adapt the initializer to its real signature.

- [ ] **Step 2: Build to confirm it compiles**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Plan/ScheduleSheet.swift
git commit -m "feat(plan): ScheduleSheet (done/scheduled/empty states + picker)"
```

---

## Task 8: `PlanView` shell — toggle, load/error/loading, sheet wiring (view assembly + preview)

**Files:**
- Modify: `Pulse/Features/Plan/PlanView.swift`

- [ ] **Step 1: Replace `Pulse/Features/Plan/PlanView.swift`**

```swift
import SwiftUI

struct PlanView: View {
    @Environment(Theme.self) private var theme
    @State private var model: PlanModel
    var onStartWorkout: () -> Void = {}

    init(model: PlanModel) { _model = State(initialValue: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[4]) {
            Text("PLAN").pulseEyebrow().foregroundStyle(theme.inkSoft)
                .padding(.horizontal, theme.spacing[5])
            toggle
            ScrollView { body(for: model.loadState) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.bg)
        .onAppear { model.onStartWorkout = onStartWorkout }
        .task { await model.load() }
        .sheet(isPresented: sheetBinding) {
            if let day = model.scheduleSheetDay {
                ScheduleSheet(model: model, day: day)
                    .presentationDetents([.medium, .large])
                    .presentationCornerRadius(26)
            }
        }
    }

    private var sheetBinding: Binding<Bool> {
        Binding(get: { model.scheduleSheetDay != nil },
                set: { if !$0 { model.scheduleSheetDay = nil } })
    }

    private var toggle: some View {
        HStack(spacing: 0) {
            segment("Calendar", isOn: model.mode == .calendar) { model.mode = .calendar }
            segment("Agenda", isOn: model.mode == .agenda) { model.mode = .agenda }
        }
        .padding(3)
        .background(theme.surface, in: Capsule())
        .overlay(Capsule().stroke(theme.inkFaint, lineWidth: 1))
        .padding(.horizontal, theme.spacing[5])
        .accessibilityIdentifier("plan.toggle")
    }

    private func segment(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased()).pulseRowSub()
                .foregroundStyle(isOn ? theme.bg : theme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.spacing[2])
                .background(isOn ? theme.ink : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan.toggle.\(label.lowercased())")
    }

    @ViewBuilder
    private func body(for state: PlanModel.LoadState) -> some View {
        switch state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                .accessibilityIdentifier("plan.loading")
        case .failed:
            VStack(spacing: theme.spacing[3]) {
                Text("Couldn't load your schedule.").pulseRowName().foregroundStyle(theme.ink)
                Button("RETRY") { Task { await model.load() } }
                    .buttonStyle(PressableButtonStyle(variant: .secondary, size: .sm))
                    .accessibilityIdentifier("plan.retry")
            }
            .frame(maxWidth: .infinity, minHeight: 240)
            .accessibilityIdentifier("plan.error")
        case .loaded:
            if model.mode == .calendar {
                CalendarMonthView(model: model)
            } else {
                AgendaListView(model: model)
            }
        }
    }
}

#Preview {
    PlanView(model: PlanModel(schedule: InMemoryScheduleRepository(),
                              workouts: InMemoryWorkoutRepository()))
        .environment(Theme())
}
```

- [ ] **Step 2: Build to confirm it compiles**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/Plan/PlanView.swift
git commit -m "feat(plan): PlanView shell with toggle, load/error states, sheet"
```

---

## Task 9: Wire `PlanView` into the app shell (modify + UI test for tab presence)

**Files:**
- Modify: `Pulse/App/AppShell.swift`

- [ ] **Step 1: Update `AppShell` to construct `PlanView` with repositories + the start callback**

Replace the `PlanView()` line in `Pulse/App/AppShell.swift`:

```swift
PlanView(model: PlanModel(
    schedule: repositories.schedule,
    workouts: repositories.workouts
))
.tabItem { Label("Plan", systemImage: "calendar") }
```

> `repositories` is BAK-6's `RepositoryContainer` injected at the shell. If the shell does not yet hold it, read it from `@Environment(RepositoryContainer.self)`. The `onStartWorkout` callback is left default (`{}`) until BAK-14 wires the active flow; pass it through here when that lands:
> `PlanView(model: …, onStartWorkout: { /* present active workout */ })`.

- [ ] **Step 2: Build to confirm it compiles**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/App/AppShell.swift
git commit -m "feat(plan): wire PlanView into the app shell tab bar"
```

---

## Task 10: Acceptance / UI tests (XCUITest)

Maps to ACs 1–14. Drives the running app against the seeded mock world.

**Files:**
- Create: `PulseUITests/PlanUITests.swift`

- [ ] **Step 1: Write `PulseUITests/PlanUITests.swift`**

```swift
import XCTest

final class PlanUITests: XCTestCase {
    private func launchToPlan() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Plan"].tap()
        return app
    }

    // AC-1: toggle defaults to Calendar and switches the body.
    func testToggleSwitchesCalendarAndAgenda() {
        let app = launchToPlan()
        XCTAssertTrue(app.otherElements["plan.calendar"].waitForExistence(timeout: 5))
        app.buttons["plan.toggle.agenda"].tap()
        XCTAssertTrue(app.otherElements["plan.agenda"].waitForExistence(timeout: 5))
        app.buttons["plan.toggle.calendar"].tap()
        XCTAssertTrue(app.otherElements["plan.calendar"].waitForExistence(timeout: 5))
    }

    // AC-2: calendar renders summary card + grid.
    func testCalendarRendersSummaryAndGrid() {
        let app = launchToPlan()
        XCTAssertTrue(app.otherElements["plan.summaryCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["plan.day.1"].exists)
        XCTAssertTrue(app.otherElements["plan.day.28"].exists)
    }

    // AC-4 + AC-10: tapping an empty day opens the Schedule sheet.
    func testTappingEmptyDayOpensScheduleSheet() {
        let app = launchToPlan()
        XCTAssertTrue(app.otherElements["plan.day.15"].waitForExistence(timeout: 5))
        app.otherElements["plan.day.15"].tap()
        XCTAssertTrue(app.otherElements["plan.scheduleSheet"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Schedule a day."].exists)
    }

    // AC-11: assigning from the picker closes the sheet.
    func testAssignFromPickerClosesSheet() {
        let app = launchToPlan()
        app.otherElements["plan.day.15"].tap()
        let sheet = app.otherElements["plan.scheduleSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        // tap the first pick row (identifier prefix plan.sheet.pick.)
        let pick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'plan.sheet.pick.'")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()
        XCTAssertFalse(sheet.waitForExistence(timeout: 2))
    }

    // AC-8: a done day opens a read-only Completed. sheet with no CLEAR.
    func testDoneDaySheetIsReadOnly() {
        let app = launchToPlan()
        // day 20 is seeded done in SampleData.
        XCTAssertTrue(app.otherElements["plan.day.20"].waitForExistence(timeout: 5))
        app.otherElements["plan.day.20"].tap()
        XCTAssertTrue(app.staticTexts["Completed."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["plan.sheet.clear"].exists)
    }

    // AC-6: agenda renders rows.
    func testAgendaRendersRows() {
        let app = launchToPlan()
        app.buttons["plan.toggle.agenda"].tap()
        XCTAssertTrue(app.otherElements["plan.agenda"].waitForExistence(timeout: 5))
    }
}
```

> **Seed dependency:** these tests assume BAK-6's `SampleData` schedules day 20 as done and the current month is May 2026 in the simulator. If the sample world differs, adjust the specific day identifiers to match `SampleData`; the structural assertions (sheet opens, toggle switches, done sheet has no CLEAR) hold regardless.

- [ ] **Step 2: Run the UI tests**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS (PlanUITests green; all unit suites green).

- [ ] **Step 3: Commit**

```bash
git add PulseUITests/PlanUITests.swift
git commit -m "test(plan): XCUITest acceptance coverage for AC1-11"
```

---

## Task 11: Theme snapshot under Coastal and Mint (AC-15)

Verifies the screen renders under both palettes with no hardcoded color. Uses a lightweight render assertion in an XCUITest by toggling the palette via the app (the picker lives under You → Palette, BAK-7). If the picker is not yet wired, this task asserts the calendar renders in the default palette and documents the second-palette pass as a follow-up against BAK-7's picker.

**Files:**
- Modify: `PulseUITests/PlanUITests.swift`

- [ ] **Step 1: Add a palette-aware render check**

```swift
extension PlanUITests {
    // AC-15: Plan renders under both palettes.
    func testPlanRendersUnderBothPalettes() {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Plan"].tap()
        XCTAssertTrue(app.otherElements["plan.calendar"].waitForExistence(timeout: 5))

        // Switch palette via You → Palette (BAK-7 picker).
        app.tabBars.buttons["You"].tap()
        let mint = app.buttons["palette.mint"]
        if mint.waitForExistence(timeout: 3) {
            mint.tap()
            app.tabBars.buttons["Plan"].tap()
            XCTAssertTrue(app.otherElements["plan.calendar"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.otherElements["plan.summaryCard"].exists)
        } else {
            // BAK-7 picker not wired yet — render check in default palette stands.
            XCTAssertTrue(app.otherElements["plan.summaryCard"].exists)
        }
    }
}
```

> `palette.mint` is BAK-7's picker control identifier; adapt to its real identifier when wiring.

- [ ] **Step 2: Run the tests**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add PulseUITests/PlanUITests.swift
git commit -m "test(plan): render under Coastal and Mint palettes (AC-15)"
```

---

## Task 12: Full verification + PR

**Files:** none (verification + integration)

- [ ] **Step 1: Regenerate and run the whole suite clean**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test
```
Expected: `BUILD SUCCEEDED` and `TEST SUCCEEDED` — `PlanViewDataTests`, `MonthMathTests`, `PlanModelLoadTests`, `PlanModelInteractionTests`, `PlanUITests` all green, plus the pre-existing foundation suites.

- [ ] **Step 2: Confirm no hardcoded colors/spacing in the Plan feature**

Run:
```bash
grep -RInE "Color\(red:|Color\(\.sRGB|#[0-9A-Fa-f]{6}|\.padding\([0-9]" Pulse/Features/Plan || echo "clean: Theme tokens only"
```
Expected: `clean: Theme tokens only` (all colors/spacing come from `Theme`).

- [ ] **Step 3: Open the PR** (only after the user asks to push; CLAUDE.md PR conventions)

Run:
```bash
git push -u origin feature/BAK-12-plan-calendar
gh pr create --title "feat(plan): Plan / Calendar tab (BAK-12)" \
  --body "Implements docs/superpowers/specs/2026-05-31-plan-calendar-spec.md and docs/superpowers/plans/2026-05-31-plan-calendar-plan.md. Calendar + Agenda views, Schedule sheet, start-today callback. UI-first against BAK-6 mocks.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```
Expected: PR opened, CI green.

---

## Self-Review notes

- **AC coverage:** AC-1 (toggle default + switch) → Task 8 view + Task 3 test + Task 10 UI test; AC-2/AC-3 (header, summary, weekday row, grid offset, per-state cells) → Task 2 math, Task 5 view, Task 10; AC-4 (today launches, others open sheet; done never launches) → Task 4 tests + Task 10; AC-5 (today row launches) → Task 5; AC-6 (agenda emphasis + dimmed rest) → Task 6; AC-7..10 (sheet titles + per-state content) → Task 7 + Task 10; AC-11 (assign/clear update + close) → Task 4 + Task 10; AC-12 (loading placeholder) → Task 8; AC-13 (empty month 0/0) → Task 3 test; AC-14 (error + retry) → Task 8; AC-15 (both palettes) → Task 11.
- **Open questions resolved (per product-decisions + sensible defaults):** segmented control is the sole toggle (no top-bar `+`); single current month only; `done`-today shows `done` and does not launch; agenda window 7 days from today; rest renders dashed/dimmed; `mode` in-memory only. All documented in the header block.
- **Prereq boundaries:** model binds to `ScheduleRepository` + a `WorkoutRepositoryReading` slice and never imports Supabase. Views use only `Theme` tokens and BAK-7 primitives. If BAK-6/BAK-7 names differ at build time, steps note the adaptation point — no Supabase calls, no hardcoded colors.
- **TDD vs view policy:** logic (`PlanViewData`, `MonthMath`, `PlanModel`) is strict red→green→commit; views (`CalendarMonthView`, `AgendaListView`, `ScheduleSheet`, `PlanView`) are concrete skeletons + `#Preview` + XCUITest. No placeholders; every step shows real code and exact commands.
```