import Foundation

/// Runtime configuration read from the app bundle's Info.plist (populated from
/// `Secrets.xcconfig` via INFOPLIST_KEY_* build settings). Pure init for testing.
struct AppConfig {
    let supabaseURL: URL
    let anonKey: String
    let devEmail: String
    let devPassword: String

    enum ConfigError: Error { case missing(String), badURL(String) }

    init(info: [String: Any]) throws {
        func str(_ k: String) throws -> String {
            guard let v = info[k] as? String, !v.isEmpty else { throw ConfigError.missing(k) }
            return v
        }
        let urlString = try str("SUPABASE_URL")
        guard let url = URL(string: urlString) else { throw ConfigError.badURL(urlString) }
        self.supabaseURL = url
        self.anonKey = try str("SUPABASE_ANON_KEY")
        self.devEmail = try str("DEV_USER_EMAIL")
        self.devPassword = try str("DEV_USER_PASSWORD")
    }

    /// Reads from the main bundle's Info.plist at runtime.
    static func fromBundle(_ bundle: Bundle = .main) throws -> AppConfig {
        try AppConfig(info: bundle.infoDictionary ?? [:])
    }
}
