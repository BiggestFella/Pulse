import Foundation

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

    private let scheduleRepo: any ScheduleRepository
    private let workoutRepo: any WorkoutRepository
    private let calendar: Calendar
    private let now: Date
    private let todayDay: Int
    private var workoutNames: [Workout.ID: String] = [:]

    init(schedule: any ScheduleRepository,
         workouts: any WorkoutRepository,
         calendar: Calendar = .current,
         now: Date = Date()) {
        self.scheduleRepo = schedule
        self.workoutRepo = workouts
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        self.calendar = cal
        self.now = now
        self.todayDay = cal.component(.day, from: now)
        self.month = MonthMath.context(for: now, calendar: cal)
    }

    func load() async {
        loadState = .loading
        do {
            let workouts = try await workoutRepo.fetchWorkouts()
            workoutNames = Dictionary(workouts.map { ($0.id, $0.name) },
                                      uniquingKeysWith: { lhs, _ in lhs })
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
        let byDay = Dictionary(
            upcoming.map { (calendar.component(.day, from: $0.date), $0.plan) },
            uniquingKeysWith: { lhs, _ in lhs })
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

    // MARK: - Sheet display strings

    /// Eyebrow for the Schedule sheet header, e.g. "MAY 15 · 2026".
    func sheetEyebrow(for day: Int) -> String {
        "\(month.monthAbbrevUpper) \(day) · \(String(month.year))"
    }

    /// Title reflects the day's state (AC-7).
    func sheetTitle(for day: Int) -> String {
        switch schedule[day]?.state {
        case .done:  return "Completed."
        case .plan, .today: return "Scheduled."
        default:     return "Schedule a day."
        }
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
