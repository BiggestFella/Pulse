import Foundation
import Observation

/// Read-only Personal Records screen model. Composes the merged BAK-6
/// `PRRepository` (derived PRs) with `ExerciseRepository` (to resolve each PR's
/// exercise name + muscle group, which `PersonalRecord` doesn't carry) and marks
/// "fresh this month" from `newPRs(in: .d30)`.
@MainActor
@Observable
final class PersonalRecordsModel {
    enum Phase: Equatable { case loading, loaded, empty, error }

    /// Display projection of a `PersonalRecord` (name/muscle resolved, freshness derived).
    struct Item: Identifiable, Equatable {
        let id: String
        let exerciseName: String
        let muscleGroup: String
        let weight: Double
        let reps: Int
        let estimatedOneRepMax: Double
        let achievedAt: Date
        let isFresh: Bool
    }

    private(set) var phase: Phase = .loading
    private(set) var records: [Item] = []     // sorted by est-1RM, descending
    var selectedMuscle: String?               // nil == "All"

    private let prRepo: any PRRepository
    private let exerciseRepo: any ExerciseRepository

    init(prRepo: any PRRepository, exerciseRepo: any ExerciseRepository) {
        self.prRepo = prRepo
        self.exerciseRepo = exerciseRepo
    }

    func load() async {
        phase = .loading
        do {
            let prs = try await prRepo.allPRs()
            let freshIDs = Set(try await prRepo.newPRs(in: .d30).map(\.id))
            let catalog = try await exerciseRepo.fetchCatalog()
            let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

            records = prs.map { pr in
                let ex = byID[pr.exerciseID]
                return Item(id: pr.id,
                            exerciseName: ex?.name ?? "Exercise",
                            muscleGroup: ex?.muscleGroup ?? "Other",
                            weight: pr.weight,
                            reps: pr.reps,
                            estimatedOneRepMax: pr.estimatedOneRepMax,
                            achievedAt: pr.achievedAt,
                            isFresh: freshIDs.contains(pr.id))
            }
            .sorted { $0.estimatedOneRepMax > $1.estimatedOneRepMax }

            phase = records.isEmpty ? .empty : .loaded
        } catch {
            phase = .error
        }
    }

    func select(_ muscle: String?) { selectedMuscle = muscle }
    func retry() async { await load() }

    // MARK: - derived

    /// Distinct muscle groups in stable (highest-PR-first) order.
    var muscleFilters: [String] {
        var seen: [String] = []
        for r in records where !seen.contains(r.muscleGroup) { seen.append(r.muscleGroup) }
        return seen
    }

    var filtered: [Item] {
        guard let selectedMuscle else { return records }
        return records.filter { $0.muscleGroup == selectedMuscle }
    }

    /// The standout PR within the current filter (highest est-1RM — records are
    /// pre-sorted, so it's the first).
    var hero: Item? { filtered.first }

    var gridRecords: [Item] {
        guard let hero else { return [] }
        return filtered.filter { $0.id != hero.id }
    }

    var trackedCount: Int { records.count }
    var freshThisMonthCount: Int { records.filter(\.isFresh).count }
}
