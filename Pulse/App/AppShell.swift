import SwiftUI

struct AppShell: View {
    /// Today is the default/first tab. Its model is built once and wired to the
    /// (mock) repo + stub callbacks — Start → is BAK-14, Session Detail push is
    /// owned by TodayView. Launch arguments select a mock variant for UI tests.
    @State private var todayModel: TodayModel = {
        let repo: MockTodayRepository
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestRestDay") { repo = .restDay }
        else if args.contains("-uiTestError") { repo = .failing }
        else { repo = .sample }
        return TodayModel(
            repository: repo,
            onStartWorkout: { _ in /* BAK-14 active flow hook */ },
            onOpenSession: { _ in /* handled by TodayView path push */ })
    }()

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTestGallery") {
                DesignSystemGallery()
            } else {
                tabs
            }
            #else
            tabs
            #endif
        }
    }

    private var tabs: some View {
        TabView {
            TodayView(model: todayModel)
                .tabItem { Label("Today", systemImage: "bolt.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            YouView()
                .tabItem { Label("You", systemImage: "person.fill") }
        }
    }
}

#Preview { AppShell().environment(Theme()) }
