import AppIntents

/// Abstraction over the live session engine so the intent is testable and the
/// Live Activity never owns state. The controller registers itself here while a
/// session is live.
@MainActor
protocol SkipRestTarget: AnyObject {
    func afterRest()
}

/// Fired by the "Skip rest" button on the Live Activity. Routes into the same
/// advance-without-logging transition as the in-app button.
struct SkipRestIntent: AppIntent {
    static var title: LocalizedStringResource = "Skip Rest"
    /// Stay in-app context; do not bring the app foreground for this action.
    static var openAppWhenRun: Bool = false

    /// Set by the active controller while a session is live; nil otherwise.
    @MainActor static weak var target: SkipRestTarget?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.target?.afterRest()
        return .result()
    }
}
