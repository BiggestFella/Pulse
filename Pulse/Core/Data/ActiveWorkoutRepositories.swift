import Foundation

// Repository seam for the active-workout flow. BAK-6 owns the canonical
// `WorkoutRepository`/`ExerciseRepository`/`SessionRepository`; the active flow
// runs a self-contained sample workout (with failure/dropset/amrap sets the
// catalog doesn't carry), so it uses these small flow-local protocols instead of
// colliding with the BAK-6 names.

/// Same-muscle-group alternatives for the Swap sheet.
protocol SwapAlternativesProviding {
    func alternatives(muscleGroup: String) async throws -> [Exercise]
}

/// Recent logged sets for the History sheet.
protocol HistoryRepository {
    func recentSets(exerciseID: Exercise.ID) async throws -> [SessionSet]
}

/// Persists a finished session. Real wiring is BAK-6's `SessionRepository`; this
/// is the stub seam the flow writes to until that integration lands.
protocol SessionWriter {
    func save(_ session: WorkoutSession) async throws
}
