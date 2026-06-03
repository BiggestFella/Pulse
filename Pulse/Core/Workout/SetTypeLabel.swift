import Foundation

/// Single source of truth for set-type display labels and chip styling, shared
/// by the in-app active hero and the Live Activity. Covers all five SetType
/// cases — the in-app hero map omits `dropset`, so this defines it explicitly.
enum SetTypeLabel {
  static func text(for type: SetType) -> String {
    switch type {
    case .working: return "WORKING"
    case .warmup:  return "WARMUP"
    case .dropset: return "DROP SET"
    case .failure: return "FAILURE"
    case .amrap:   return "AMRAP"
    }
  }

  /// `working` renders as a filled chip (accent fill, onAccent text);
  /// all others render outlined per the active hero pill rules.
  static func isFilledChip(_ type: SetType) -> Bool {
    type == .working
  }
}
