import SwiftUI

@main
struct PulseApp: App {
    @State private var theme = Theme()

    // The data-layer composition root. DEBUG builds default to mock data; the
    // `-uiMock` argument forces it in any build. Injected alongside the Theme so
    // any screen model can resolve its repositories from the environment.
    @State private var container: RepositoryContainer = {
        #if DEBUG
        return RepositoryContainer(useMock: true)
        #else
        return RepositoryContainer(useMock: RepositoryContainer.useMock())
        #endif
    }()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(theme)
                .environment(container)
        }
    }
}
