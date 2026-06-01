import Foundation

/// Personal records, derived (est. 1RM via Epley) — not a stored table.
protocol PRRepository {
    func allPRs() async throws -> [PersonalRecord]
    func prs(muscleGroup: String) async throws -> [PersonalRecord]
    func personalBest(forExercise: Exercise.ID) async throws -> PersonalRecord?
    func newPRs(in range: StatRange) async throws -> [PersonalRecord]
}
