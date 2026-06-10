import Foundation

/// Plays the rest-timer audio + haptic cues. Injected into `ActiveWorkoutModel`
/// so cue firing is testable with a mock and the model never touches AVFoundation.
/// Mock-friendly per repo convention (protocol + real impl + mock).
protocol RestCuePlaying {
    /// Configure the audio session and preload players. Called when rest starts.
    func prepare()
    /// T-10s "get ready" cue: soft tick + light impact haptic.
    func warn()
    /// Rest-over cue: double chime + success notification haptic.
    func end()
    /// Deactivate the audio session when leaving the rest screen.
    func teardown()
}

/// Default no-op used by SwiftUI previews and any call site that doesn't supply
/// a real service. Keeps `ActiveWorkoutModel.init` ergonomic without pulling
/// AVFoundation into preview rendering.
struct NoopRestCueService: RestCuePlaying {
    func prepare() {}
    func warn() {}
    func end() {}
    func teardown() {}
}
