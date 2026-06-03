import Foundation
import Observation

/// One logged session reduced to what Exercise Detail displays. Derived in the
/// model from `WorkoutSession`/`SessionSet` via `WorkoutAnalytics` so the view
/// stays declarative. `date` is the session start; the view formats the label.
struct ExerciseSessionSummary: Equatable, Identifiable {
    var id = UUID()
    var date: Date
    var repLine: String       // e.g. "12 · 10 · 8" (counting sets only)
    var topWeight: Double     // heaviest counting set, kg (0 = bodyweight)
    var volume: Double        // total counting-set volume (kg · reps)
}

/// All-time personal best top set for the exercise (nil when bodyweight / none).
/// Derived from `PRRepository` (est-1RM via Epley) — not stored.
struct ExerciseDetailPB: Equatable {
    var topWeight: Double
    var date: Date
}

/// A selectable variation pill ("All" + named variations).
struct VariationOption: Equatable, Identifiable {
    var id = UUID()
    var label: String
    var variationID: Variation.ID?   // nil for the "All" pill
}

enum ExerciseDetailPhase: Equatable {
    case loading, loaded, empty
    case error(String)
}

/// Read-only Exercise Detail screen model. Composes the merged BAK-6
/// repositories: `ExerciseRepository` (catalog), `SessionRepository`
/// (per-exercise history → summaries), and `PRRepository` (derived PB). All
/// weight math goes through `WorkoutAnalytics`; weight strings through
/// `WeightFormat`. Variation pills are cosmetic in v1 (product decision Open Q1).
@MainActor
@Observable
final class ExerciseDetailModel {
    let exerciseID: Exercise.ID
    private let exerciseRepo: any ExerciseRepository
    private let sessionRepo: any SessionRepository
    private let prRepo: any PRRepository
    private let window = 4

    var phase: ExerciseDetailPhase = .loading
    var exercise: Exercise?
    var personalBest: ExerciseDetailPB?
    var sessions: [ExerciseSessionSummary] = []
    var variations: [VariationOption] = [VariationOption(label: "All", variationID: nil)]
    var selectedVariationIndex = 0

    init(exerciseID: Exercise.ID,
         exerciseRepo: any ExerciseRepository,
         sessionRepo: any SessionRepository,
         prRepo: any PRRepository) {
        self.exerciseID = exerciseID
        self.exerciseRepo = exerciseRepo
        self.sessionRepo = sessionRepo
        self.prRepo = prRepo
    }

    // MARK: - Derived

    var showsVariationPills: Bool { variations.count > 1 }
    var showsPersonalBest: Bool { personalBest != nil }

    /// Chart scaling denominator — never zero (avoids div-by-zero / invisible bars).
    var maxVolume: Double { max(1, sessions.map(\.volume).max() ?? 0) }

    /// "<MUSCLE GROUP> · <EQUIPMENT>" eyebrow, uppercase. Equipment is resolved
    /// from the variation set (the merged `Exercise` carries equipment on its
    /// `Variation`s), falling back to "—" when unknown.
    var eyebrowText: String {
        guard let ex = exercise else { return "" }
        return "\(ex.muscleGroup.uppercased()) · \(equipmentLabel(ex))"
    }

    private func equipmentLabel(_ ex: Exercise) -> String {
        // Prefer an explicit equipment tag on the default/first variation; else
        // use the first variation's name (the mock catalog encodes equipment as
        // the variation name, e.g. "Barbell"); else a neutral dash.
        if let v = ex.variations.first {
            return (v.equipment ?? v.name).uppercased()
        }
        return "—"
    }

    // MARK: - Load

    func load() async {
        phase = .loading
        do {
            guard let ex = try await exerciseRepo.fetchExercise(id: exerciseID) else {
                clear()
                phase = .error("Couldn’t find this exercise.")
                return
            }
            self.exercise = ex
            self.variations = [VariationOption(label: "All", variationID: nil)]
                + ex.variations.map { VariationOption(label: $0.name, variationID: $0.id) }
            self.selectedVariationIndex = ex.variations.isEmpty ? 0 : 1

            let logged = try await sessionRepo.lastSessions(forExercise: exerciseID, limit: window)
            self.sessions = logged.map { summarize($0) }
            self.personalBest = try await derivePB()

            phase = sessions.isEmpty ? .empty : .loaded
        } catch {
            clear()
            phase = .error("Couldn’t load this exercise. Pull to retry.")
        }
    }

    func retry() async { await load() }

    /// v1: cosmetic — updates the selection without re-querying history.
    func selectVariation(_ index: Int) {
        guard variations.indices.contains(index) else { return }
        selectedVariationIndex = index
    }

    // MARK: - Derivation helpers

    private func clear() {
        sessions = []
        personalBest = nil
    }

    /// Reduce a session's sets for this exercise into a display summary.
    private func summarize(_ session: WorkoutSession) -> ExerciseSessionSummary {
        let sets = session.sets.filter { $0.exerciseID == exerciseID }
        let counting = sets.filter { WorkoutAnalytics.counts($0.type) }
        let repLine = counting.map { String($0.reps) }.joined(separator: " · ")
        let topWeight = WorkoutAnalytics.topWorkingWeight(in: sets) ?? 0
        let volume = WorkoutAnalytics.volume(of: sets)
        return ExerciseSessionSummary(date: session.startedAt, repLine: repLine,
                                      topWeight: topWeight, volume: volume)
    }

    /// PB = the all-time best set (est-1RM) for this exercise from `PRRepository`.
    /// nil when bodyweight (weight 0) or no record.
    private func derivePB() async throws -> ExerciseDetailPB? {
        guard let record = try await prRepo.personalBest(forExercise: exerciseID),
              record.weight > 0 else { return nil }
        return ExerciseDetailPB(topWeight: record.weight, date: record.achievedAt)
    }
}
