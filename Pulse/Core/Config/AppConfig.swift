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

    /// Direct init (used for the placeholder fallback).
    init(supabaseURL: URL, anonKey: String, devEmail: String, devPassword: String) {
        self.supabaseURL = supabaseURL
        self.anonKey = anonKey
        self.devEmail = devEmail
        self.devPassword = devPassword
    }

    /// Reads from the main bundle's Info.plist at runtime.
    static func fromBundle(_ bundle: Bundle = .main) throws -> AppConfig {
        try AppConfig(info: bundle.infoDictionary ?? [:])
    }

    /// Fallback so the live container can construct even when Secrets.xcconfig
    /// isn't present (unit tests / CI). Repository calls fail until real config is
    /// supplied; the running app reads real values from Info.plist.
    static let placeholder = AppConfig(
        supabaseURL: URL(string: "https://placeholder.supabase.co")!,
        anonKey: "placeholder", devEmail: "placeholder@pulse.app", devPassword: "placeholder")
}
