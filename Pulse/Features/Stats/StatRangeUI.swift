import Foundation

/// UI affordances for the merged `StatRange` (BAK-6 owns the enum). Stats reuses
/// it rather than defining a parallel range type.
extension StatRange {
    /// Chip / eyebrow token: "7D", "30D", "3M", "YR", "ALL".
    var chipLabel: String {
        switch self {
        case .d7:   return "7D"
        case .d30:  return "30D"
        case .m3:   return "3M"
        case .year: return "YR"
        case .all:  return "ALL"
        }
    }
    var eyebrowToken: String { chipLabel }

    static let defaultRange: StatRange = .d30
    /// Display order for the chip row.
    static let displayOrder: [StatRange] = [.d7, .d30, .m3, .year, .all]
}
