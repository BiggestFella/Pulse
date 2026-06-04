import Foundation
import Supabase

/// Signs in the stubbed dev user once at launch so RLS sees `auth.uid()`.
/// Real onboarding (BAK-8) replaces this later.
actor AuthGateway {
    private let client: SupabaseClient
    private let config: AppConfig

    init(client: SupabaseClient, config: AppConfig) {
        self.client = client
        self.config = config
    }

    /// Idempotent: signs in only if there's no current session.
    @discardableResult
    func ensureSignedIn() async throws -> UUID {
        if let session = try? await client.auth.session {
            return session.user.id
        }
        let session = try await client.auth.signIn(email: config.devEmail, password: config.devPassword)
        return session.user.id
    }
}
