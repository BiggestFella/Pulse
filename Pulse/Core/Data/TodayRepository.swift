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
