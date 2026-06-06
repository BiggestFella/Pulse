import Foundation
import Supabase

/// The Plan calendar, backed by `plan_entries` (one row per user per day,
/// `unique(user_id, date)`). `state` + the nullable FKs encode the `DayPlan`:
/// `planned` carries a `workout_id`, `done` a `session_id`, `rest` neither.
struct SupabaseScheduleRepository: ScheduleRepository {
    let client: SupabaseClient

    /// Postgres `date` is tz-naive — the shared timestamptz decoder can't parse it,
    /// so plan-entry dates are decoded as strings and converted here. The local
    /// time zone is used so a day stored as "2026-06-04" round-trips to the same
    /// local calendar day the user scheduled (and lines up with `cal.startOfDay`).
    static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    fileprivate struct PlanEntryRow: Decodable {
        let date: String
        let workoutId: UUID?
        let sessionId: UUID?
        let state: String
        func toDayPlan() -> DayPlan? {
            switch state {
            case "planned": return workoutId.map { DayPlan.workout($0) }
            case "rest":    return .rest
            case "done":    return sessionId.map { DayPlan.done($0) }
            default:        return nil
            }
        }
    }

    private struct PlanEntryWriteRow: Encodable {
        let userId: UUID
        let date: String
        let workoutId: UUID?
        let sessionId: UUID?
        let state: String
        enum CodingKeys: String, CodingKey { case userId, date, workoutId, sessionId, state }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(userId, forKey: .userId)
            try c.encode(date, forKey: .date)
            try c.encode(workoutId, forKey: .workoutId)   // explicit null clears on upsert
            try c.encode(sessionId, forKey: .sessionId)
            try c.encode(state, forKey: .state)
        }
    }

    func plan(for date: Date) async throws -> DayPlan? {
        let rows: [PlanEntryRow] = try await client
            .from("plan_entries").select("*")
            .eq("date", value: Self.dateFmt.string(from: date)).limit(1)
            .execute().value
        return rows.first?.toDayPlan()
    }

    func upcoming(from date: Date, days: Int) async throws -> [(date: Date, plan: DayPlan)] {
        guard days > 0,
              let end = SampleData.calendar.date(byAdding: .day, value: days - 1, to: date)
        else { return [] }
        let rows: [PlanEntryRow] = try await client
            .from("plan_entries").select("*")
            .gte("date", value: Self.dateFmt.string(from: date))
            .lte("date", value: Self.dateFmt.string(from: end))
            .order("date")
            .execute().value
        return rows.compactMap { row -> (date: Date, plan: DayPlan)? in
            guard let day = Self.dateFmt.date(from: row.date), let plan = row.toDayPlan() else { return nil }
            return (day, plan)
        }
    }

    func setPlan(_ plan: DayPlan?, on date: Date) async throws {
        let dateString = Self.dateFmt.string(from: date)
        guard let plan else {
            try await client.from("plan_entries").delete().eq("date", value: dateString).execute()
            return
        }
        let userID = try await client.auth.session.user.id
        let row: PlanEntryWriteRow
        switch plan {
        case .workout(let id):
            row = PlanEntryWriteRow(userId: userID, date: dateString,
                                    workoutId: id, sessionId: nil, state: "planned")
        case .rest:
            row = PlanEntryWriteRow(userId: userID, date: dateString,
                                    workoutId: nil, sessionId: nil, state: "rest")
        case .done(let id):
            row = PlanEntryWriteRow(userId: userID, date: dateString,
                                    workoutId: nil, sessionId: id, state: "done")
        }
        try await client.from("plan_entries").upsert(row, onConflict: "user_id,date").execute()
    }

    /// All of the user's plan entries keyed by local start-of-day. Used by the
    /// derived stats streak (not part of the protocol).
    func fullSchedule() async throws -> [Date: DayPlan] {
        let rows: [PlanEntryRow] = try await client.from("plan_entries").select("*").execute().value
        var dict: [Date: DayPlan] = [:]
        for row in rows {
            guard let day = Self.dateFmt.date(from: row.date), let plan = row.toDayPlan() else { continue }
            dict[SampleData.calendar.startOfDay(for: day)] = plan
        }
        return dict
    }
}
