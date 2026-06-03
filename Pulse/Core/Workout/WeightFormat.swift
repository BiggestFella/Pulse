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

    /// Bare kg number with no unit — for hero/Oswald numerals. Trims ".0".
    static func kgNumeral(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(weight)) : String(weight)
    }

    /// "100 kg" for positive weight, "bodyweight" for zero/negative.
    static func weightOrBodyweight(_ weight: Double) -> String {
        weight > 0 ? kg(weight) : "bodyweight"
    }

    /// Total volume abbreviated to thousands ("3.6k"); whole numbers under 1000
    /// render rounded ("840"); "—" when zero/negative.
    static func volume(_ value: Double) -> String {
        guard value > 0 else { return "—" }
        if value < 1000 { return String(Int(value.rounded())) }
        return String(format: "%.1fk", value / 1000)
    }
}
