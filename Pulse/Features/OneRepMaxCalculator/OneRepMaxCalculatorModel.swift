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

    /// One row of the %-of-1RM working-weight table.
    struct PercentRow: Identifiable, Equatable {
        var percent: Int        // e.g. 90, 85 …
        var weight: Double      // working weight, kg, rounded to nearest 2.5
        var id: Int { percent }
    }

    /// Common training intensities surfaced in the table (high → low).
    static let percents: [Int] = [90, 85, 80, 75, 70]

    init(weight: Double = 60, reps: Int = 5) {
        self.weight = max(0, weight)
        self.reps = max(1, reps)
    }

    /// Estimated one-rep max for the current inputs (Epley, via the shared helper).
    var estimatedOneRepMax: Double { epley1RM(weight: weight, reps: reps) }

    /// The %-of-1RM table for the current estimate, rounded to the nearest 2.5 kg.
    var percentRows: [PercentRow] {
        let oneRM = estimatedOneRepMax
        return Self.percents.map { p in
            PercentRow(percent: p, weight: Self.workingWeight(forPercent: p, of: oneRM))
        }
    }

    /// `percent`% of `oneRM`, rounded to the nearest 2.5 kg (a real plate jump).
    static func workingWeight(forPercent percent: Int, of oneRM: Double) -> Double {
        rounded(toNearest: 2.5, oneRM * Double(percent) / 100)
    }

    /// Round `value` to the nearest multiple of `step` (ties round up). `step`
    /// must be > 0; returns `value` unchanged otherwise.
    static func rounded(toNearest step: Double, _ value: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    func incrementWeight() { weight += Self.weightStep }
    func decrementWeight() { weight = max(0, weight - Self.weightStep) }
    func incrementReps() { reps += 1 }
    func decrementReps() { reps = max(1, reps - 1) }
}
