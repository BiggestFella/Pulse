import Foundation

/// Weight unit system. v1 is kg-only (product decision); a real toggle + conversion
/// is a later feature. Keeping the label here localizes that future change.
enum Units: String, Codable, CaseIterable {
    case kg

    var displayLabel: String {
        switch self {
        case .kg: return "KG · METRIC"
        }
    }
}

/// Lifter identity shown in the You header.
struct UserProfile: Codable, Equatable {
    var displayName: String
    var memberSince: Date
    var programLabel: String

    /// Single uppercase initial for the avatar; falls back to "?" when name is empty.
    var avatarInitial: String {
        guard let first = displayName.trimmingCharacters(in: .whitespaces).first else {
            return "?"
        }
        return String(first).uppercased()
    }

    /// "Member since Feb 2024 · PPL". Fixed locale so it reads identically
    /// regardless of device language.
    var subtitle: String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "LLL yyyy"
        return "Member since \(f.string(from: memberSince)) · \(programLabel)"
    }
}

/// Aggregate headline numbers for the MiniStat strip + NavRow sub-counts.
struct ProfileStats: Codable, Equatable {
    var streakDays: Int
    var totalSessions: Int
    var totalVolumeKg: Double
    var liftsTracked: Int
    var sessionsLogged: Int

    static let empty = ProfileStats(streakDays: 0, totalSessions: 0,
                                    totalVolumeKg: 0, liftsTracked: 0, sessionsLogged: 0)
}

/// Editable training preferences. Persisted via `SettingsRepository`.
struct UserSettings: Codable, Equatable {
    var units: Units
    var defaultRestSeconds: Int
    var autoProgressWeight: Bool
    var soundOnRestEnd: Bool

    static let `default` = UserSettings(units: .kg, defaultRestSeconds: 90,
                                        autoProgressWeight: true, soundOnRestEnd: true)

    /// "90s" — display value for the Default rest timer row.
    var restTimerLabel: String { "\(defaultRestSeconds)s" }
}
