import SwiftUI

@main
struct PulseWatchApp: App {
    @State private var model = WatchSessionModel(channel: WCSessionWatchSyncChannel())

    var body: some Scene {
        WindowGroup { WatchRootView(model: model) }
    }
}
