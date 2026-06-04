import Foundation
import Supabase

/// Builds the shared Supabase client from `AppConfig`. Create once at launch and
/// share the instance across all repositories.
enum SupabaseClientProvider {
    static func make(_ config: AppConfig) -> SupabaseClient {
        SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.anonKey)
    }
}
