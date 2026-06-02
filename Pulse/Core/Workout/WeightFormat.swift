import Foundation

/// Single source of truth for weight display (kg-only in v1; a units toggle is later).
enum WeightFormat {
    /// "60 kg" / "62.5 kg" — trims a trailing ".0".
    static func kg(_ weight: Double) -> String {
        let trimmed = weight.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(weight))
            : String(weight)
        return "\(trimmed) kg"
    }

    /// Footer eyebrow: "60 KG · 10 REPS".
    static func eyebrow(weight: Double, reps: Int) -> String {
        let w = weight.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(weight)) : String(weight)
        return "\(w) KG · \(reps) REPS"
    }
}
