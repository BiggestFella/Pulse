import Foundation
import Observation

/// Read-only 1RM calculator / what-if model. Pure derived state — no
/// persistence, no repositories. The est-1RM reuses the canonical Epley math
/// (`epley1RM`); this type adds NO new formula. kg-only (v1).
@MainActor
@Observable
final class OneRepMaxCalculatorModel {
    /// Weight on the bar, kg. Floored at 0, stepped by 2.5 (matches active flow).
    private(set) var weight: Double
    /// Reps performed. Floored at 1 (est-1RM is the bar weight at 1 rep).
    private(set) var reps: Int

    static let weightStep = 2.5

    init(weight: Double = 60, reps: Int = 5) {
        self.weight = max(0, weight)
        self.reps = max(1, reps)
    }

    /// Estimated one-rep max for the current inputs (Epley, via the shared helper).
    var estimatedOneRepMax: Double { epley1RM(weight: weight, reps: reps) }

    func incrementWeight() { weight += Self.weightStep }
    func decrementWeight() { weight = max(0, weight - Self.weightStep) }
    func incrementReps() { reps += 1 }
    func decrementReps() { reps = max(1, reps - 1) }
}
