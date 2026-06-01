import Foundation

@MainActor
struct InMemoryScheduleRepository: ScheduleRepository {
    let store: MockStore
    private var cal: Calendar { SampleData.calendar }

    func plan(for date: Date) async throws -> DayPlan? {
        try await store.gate(); return store.schedule[cal.startOfDay(for: date)]
    }
    func upcoming(from date: Date, days: Int) async throws -> [(date: Date, plan: DayPlan)] {
        try await store.gate()
        let start = cal.startOfDay(for: date)
        return (0..<days).compactMap { offset -> (Date, DayPlan)? in
            guard let day = cal.date(byAdding: .day, value: offset, to: start),
                  let plan = store.schedule[day] else { return nil }
            return (day, plan)
        }.sorted { $0.0 < $1.0 }
    }
    func setPlan(_ plan: DayPlan?, on date: Date) async throws {
        try await store.gate()
        let day = cal.startOfDay(for: date)
        if let plan { store.schedule[day] = plan } else { store.schedule[day] = nil }
    }
}
