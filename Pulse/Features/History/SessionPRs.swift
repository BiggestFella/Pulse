import Foundation

/// Derives, for a single session, which exercises set a PR — i.e. whose best
/// est-1RM (Epley, warmups excluded) in that session strictly exceeds every
/// earlier session's best for the same exercise. PRs are computed, never stored
/// (product decision). All math goes through `WorkoutAnalytics` so it can't drift.
enum SessionPRs {
    /// Exercise ids that set a PR in `session`, given the full session list.
    static func prExerciseIDs(in session: WorkoutSession,
                              allSessions: [WorkoutSession]) -> [Exercise.ID] {
        // Best prior est-1RM per exercise, across sessions strictly before this one.
        var priorBest: [Exercise.ID: Double] = [:]
        for prior in allSessions where prior.startedAt < session.startedAt {
            for set in prior.sets where WorkoutAnalytics.counts(set.type) {
                let oneRM = WorkoutAnalytics.estimatedOneRepMax(set)
                priorBest[set.exerciseID] = max(priorBest[set.exerciseID] ?? 0, oneRM)
            }
        }

        var thisBest: [Exercise.ID: Double] = [:]
        for set in session.sets where WorkoutAnalytics.counts(set.type) {
            let oneRM = WorkoutAnalytics.estimatedOneRepMax(set)
            thisBest[set.exerciseID] = max(thisBest[set.exerciseID] ?? 0, oneRM)
        }

        return thisBest.compactMap { exID, best in
            best > (priorBest[exID] ?? 0) ? exID : nil
        }
    }

    static func count(in session: WorkoutSession,
                      allSessions: [WorkoutSession]) -> Int {
        prExerciseIDs(in: session, allSessions: allSessions).count
    }

    /// Convenience for a single-session world (no priors): every exercise with a
    /// counting set is a PR. Used where the caller has no session history.
    static func count(in session: WorkoutSession) -> Int {
        count(in: session, allSessions: [session])
    }
}
