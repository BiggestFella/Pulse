import Foundation

/// In-memory mock for `SettingsRepository`: holds a mutable copy so a save → load
/// round-trips within a running instance. `shouldFailLoad` / `shouldFailSave`
/// drive the model's failure-path tests.
final class InMemorySettingsRepository: SettingsRepository {
    private let shouldFailLoad: Bool
    private let shouldFailSave: Bool
    private var stored: UserSettings

    init(shouldFailLoad: Bool = false, shouldFailSave: Bool = false,
         initial: UserSettings = .default) {
        self.shouldFailLoad = shouldFailLoad
        self.shouldFailSave = shouldFailSave
        self.stored = initial
    }

    func load() async throws -> UserSettings {
        if shouldFailLoad { throw RepositoryError.forced }
        return stored
    }

    func save(_ settings: UserSettings) async throws {
        if shouldFailSave { throw RepositoryError.forced }
        stored = settings
    }
}
