import Foundation

/// Errors any repository may throw. `notImplemented` is the Supabase-stub
/// placeholder; `forced` is what the mock throws in forced-error mode.
enum RepositoryError: Error, Equatable {
    case notImplemented
    case notFound
    case forced
}
