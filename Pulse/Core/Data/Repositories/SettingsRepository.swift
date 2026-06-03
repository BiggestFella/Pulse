import Foundation

/// Loads/saves training preferences (units, default rest, toggles). Owned by the
/// data layer (BAK-6). Palette is NOT here — it is persisted by `Theme` via
/// UserDefaults key "pulse-pal".
protocol SettingsRepository {
    func load() async throws -> UserSettings
    func save(_ settings: UserSettings) async throws
}
