import Foundation

/// Placeholder for the live Supabase client. Real wiring (supabase-swift,
/// auth tokens, decoding) lands later behind the same repository protocols.
/// This compiles today so the `-uiMock=false` configuration builds.
enum SupabaseClientProvider {
    static func makeClient() -> Void {
        // Intentionally empty: live client construction deferred to BAK-6 live wiring.
    }
}
