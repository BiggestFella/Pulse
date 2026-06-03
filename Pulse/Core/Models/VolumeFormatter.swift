import Foundation

/// Compact display of a kg volume as a numeral + unit suffix ("2.1" + "M").
/// Single source of truth for volume formatting so a later units feature is localized.
enum VolumeFormatter {
    struct Compact: Equatable { let value: String; let unit: String }

    static func compact(_ kg: Double) -> Compact {
        let magnitude = Swift.abs(kg)
        if magnitude >= 1_000_000 { return Compact(value: trim(kg / 1_000_000), unit: "M") }
        if magnitude >= 1_000 { return Compact(value: trim(kg / 1_000), unit: "K") }
        return Compact(value: trim(kg), unit: "")
    }

    /// One decimal, dropping a trailing ".0".
    private static func trim(_ x: Double) -> String {
        let rounded = (x * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}
