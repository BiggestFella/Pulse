import SwiftUI

@main
struct PulseApp: App {
    @State private var theme = Theme()

    // The data-layer composition root. Defaults to the real Supabase backend; the
    // `-uiMock` launch argument forces the in-memory mock (used by tests/previews).
    @State private var container = RepositoryContainer(useMock: RepositoryContainer.useMock())

    var body: some Scene {
        WindowGroup {
            AppShell(container: container)
                .environment(theme)
                .environment(container)
        }
    }
}
