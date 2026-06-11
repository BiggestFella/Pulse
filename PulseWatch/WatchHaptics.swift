import Foundation
import WatchKit

/// Seam over `WKInterfaceDevice.play` so haptic intent is expressible without a
/// physical device. Two cues, matching the Rest Timer Audio semantics: a lighter
/// warning at T-10s and a success notification at rest end.
protocol WatchHapticsPlaying {
    func playWarning()   // T-10s
    func playRestEnd()   // 0
}

struct WatchHaptics: WatchHapticsPlaying {
    func playWarning() { WKInterfaceDevice.current().play(.directionUp) }
    func playRestEnd() { WKInterfaceDevice.current().play(.success) }
}
