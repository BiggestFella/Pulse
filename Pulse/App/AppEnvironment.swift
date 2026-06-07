import SwiftUI
import Supabase

/// The composition root. Bundles one instance of each repository and selects
/// mock vs live at construction. Injected into the SwiftUI environment at the
/// app root so any model resolves its repositories from the environment rather
/// than constructing them. Mock repos share a single `MockStore` so writes are
/// visible across repositories within the running instance.
@MainActor
@Observable
final class RepositoryContainer {
    let programs: any ProgramRepository
    let workouts: any WorkoutRepository
    let exercises: any ExerciseRepository
    let sessions: any SessionRepository
    let schedule: any ScheduleRepository
    let stats: any StatsRepository
    let prs: any PRRepository
    let user: any UserRepository
    let settings: any SettingsRepository
    let folders: any FolderRepository
    /// Persists finished active-workout sessions (the active flow writes here).
    let sessionWriter: any SessionWriter

    /// Non-nil only on the Supabase path; `bootstrap()` signs in the dev user.
    private let authGateway: AuthGateway?

    init(useMock: Bool) {
        // Folders have no Supabase model yet, so both paths use the in-memory
        // capture repo (see FolderRepository) until the folder data model lands.
        folders = InMemoryFolderRepository()
        if useMock {
            let store = MockStore()
            programs = InMemoryProgramRepository(store: store)
            workouts = InMemoryWorkoutRepository(store: store)
            exercises = InMemoryExerciseRepository(store: store)
            sessions = InMemorySessionRepository(store: store)
            schedule = InMemoryScheduleRepository(store: store)
            stats = InMemoryStatsRepository(store: store)
            prs = InMemoryPRRepository(store: store)
            user = InMemoryUserRepository()
            settings = InMemorySettingsRepository()
            // `-uiTestSaveFail` makes the first save throw so the summary's
            // save-failure + retry path (BAK-31) is exercisable from a UI test.
            let writer = MockSessionWriter()
            if CommandLine.arguments.contains("-uiTestSaveFail") {
                writer.failOnce = NSError(domain: "Pulse.UITest", code: -1)
            }
            sessionWriter = writer
            authGateway = nil
        } else {
            let config: AppConfig
            if let loaded = try? AppConfig.fromBundle() {
                config = loaded
            } else {
                print("[Supabase] WARNING: config missing from Info.plist/Secrets.xcconfig — using placeholder; data calls will fail until real config is provided.")
                config = .placeholder
            }
            let client = SupabaseClientProvider.make(config)
            authGateway = AuthGateway(client: client, config: config)
            programs = SupabaseProgramRepository(client: client)
            workouts = SupabaseWorkoutRepository(client: client)
            exercises = SupabaseExerciseRepository(client: client)
            sessions = SupabaseSessionRepository(client: client)
            schedule = SupabaseScheduleRepository(client: client)
            stats = SupabaseStatsRepository(client: client)
            prs = SupabasePRRepository(client: client)
            user = SupabaseUserRepository(client: client)
            settings = SupabaseSettingsRepository(client: client)
            sessionWriter = SupabaseSessionWriter(client: client)
        }
    }

    /// Signs in the dev user on the Supabase path (no-op on mock). Call once at launch.
    func bootstrap() async {
        guard let authGateway else { return }
        do { _ = try await authGateway.ensureSignedIn() }
        catch { print("[Supabase] dev sign-in failed: \(error)") }
    }

    /// `-uiMock` launch argument (or DEBUG default) selects the mock path.
    static func useMock(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains("-uiMock")
    }
}
