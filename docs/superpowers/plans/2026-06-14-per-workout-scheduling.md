# Per-workout Scheduling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a workout recurring `weekdays`, reconcile recurrence with the per-date `plan_entries` via one shared resolver (specific entry → recurring weekday → empty), add a minimal weekday editor on Workout Detail, and make Start launch the real scheduled workout (BAK-42).

**Architecture:** `Workout.weekday: Int?` becomes `weekdays: [Int]`. A pure `ScheduleResolver` computes the effective `DayPlan?` for a date and is shared by `TodaySnapshotComposer` and `PlanModel` so Today and the Plan calendar agree. The Plan tab keeps editing per-date `plan_entries` (specific dates win).

**Tech Stack:** SwiftUI, `@Observable`, Swift Concurrency, Supabase (PostgREST), XcodeGen, XCTest/XCUITest.

**Spec:** `docs/superpowers/specs/2026-06-14-per-workout-scheduling-design.md` · **Linear:** [BAK-57](https://linear.app/bakinglions/issue/BAK-57) (subsumes BAK-42)

---

## Conventions (read once)
- After creating any new `.swift` file run `xcodegen generate` before building (`.xcodeproj` gitignored; `Pulse/`, `PulseTests/`, `PulseUITests/` are globbed — no `project.yml` edit). Don't commit `.xcodeproj`/`project.yml`.
- Test sim: `-destination 'platform=iOS Simulator,name=iPhone 17'`. Single test: `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/<Class>/<method>`. UI tests run too (`-only-testing:PulseUITests/<Class>`). Confirm via `** TEST SUCCEEDED **` in the log (piping to `tail` masks the exit code).
- Theme tokens only; follow existing patterns. Migrations are files applied via the Supabase dashboard.

---

## Task 1: Rename `Workout.weekday` → `weekdays: [Int]` (model + migration + persistence + consumers green)

Renaming the model field breaks every reader, so this task changes them all together and keeps the suite green. No behaviour change yet beyond "a workout can hold multiple recurring days."

**Files:**
- Modify: `Pulse/Core/Models/WorkoutModels.swift`
- Create: `supabase/migrations/0009_workout_weekdays.sql`
- Modify: `Pulse/Core/Data/Supabase/Rows/Rows.swift`, `Pulse/Core/Data/Supabase/Rows/WriteRows.swift`
- Modify: `Pulse/Core/Data/Supabase/SupabaseWorkoutRepository.swift`, `Pulse/Core/Data/Mock/InMemoryWorkoutRepository.swift`
- Modify: `Pulse/Core/Data/Mock/SampleData.swift`
- Test: `PulseTests/Data/SampleDataTests.swift` (existing BAK-38 test), `PulseTests/Core/Models/WorkoutWeekdaysTests.swift` (new)

- [ ] **Step 1: Failing test** — `PulseTests/Core/Models/WorkoutWeekdaysTests.swift`:
```swift
import XCTest
@testable import Pulse

@MainActor
final class WorkoutWeekdaysTests: XCTestCase {
    func testDefaultIsEmpty() {
        XCTAssertEqual(Workout(name: "x", order: 0, exercises: []).weekdays, [])
    }
    func testTodaysWorkoutMatchesAnyWeekdayInSet() async throws {
        let store = MockStore()
        let repo = InMemoryWorkoutRepository(store: store)
        // A Monday: 2026-06-15 is a Monday → appWeekday 1.
        let monday = SampleData.calendar.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let hero = try await repo.todaysWorkout(on: monday)
        XCTAssertEqual(hero?.id, SampleData.pushWorkout.id)   // Push recurs on [1]
    }
}
```
Note: `Workout(name:order:exercises:)` omits `weekday`/`weekdays` (defaulted). If the memberwise init currently requires `weekday`, this test also proves the new default.

- [ ] **Step 2: Run → FAIL** (`weekdays` undefined): `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests/WorkoutWeekdaysTests` after `xcodegen generate`.

- [ ] **Step 3: Model** — in `WorkoutModels.swift` change `Workout`:
```swift
struct Workout: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var weekdays: [Int] = []     // 1...7 (Mon…Sun), empty = unscheduled
    var order: Int
    var exercises: [WorkoutExercise]
    var targets: [MuscleGroup] = []
}
```

- [ ] **Step 4: Migration** — `supabase/migrations/0009_workout_weekdays.sql`:
```sql
-- BAK-57: a workout recurs on multiple weekdays. Replace the single `weekday`
-- with a `weekdays int[]`, backfilling existing single-day workouts.
alter table workouts add column weekdays int[] not null default '{}';
update workouts set weekdays = array[weekday] where weekday is not null;
alter table workouts drop column weekday;
```
(Apply via the Supabase dashboard.)

- [ ] **Step 5: Row mapping** — `Rows.swift` `WorkoutRow`: replace `let weekday: Int?` with `let weekdays: [Int]?`, and in `toModel()` replace `weekday: weekday` with `weekdays: weekdays ?? []`. `WriteRows.swift` `WorkoutWriteRow`: replace `let weekday: Int?` with `let weekdays: [Int]`; in `CodingKeys` replace `weekday` with `weekdays`; in `encode` replace the weekday line with `try c.encode(weekdays, forKey: .weekdays)`. In `WorkoutGraphWriter.insert`, replace `weekday: $0.weekday` with `weekdays: $0.weekdays`.

- [ ] **Step 6: Repositories** — `SupabaseWorkoutRepository.todaysWorkout(on:)`: replace the `.eq("weekday", value: appWeekday)` filter with `.contains("weekdays", value: [appWeekday])`. `InMemoryWorkoutRepository.todaysWorkout(on:)`: replace `first { $0.weekday == appWeekday }` with `first { $0.weekdays.contains(appWeekday) }`.

- [ ] **Step 7: Mock data** — `SampleData.swift`: `pushWorkout` `weekday: 1` → `weekdays: [1]`; Pull `weekday: 3` → `weekdays: [3]`; Legs `weekday: 5` → `weekdays: [5]`. In the `schedule` generator replace `$0.weekday == appWeekday` with `$0.weekdays.contains(appWeekday)`.

- [ ] **Step 8: Fix any other `weekday` references** — `grep -rn "\.weekday\b\|weekday:" Pulse PulseTests | grep -vi "weekdays\|component(.weekday"`. Update each (e.g. `Pulse/Core/Data/Mocks/TodaysWorkout.swift` if it sets `weekday:`). The BAK-38 test `testScheduledWorkoutsAgreeWithWeekdayHero` should still pass unchanged (it only reads `todaysWorkout`); confirm it compiles.

- [ ] **Step 9: Run the full suite green** — `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests`. Expected: `** TEST SUCCEEDED **`, 0 failures (incl. the new `WorkoutWeekdaysTests` and the existing BAK-38 test).

- [ ] **Step 10: Commit**
```bash
git add Pulse/Core/Models/WorkoutModels.swift supabase/migrations/0009_workout_weekdays.sql Pulse/Core/Data/Supabase/Rows/Rows.swift Pulse/Core/Data/Supabase/Rows/WriteRows.swift Pulse/Core/Data/Supabase/SupabaseWorkoutRepository.swift Pulse/Core/Data/Mock/InMemoryWorkoutRepository.swift Pulse/Core/Data/Mock/SampleData.swift PulseTests/Core/Models/WorkoutWeekdaysTests.swift PulseTests/Data/SampleDataTests.swift
git commit -m "feat(scheduling): Workout.weekdays (recurring multi-day) + 0009 migration [BAK-57]"
```

---

## Task 2: `ScheduleResolver` (pure) + tests

**Files:**
- Create: `Pulse/Core/Workout/ScheduleResolver.swift`
- Test: `PulseTests/Core/Workout/ScheduleResolverTests.swift`

- [ ] **Step 1: Failing tests** — `PulseTests/Core/Workout/ScheduleResolverTests.swift`:
```swift
import XCTest
@testable import Pulse

final class ScheduleResolverTests: XCTestCase {
    private let cal = SampleData.calendar
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func workout(_ name: String, order: Int, weekdays: [Int]) -> Workout {
        Workout(name: name, weekdays: weekdays, order: order, exercises: [])
    }

    func testAppWeekdayMapsMondayTo1AndSundayTo7() {
        XCTAssertEqual(ScheduleResolver.appWeekday(of: date(2026, 6, 15), calendar: cal), 1) // Mon
        XCTAssertEqual(ScheduleResolver.appWeekday(of: date(2026, 6, 21), calendar: cal), 7) // Sun
    }
    func testSpecificEntryWins() {
        let w = workout("A", order: 0, weekdays: [1])
        let entry = DayPlan.rest
        XCTAssertEqual(ScheduleResolver.plan(for: date(2026, 6, 15), entry: entry, workouts: [w], calendar: cal), .rest)
    }
    func testRecurringWeekdayWhenNoEntry() {
        let w = workout("A", order: 0, weekdays: [1])
        XCTAssertEqual(ScheduleResolver.plan(for: date(2026, 6, 15), entry: nil, workouts: [w], calendar: cal), .workout(w.id))
    }
    func testEmptyWhenNeither() {
        let w = workout("A", order: 0, weekdays: [3])
        XCTAssertNil(ScheduleResolver.plan(for: date(2026, 6, 15), entry: nil, workouts: [w], calendar: cal)) // Mon, w is Wed-only
    }
    func testTiebreakByLowestOrder() {
        let a = workout("A", order: 1, weekdays: [1])
        let b = workout("B", order: 0, weekdays: [1])
        XCTAssertEqual(ScheduleResolver.plan(for: date(2026, 6, 15), entry: nil, workouts: [a, b], calendar: cal), .workout(b.id))
    }
}
```

- [ ] **Step 2: Run → FAIL** (`ScheduleResolver` undefined). `xcodegen generate` first.

- [ ] **Step 3: Implement** — `Pulse/Core/Workout/ScheduleResolver.swift`:
```swift
import Foundation

/// Computes the effective plan for a date by reconciling the per-date schedule
/// (`plan_entries`) with each workout's recurring `weekdays`. Pure + testable;
/// shared by Today and the Plan tab so they always agree.
enum ScheduleResolver {
    /// Gregorian weekday (1=Sun…7=Sat) → app weekday (Mon=1…Sun=7).
    static func appWeekday(of date: Date, calendar: Calendar) -> Int {
        let greg = calendar.component(.weekday, from: date)
        return ((greg + 5) % 7) + 1
    }

    /// Precedence: a specific `plan_entry` wins; else the recurring workout whose
    /// `weekdays` include this weekday (lowest `order`); else `nil` (no plan —
    /// callers map that to their own empty/rest state).
    static func plan(for date: Date, entry: DayPlan?,
                     workouts: [Workout], calendar: Calendar) -> DayPlan? {
        if let entry { return entry }
        let wd = appWeekday(of: date, calendar: calendar)
        if let w = workouts.filter({ $0.weekdays.contains(wd) })
                           .sorted(by: { $0.order < $1.order }).first {
            return .workout(w.id)
        }
        return nil
    }
}
```

- [ ] **Step 4: Run → PASS.** `xcodebuild test … -only-testing:PulseTests/ScheduleResolverTests`.

- [ ] **Step 5: Commit**
```bash
git add Pulse/Core/Workout/ScheduleResolver.swift PulseTests/Core/Workout/ScheduleResolverTests.swift
git commit -m "feat(scheduling): pure ScheduleResolver (specific > recurrence > empty) [BAK-57]"
```

---

## Task 3: Wire the resolver into Today + Plan

Make Today's hero/week-strip and the Plan calendar/agenda compute through `ScheduleResolver`, so a workout's recurring weekdays show automatically and specific dates override.

**Files:**
- Modify: `Pulse/Features/Today/TodaySnapshotComposer.swift`
- Modify: `Pulse/Features/Plan/PlanModel.swift`
- Test: `PulseTests/Features/Plan/PlanScheduleResolutionTests.swift` (new)

- [ ] **Step 1: Failing test** — drive it through `PlanModel` (it owns both repos). `PulseTests/Features/Plan/PlanScheduleResolutionTests.swift`:
```swift
import XCTest
@testable import Pulse

@MainActor
final class PlanScheduleResolutionTests: XCTestCase {
    func testRecurringWorkoutAppearsOnItsWeekdayWithoutAPlanEntry() async throws {
        let store = MockStore()
        store.schedule = [:]   // no per-date entries at all
        let cal = SampleData.calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!  // Monday
        let model = PlanModel(schedule: InMemoryScheduleRepository(store: store),
                              workouts: InMemoryWorkoutRepository(store: store),
                              calendar: cal, now: now)
        await model.load()
        // Push recurs on Monday ([1]); the agenda's first (today) row should name it.
        XCTAssertEqual(model.agenda.first?.name, "Push")
    }
}
```
(If `MockStore.schedule`/`allWorkouts` need seeding, seed `store.programs = [SampleData.program]` so `fetchWorkouts` returns Push/Pull/Legs; confirm `MockStore`'s API and adjust the setup.)

- [ ] **Step 2: Run → FAIL** (today's agenda row is empty because PlanModel only reads `plan_entries`, which are empty).

- [ ] **Step 3: PlanModel** — load workouts once per refresh and resolve each day. In the load path (where `workoutNames` is populated), also keep the `[Workout]`. Replace the raw `scheduleRepo.plan(for:)` reads in `buildSchedule` and `buildAgenda` with the resolver:
```swift
// buildSchedule:
let workouts = try await workoutRepo.fetchWorkouts()
var map: [Int: ScheduledDay] = [:]
for day in 1...month.daysInMonth {
    let date = dateFor(day: day)
    let entry = try await scheduleRepo.plan(for: date)
    let plan = ScheduleResolver.plan(for: date, entry: entry, workouts: workouts, calendar: calendar)
    map[day] = mapDay(day: day, plan: plan)
}
schedule = map
```
```swift
// buildAgenda: resolve per day instead of reading `upcoming` raw.
let workouts = try await workoutRepo.fetchWorkouts()
var rows: [AgendaEntry] = []
for offset in 0..<7 {
    let date = calendar.date(byAdding: .day, value: offset, to: startOfDay(now))!
    let day = calendar.component(.day, from: date)
    let entry = try await scheduleRepo.plan(for: date)
    let plan = ScheduleResolver.plan(for: date, entry: entry, workouts: workouts, calendar: calendar)
    // ...existing switch on `plan` (DayPlan?) building AgendaEntry, unchanged...
}
agenda = rows
```
Keep `mapDay(day:plan:)` and the agenda `switch` exactly as they are (both already accept a `DayPlan?` and map `nil` → empty/rest). Ensure `workoutNames` is populated from the same `workouts` so agenda/calendar names resolve.

- [ ] **Step 4: TodaySnapshotComposer** — route the hero + week strip through the resolver. `compose` already loads `allWorkouts`; pass them down.
```swift
// composeCard: resolve today instead of calling todaysWorkout directly.
private func composeCard(now: Date, profile: UserProfile, completedCount: Int,
                         workouts: [Workout]) async throws -> TodayWorkoutCard? {
    let today = calendar.startOfDay(for: now)
    let entry = try await schedule.plan(for: today)
    guard case let .workout(id)? = ScheduleResolver.plan(for: today, entry: entry,
                                                         workouts: workouts, calendar: calendar),
          let workout = workouts.first(where: { $0.id == id }) ?? (try await self.workouts.fetchWorkout(id: id))
    else { return nil }   // .done / .rest / nil → no startable hero
    let perWeek = max(1, (try await programs.activeProgram())?.workouts.count ?? 1)
    let day = completedCount + 1
    let week = (day + perWeek - 1) / perWeek
    return TodayWorkoutCard(workoutID: workout.id, programLabel: profile.programLabel,
                            week: week, day: day, name: workout.name,
                            exerciseCount: workout.exercises.count,
                            estimatedMinutes: max(1, workout.exercises.count) * 9)
}
```
```swift
// composeWeek: each cell resolves via the resolver (pass `workouts`).
let plan = ScheduleResolver.plan(for: day, entry: try await schedule.plan(for: day),
                                 workouts: workouts, calendar: calendar)
switch plan {                       // DayPlan? — same cases as today, nil → .rest
case .done(let sessionID)?: ...
case .workout(let id)?:    ...
case .rest?, nil:          state = .rest; label = "Rest"
}
```
Update `compose` to pass `workouts: allWorkouts` into `composeCard` and `composeWeek`. (`composeWeek` already builds `workoutName`; keep it.)

- [ ] **Step 5: Run → PASS** the new test + the existing Today/Plan suites: `xcodebuild test … -only-testing:PulseTests/PlanScheduleResolutionTests -only-testing:PulseTests/PlanModelTests -only-testing:PulseTests/TodayModelTests` (use the actual existing test class names — `grep -rl "PlanModel\|TodaySnapshotComposer" PulseTests`). Fix fallout.

- [ ] **Step 6: Commit**
```bash
git add Pulse/Features/Today/TodaySnapshotComposer.swift Pulse/Features/Plan/PlanModel.swift PulseTests/Features/Plan/PlanScheduleResolutionTests.swift
git commit -m "feat(scheduling): Today + Plan resolve recurrence via ScheduleResolver [BAK-57]"
```

---

## Task 4: Weekday editor + schedule-on-date on Workout Detail

**Files:**
- Modify: `Pulse/Features/Library/WorkoutDetailModel.swift`, `Pulse/Features/Library/WorkoutDetailView.swift`
- Modify: `Pulse/Features/Library/LibraryView.swift` (pass the schedule repo into the detail model — see Step 4)
- Test: `PulseTests/Features/Library/WorkoutDetailScheduleTests.swift` (new)

- [ ] **Step 1: Failing test** — `PulseTests/Features/Library/WorkoutDetailScheduleTests.swift`:
```swift
import XCTest
@testable import Pulse

@MainActor
final class WorkoutDetailScheduleTests: XCTestCase {
    private func model(_ store: MockStore, _ w: Workout) -> WorkoutDetailModel {
        WorkoutDetailModel(workoutID: w.id, title: w.name,
                           workoutRepo: InMemoryWorkoutRepository(store: store),
                           scheduleRepo: InMemoryScheduleRepository(store: store),
                           onStart: { _ in })
    }
    func testToggleWeekdayPersists() async {
        let store = MockStore(); store.programs = [SampleData.program]
        let w = SampleData.pushWorkout                  // weekdays [1]
        let m = model(store, w)
        await m.load()
        await m.toggleWeekday(5)                        // add Friday
        let reloaded = try? await InMemoryWorkoutRepository(store: store).fetchWorkout(id: w.id)
        XCTAssertEqual(Set(reloaded?.weekdays ?? []), [1, 5])
    }
    func testScheduleOnDateWritesPlanEntry() async {
        let store = MockStore(); store.programs = [SampleData.program]
        let date = SampleData.calendar.date(from: DateComponents(year: 2026, month: 6, day: 16))!
        let m = model(store, SampleData.pushWorkout)
        await m.load()
        await m.scheduleOnDate(date)
        let entry = try? await InMemoryScheduleRepository(store: store).plan(for: date)
        XCTAssertEqual(entry, .workout(SampleData.pushWorkout.id))
    }
}
```
(Confirm `MockStore` lets `fetchWorkout` find a program workout; `SampleData.program` contains Push/Pull/Legs. Adjust seeding to match `MockStore`'s real API.)

- [ ] **Step 2: Run → FAIL** (`scheduleRepo` param / `toggleWeekday` / `scheduleOnDate` undefined).

- [ ] **Step 3: Model** — add a `ScheduleRepository` + intents to `WorkoutDetailModel`:
```swift
private let scheduleRepo: any ScheduleRepository
// add `scheduleRepo` to init (after workoutRepo) and store it.

private(set) var weekdays: Set<Int> = []

// in load(), after `workout = w`:
weekdays = Set(w.weekdays)

func toggleWeekday(_ day: Int) async {
    guard var w = workout else { return }
    if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
    w.weekdays = [1,2,3,4,5,6,7].filter { weekdays.contains($0) }   // canonical order
    do { _ = try await workoutRepo.saveWorkout(w); workout = w } catch { }
}

func scheduleOnDate(_ date: Date) async {
    guard let id = workout?.id else { return }
    try? await scheduleRepo.setPlan(.workout(id), on: date)
}
```

- [ ] **Step 4: View + wiring** — in `WorkoutDetailView`, add (in the `.loaded` content, above the rows) a "REPEATS ON" row of 7 weekday toggle chips (M T W T F S S → days 1…7) bound to `model.weekdays`/`model.toggleWeekday`, each `accessibilityIdentifier("repeat-day-\(day)")` and `.isSelected` when on; and a "Schedule on a date" button presenting a `DatePicker` sheet that calls `model.scheduleOnDate`. Use `PillChip`/Theme tokens. Then update the **two** `WorkoutDetailModel(...)` construction sites in `LibraryView.swift` (the `.workoutDetail` route) to pass `scheduleRepo: repos.schedule`. (`grep -n "WorkoutDetailModel(" Pulse/Features/Library/LibraryView.swift`.)

- [ ] **Step 5: Run → PASS** the new tests + existing `WorkoutDetailModelTests`. `xcodegen generate` (new test file) first.

- [ ] **Step 6: Commit**
```bash
git add Pulse/Features/Library/WorkoutDetailModel.swift Pulse/Features/Library/WorkoutDetailView.swift Pulse/Features/Library/LibraryView.swift PulseTests/Features/Library/WorkoutDetailScheduleTests.swift
git commit -m "feat(scheduling): Workout Detail weekday editor + schedule-on-date [BAK-57]"
```

---

## Task 5: BAK-42 — Start launches the real scheduled workout

**Files:**
- Modify: `Pulse/App/AppShell.swift`
- Delete: `Pulse/Core/Data/Mocks/TodaysWorkout.swift` (once unused)
- Test: `PulseTests/App/StartResolutionTests.swift` (new — drive the resolution helper, not the View)

- [ ] **Step 1:** Extract the "today's effective workout" resolution into a testable async helper (so it isn't trapped in `AppShell.init`). Add to `WorkoutRepository` (or a small composer) — simplest: a method on the existing repos isn't ideal; instead add a free async function in `AppShell` file or a `TodayWorkoutResolver`:
```swift
// Pulse/Core/Workout/TodayWorkoutResolver.swift
import Foundation
@MainActor
enum TodayWorkoutResolver {
    /// The hydrated workout to launch for `date`, or nil if today is rest/empty/done.
    static func workout(on date: Date, schedule: any ScheduleRepository,
                        workouts: any WorkoutRepository, calendar: Calendar) async throws -> Workout? {
        let day = calendar.startOfDay(for: date)
        let entry = try await schedule.plan(for: day)
        let all = try await workouts.fetchWorkouts()
        guard case let .workout(id)? = ScheduleResolver.plan(for: day, entry: entry,
                                                            workouts: all, calendar: calendar)
        else { return nil }
        return try await workouts.fetchWorkout(id: id)
    }
}
```
**Failing test** — `PulseTests/App/StartResolutionTests.swift`:
```swift
import XCTest
@testable import Pulse

@MainActor
final class StartResolutionTests: XCTestCase {
    func testResolvesTodaysRecurringWorkout() async throws {
        let store = MockStore(); store.programs = [SampleData.program]; store.schedule = [:]
        let cal = SampleData.calendar
        let monday = cal.date(from: DateComponents(year: 2026, month: 6, day: 15))!
        let w = try await TodayWorkoutResolver.workout(on: monday,
                  schedule: InMemoryScheduleRepository(store: store),
                  workouts: InMemoryWorkoutRepository(store: store), calendar: cal)
        XCTAssertEqual(w?.id, SampleData.pushWorkout.id)
    }
}
```

- [ ] **Step 2: Run → FAIL** (`TodayWorkoutResolver` undefined). `xcodegen generate` first.

- [ ] **Step 3: Implement** the resolver file above.

- [ ] **Step 4: Run → PASS** `-only-testing:PulseTests/StartResolutionTests`.

- [ ] **Step 5: Wire AppShell** — replace the hardcoded `startWorkout`. `AppShell` should resolve today's workout asynchronously and pass it to Start. Minimal change: give `TodayView`/`PlanView` Start a closure that resolves at tap time:
```swift
// where Start is wired (Today/Plan/Library callbacks):
onStartWorkout: {
    Task {
        if let w = try? await TodayWorkoutResolver.workout(on: Date(),
                       schedule: container.schedule, workouts: container.workouts,
                       calendar: .current) {
            session.startWorkout(w)
        }
    }
}
```
Remove the `let startWorkout = … TodaysWorkout.workout` line and the `PlanView(onStartWorkout: { session.startWorkout(startWorkout) })` hardcoding (Plan's Start resolves the same way). Keep `LibraryView(onStartWorkout: { session.startWorkout($0) })` (it already passes the chosen workout). Confirm `container` exposes `schedule` + `workouts` repositories (it does — `RepositoryContainer`).

- [ ] **Step 6: Delete `TodaysWorkout.swift`** if no references remain (`grep -rn "TodaysWorkout" Pulse PulseTests`); `xcodegen generate`.

- [ ] **Step 7: Run the full suite green** — `xcodebuild test … -only-testing:PulseTests`.

- [ ] **Step 8: Commit**
```bash
git add Pulse/App/AppShell.swift Pulse/Core/Workout/TodayWorkoutResolver.swift PulseTests/App/StartResolutionTests.swift
git rm Pulse/Core/Data/Mocks/TodaysWorkout.swift
git commit -m "feat(scheduling): Start launches the resolved scheduled workout; drop hardcoded TodaysWorkout [BAK-42][BAK-57]"
```

---

## Task 6: Acceptance + UI test + full-suite green

**Files:**
- Test: `PulseTests/Features/SchedulingAcceptanceTests.swift` (new), `PulseUITests/WorkoutScheduleUITests.swift` (new)

- [ ] **Step 1: Acceptance (model-level)** — `PulseTests/Features/SchedulingAcceptanceTests.swift`: set a workout to Mon+Fri via `WorkoutDetailModel.toggleWeekday`, then assert (a) `TodayWorkoutResolver.workout(on:)` returns it on a Monday and a Friday, (b) a specific `plan_entry` on that Monday for a *different* workout overrides it, (c) `PlanModel.agenda` names it on its recurring day. Reuse the patterns from Tasks 3–5 (InMemory repos + `SampleData.program`).

- [ ] **Step 2: UI test** — `PulseUITests/WorkoutScheduleUITests.swift`: launch `-uiMock`, open Library, tap a saved workout to reach `workoutDetail.title`, tap `repeat-day-5` (Friday), assert it becomes selected (`.isSelected`). Navigation per `LibraryTabTests` (open Library → tap the workout row that routes to `WorkoutDetailView`). If the mock Library doesn't expose a directly-tappable saved workout at root, reach it via the seeded folder/program; inspect with `app.debugDescription` and use the real id.

- [ ] **Step 3: Run** `-only-testing:PulseTests/SchedulingAcceptanceTests` and `-only-testing:PulseUITests/WorkoutScheduleUITests` (after `xcodegen generate`); iterate to green.

- [ ] **Step 4: Full gated suite** — `xcodebuild test -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:PulseTests` then `-only-testing:PulseUITests`. Report totals; 0 failures.

- [ ] **Step 5: Commit**
```bash
git add PulseTests/Features/SchedulingAcceptanceTests.swift PulseUITests/WorkoutScheduleUITests.swift
git commit -m "test(scheduling): acceptance + UI coverage for per-workout scheduling [BAK-57]"
```

---

## Final verification (before PR)
- [ ] `xcodegen generate`; full `PulseTests` + `PulseUITests` green on iPhone 17.
- [ ] Apply `0009_workout_weekdays.sql` in the Supabase dashboard (live path).
- [ ] Smoke on device: set a workout to repeat Mon+Fri → it shows on those days in Today + Plan; schedule it on a one-off date → that date shows it; Start launches the scheduled workout.
- [ ] `code-reviewer` + `/security-review`; PR; move BAK-57 → Done on merge, and close BAK-42 (subsumed).

## Out of scope (per spec)
Frequency (every-N-days), cooldowns, dashboard card "Layout", calendar "Pattern", the rich Schedule *step* (SP3 wizard), settings sheet (SP4). Streaks unchanged.
