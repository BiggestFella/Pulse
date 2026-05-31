import SwiftUI

@main
struct PulseApp: App {
    @State private var theme = Theme()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(theme)
        }
    }
}
