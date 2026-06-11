import Foundation

/// Inputs to the (pure) progression rule. No I/O — `lastSets` is the caller's
/// already-fetched history slice for one exercise's most recent session.
struct ProgressionInput {
    let target: SetSpec            // planned reps/type for this set
    let lastSets: [SessionSet]     // same exercise, most recent session (may be empty)
    let increment: Double          // kg step for this movement (default 2.5)
    let autoProgress: Bool
}

/// A suggested load to pre-seed the steppers, with a short human rationale.
struct ProgressionSuggestion: Equatable {
    let weight: Double
    let reps: Int
    let rationale: String
}

/// Double-progression rule (v1, reps-completion based — no RPE/RIR):
/// - No history → `nil` (caller seeds from `SetSpec`/planned weight as today).
/// - `autoProgress == false` → repeat last weight × last reps ("Repeat last session").
/// - Last set met/beat target reps → +1 increment at target reps
///   ("Hit all reps last time → +<inc> kg").
/// - Last set missed target reps → same weight at target reps
///   ("Missed target last time → hold weight").
func suggestProgression(_ input: ProgressionInput) -> ProgressionSuggestion? {
    guard let last = input.lastSets.first else { return nil }

    if !input.autoProgress {
        return ProgressionSuggestion(weight: last.weight, reps: last.reps,
                                     rationale: "Repeat last session")
    }

    if last.reps >= input.target.reps {
        let bumped = last.weight + input.increment
        let incLabel = WeightFormat.kgNumeral(input.increment)
        return ProgressionSuggestion(weight: bumped, reps: input.target.reps,
                                     rationale: "Hit all reps last time → +\(incLabel) kg")
    }

    return ProgressionSuggestion(weight: last.weight, reps: input.target.reps,
                                 rationale: "Missed target last time → hold weight")
}
