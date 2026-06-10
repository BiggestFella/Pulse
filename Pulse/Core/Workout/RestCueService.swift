import Foundation
import AVFoundation
import UIKit

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

/// Real cue player. Mixes short cues over background audio without interrupting
/// it (`.playback` + `[.mixWithOthers, .duckOthers]`) and pairs each with a haptic
/// so the cue still registers when the device is muted or quiet. Marked @MainActor
/// because haptic generators and player setup are UIKit/main-thread friendly.
@MainActor
final class RestCueService: RestCuePlaying {
    private let session = AVAudioSession.sharedInstance()
    private var warnPlayer: AVAudioPlayer?
    private var endPlayer: AVAudioPlayer?
    private let notify = UINotificationFeedbackGenerator()
    private let impact = UIImpactFeedbackGenerator(style: .light)

    init() {
        warnPlayer = Self.makePlayer(named: "rest-warn")
        endPlayer = Self.makePlayer(named: "rest-end")
    }

    private static func makePlayer(named name: String) -> AVAudioPlayer? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "caf") else {
            assertionFailure("Missing bundled audio asset \(name).caf")
            return nil
        }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
    }

    func prepare() {
        // .playback is audible even when the hardware silent switch is on
        // (important in a gym). .mixWithOthers keeps Spotify/podcasts playing;
        // .duckOthers briefly dips that audio so the cue cuts through.
        try? session.setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        try? session.setActive(true)
        warnPlayer?.prepareToPlay()
        endPlayer?.prepareToPlay()
        notify.prepare()
        impact.prepare()
    }

    func warn() {
        impact.impactOccurred()
        warnPlayer?.currentTime = 0
        warnPlayer?.play()
    }

    func end() {
        notify.notificationOccurred(.success)
        endPlayer?.currentTime = 0
        endPlayer?.play()
    }

    func teardown() {
        // Hand the session back so other apps can resume full control.
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
