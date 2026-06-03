import Foundation

enum LoadPhase: Equatable {
    case loading
    case loaded
    case failed(String)
}

/// `@Observable` model for the You tab. Loads profile + stats + settings on
/// appear, exposes a `LoadPhase`, and mutates/persists the two preference toggles.
/// Palette is NOT owned here — the swatch picker writes `Theme` directly. On a
/// repo failure, `load()` enters a non-fatal `.failed` state but keeps `settings`
/// at last-known/default so the screen still renders and the palette picker stays
/// usable. Toggle saves are optimistic; a failed save surfaces `saveError` without
/// reverting (product decision: keep it simple, surface a non-fatal error).
@MainActor
@Observable
final class YouModel {
    private(set) var profile: UserProfile?
    private(set) var stats: ProfileStats?
    private(set) var settings: UserSettings = .default
    private(set) var phase: LoadPhase = .loading
    /// Non-fatal error from a failed preference save (nil when the last save succeeded).
    private(set) var saveError: String?

    private let userRepo: any UserRepository
    private let settingsRepo: any SettingsRepository

    init(userRepo: any UserRepository, settingsRepo: any SettingsRepository) {
        self.userRepo = userRepo
        self.settingsRepo = settingsRepo
    }

    func load() async {
        phase = .loading
        do {
            async let profileTask = userRepo.currentProfile()
            async let statsTask = userRepo.profileSummary()
            async let settingsTask = settingsRepo.load()
            let (p, s, set) = try await (profileTask, statsTask, settingsTask)
            profile = p
            stats = s
            settings = set
            phase = .loaded
        } catch {
            // Non-fatal: keep last-known/default settings; the screen still renders.
            phase = .failed(String(describing: error))
        }
    }

    func setAutoProgress(_ on: Bool) async {
        settings.autoProgressWeight = on
        await persist()
    }

    func setSoundOnRest(_ on: Bool) async {
        settings.soundOnRestEnd = on
        await persist()
    }

    private func persist() async {
        do {
            try await settingsRepo.save(settings)
            saveError = nil
        } catch {
            // Optimistic: keep the new value, surface a non-fatal error.
            saveError = String(describing: error)
        }
    }
}
