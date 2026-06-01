import Foundation

@MainActor
struct InMemoryPRRepository: PRRepository {
    let store: MockStore
    private var cal: Calendar { SampleData.calendar }

    private func records(newWithin range: StatRange?) -> [PersonalRecord] {
        struct Candidate { let set: SessionSet; let date: Date }
        var bestByExercise: [Exercise.ID: Candidate] = [:]
        for session in store.sessions {
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
            let variationID = store.exercises.first { $0.id == exID }?.defaultVariationID
            let isNew = rangeStart.map { c.date > $0 } ?? true
            return PersonalRecord(
                exerciseID: exID, variationID: variationID,
                weight: c.set.weight, reps: c.set.reps,
                estimatedOneRepMax: WorkoutAnalytics.estimatedOneRepMax(c.set),
                achievedAt: c.date, isNew: isNew)
        }
    }

    func allPRs() async throws -> [PersonalRecord] {
        try await store.gate(); return records(newWithin: nil)
    }
    func prs(muscleGroup: String) async throws -> [PersonalRecord] {
        try await store.gate()
        let ids = Set(store.exercises.filter { $0.muscleGroup == muscleGroup }.map(\.id))
        return records(newWithin: nil).filter { ids.contains($0.exerciseID) }
    }
    func personalBest(forExercise: Exercise.ID) async throws -> PersonalRecord? {
        try await store.gate()
        return records(newWithin: nil).first { $0.exerciseID == forExercise }
    }
    func newPRs(in range: StatRange) async throws -> [PersonalRecord] {
        try await store.gate()
        return records(newWithin: range).filter(\.isNew)
    }
}
