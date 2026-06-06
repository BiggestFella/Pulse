import Foundation
import Supabase

/// Personal records, derived client-side from logged sessions (est. 1RM via
/// Epley) — there is no stored PR table. Mirrors `InMemoryPRRepository`, fetching
/// the user's sessions + catalog from Supabase instead of the mock store.
struct SupabasePRRepository: PRRepository {
    let client: SupabaseClient
    private var cal: Calendar { SampleData.calendar }

    private func records(newWithin range: StatRange?,
                         sessions: [WorkoutSession],
                         exercises: [Exercise]) -> [PersonalRecord] {
        struct Candidate { let set: SessionSet; let date: Date }
        var bestByExercise: [Exercise.ID: Candidate] = [:]
        for session in sessions {
            for set in session.sets where WorkoutAnalytics.counts(set.type) {
                let oneRM = WorkoutAnalytics.estimatedOneRepMax(set)
                if let existing = bestByExercise[set.exerciseID] {
                    if oneRM > WorkoutAnalytics.estimatedOneRepMax(existing.set) {
                        bestByExercise[set.exerciseID] = Candidate(set: set, date: session.startedAt)
                    }
                } else {
                    bestByExercise[set.exerciseID] = Candidate(set: set, date: session.startedAt)
                }
            }
        }
        let rangeStart: Date? = range.flatMap { r in
            switch r {
            case .d7:   return cal.date(byAdding: .day, value: -7, to: Date())
            case .d30:  return cal.date(byAdding: .day, value: -30, to: Date())
            case .m3:   return cal.date(byAdding: .month, value: -3, to: Date())
            case .year: return cal.date(byAdding: .year, value: -1, to: Date())
            case .all:  return nil
            }
        }
        return bestByExercise.map { exID, c in
            let variationID = exercises.first { $0.id == exID }?.defaultVariationID
            let isNew = rangeStart.map { c.date > $0 } ?? true
            return PersonalRecord(
                exerciseID: exID, variationID: variationID,
                weight: c.set.weight, reps: c.set.reps,
                estimatedOneRepMax: WorkoutAnalytics.estimatedOneRepMax(c.set),
                achievedAt: c.date, isNew: isNew)
        }
    }

    func allPRs() async throws -> [PersonalRecord] {
        let (sessions, exercises) = try await loadInputs()
        return records(newWithin: nil, sessions: sessions, exercises: exercises)
    }

    func prs(muscleGroup: String) async throws -> [PersonalRecord] {
        let (sessions, exercises) = try await loadInputs()
        let ids = Set(exercises.filter { $0.muscleGroup == muscleGroup }.map(\.id))
        return records(newWithin: nil, sessions: sessions, exercises: exercises)
            .filter { ids.contains($0.exerciseID) }
    }

    func personalBest(forExercise: Exercise.ID) async throws -> PersonalRecord? {
        let (sessions, exercises) = try await loadInputs()
        return records(newWithin: nil, sessions: sessions, exercises: exercises)
            .first { $0.exerciseID == forExercise }
    }

    func newPRs(in range: StatRange) async throws -> [PersonalRecord] {
        let (sessions, exercises) = try await loadInputs()
        return records(newWithin: range, sessions: sessions, exercises: exercises).filter(\.isNew)
    }

    private func loadInputs() async throws -> ([WorkoutSession], [Exercise]) {
        async let sessions = SupabaseSessionRepository(client: client).fetchSessions(limit: nil)
        async let exercises = SupabaseExerciseRepository(client: client).fetchCatalog()
        return try await (sessions, exercises)
    }
}
