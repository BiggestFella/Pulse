import Foundation
import Supabase

/// Training preferences, stored one row per user in `user_settings` (RLS-scoped).
/// A missing row falls back to `UserSettings.default`; `save` upserts on user_id.
struct SupabaseSettingsRepository: SettingsRepository {
    let client: SupabaseClient

    private struct SettingsRow: Decodable {
        let units: String
        let defaultRestSeconds: Int
        let autoProgressWeight: Bool
        let soundOnRestEnd: Bool
        func toModel() -> UserSettings {
            UserSettings(units: Units(rawValue: units) ?? .kg,
                         defaultRestSeconds: defaultRestSeconds,
                         autoProgressWeight: autoProgressWeight,
                         soundOnRestEnd: soundOnRestEnd)
        }
    }

    private struct SettingsWriteRow: Encodable {
        let userId: UUID
        let units: String
        let defaultRestSeconds: Int
        let autoProgressWeight: Bool
        let soundOnRestEnd: Bool
    }

    func load() async throws -> UserSettings {
        let rows: [SettingsRow] = try await client
            .from("user_settings").select("*").limit(1).execute().value
        return rows.first?.toModel() ?? .default
    }

    func save(_ settings: UserSettings) async throws {
        let userID = try await client.auth.session.user.id
        try await client.from("user_settings").upsert(SettingsWriteRow(
            userId: userID,
            units: settings.units.rawValue,
            defaultRestSeconds: settings.defaultRestSeconds,
            autoProgressWeight: settings.autoProgressWeight,
            soundOnRestEnd: settings.soundOnRestEnd), onConflict: "user_id").execute()
    }
}
