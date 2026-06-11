import Foundation

/// Advisory deload nudge derived from recent RIR trends. Display-only — never
/// mutates the program (auto-deload is an explicit non-goal). `nil` everywhere
/// means "no signal / not enough data".
struct DeloadSuggestion: Equatable {
    /// Floored average RIR across the recent tagged top working sets.
    let averageRIR: Int
    /// How many recent sessions contributed a tagged top set.
    let taggedSessionCount: Int
    /// Headline + body for the banner. Kept here so the view stays declarative.
    let title: String
    let message: String
}

/// Heuristic v1 (pure, no I/O). Over the most recent `window` sessions, take each
/// session's **top working set** (highest est-1RM among counting sets) and its
/// RIR when tagged. If at least `minTaggedSessions` of those are tagged AND the
/// floored average tagged RIR is ≤ `lowRIRThreshold` (consistently near failure),
/// return a suggestion; otherwise `nil` (no nagging on sparse or easy data).
///
/// - Parameters:
///   - recentSessions: any order; sorted newest-first internally.
///   - window: how many recent sessions to consider (default 6).
///   - minTaggedSessions: minimum tagged top sets required to fire (default 3).
///   - lowRIRThreshold: average at/below which we suggest a deload (default 1).
func deloadSuggestion(recentSessions: [WorkoutSession],
                      window: Int = 6,
                      minTaggedSessions: Int = 3,
                      lowRIRThreshold: Int = 1) -> DeloadSuggestion? {
    guard window > 0, minTaggedSessions > 0 else { return nil }

    let recent = recentSessions
        .sorted { $0.startedAt > $1.startedAt }
        .prefix(window)

    // Top working set's RIR per session, dropping sessions with no tagged top set.
    let topRIRs: [Int] = recent.compactMap { session in
        WorkoutAnalytics.bestSet(in: session.sets)?.rir
    }

    guard topRIRs.count >= minTaggedSessions else { return nil }

    let avg = topRIRs.reduce(0, +) / topRIRs.count   // integer floor
    guard avg <= lowRIRThreshold else { return nil }

    return DeloadSuggestion(
        averageRIR: avg,
        taggedSessionCount: topRIRs.count,
        title: "Hard stretch",
        message: "Your top sets have averaged RIR \(avg) over your last "
            + "\(topRIRs.count) sessions. Consider an easier week.")
}
