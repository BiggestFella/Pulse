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
    /// Always a `BufferedSessionWriter` so a finished workout survives flaky
    /// connectivity (BAK-32) — it buffers to `pendingStore` and flushes on reconnect.
    let sessionWriter: any SessionWriter
    /// Durable buffer of finished-but-unsynced sessions; drives the Today tab's
    /// "pending sync" indicator (BAK-32).
    let pendingStore: PendingSessionStore
    private let bufferedWriter: BufferedSessionWriter

    /// Non-nil only on the Supabase path; `bootstrap()` signs in the dev user.
    private let authGateway: AuthGateway?

    init(useMock: Bool) {
        // Folders have no Supabase model yet, so both paths use the in-memory
        // capture repo (see FolderRepository) until the folder data model lands.
        folders = InMemoryFolderRepository()

        // BAK-32: the active flow always writes through a BufferedSessionWriter so
        // a finished session is buffered on-device before the remote attempt and
        // flushed when connectivity returns. Under `-uiMock` the buffer points at a
        // throwaway temp dir so UI tests start with an empty pending list.
        let monitor = ConnectivityMonitor()
        let store: PendingSessionStore
        if useMock {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("pending-sessions-uitest-\(UUID().uuidString)")
            store = PendingSessionStore(directory: dir)
        } else {
            store = PendingSessionStore()
        }
        pendingStore = store

        let baseWriter: any SessionWriter
        if useMock {
            let mockStore = MockStore()
            programs = InMemoryProgramRepository(store: mockStore)
            workouts = InMemoryWorkoutRepository(store: mockStore)
            exercises = InMemoryExerciseRepository(store: mockStore)
            sessions = InMemorySessionRepository(store: mockStore)
            schedule = InMemoryScheduleRepository(store: mockStore)
            stats = InMemoryStatsRepository(store: mockStore)
            prs = InMemoryPRRepository(store: mockStore)
            user = InMemoryUserRepository()
            settings = InMemorySettingsRepository()
            // `-uiTestSaveFail` makes the first save throw so the summary's
            // save-failure + retry path (BAK-31) is exercisable from a UI test.
            // `-uiTestOffline` makes every save throw a connectivity error so the
            // offline buffer + pending-sync path (BAK-32) is exercisable.
            let writer = MockSessionWriter()
            if CommandLine.arguments.contains("-uiTestSaveFail") {
                writer.failOnce = NSError(domain: "Pulse.UITest", code: -1)
            }
            if CommandLine.arguments.contains("-uiTestOffline") {
                writer.failAlways = URLError(.notConnectedToInternet)
            }
            baseWriter = writer
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
            baseWriter = SupabaseSessionWriter(client: client)
        }

        let buffered = BufferedSessionWriter(wrapping: baseWriter, store: store, monitor: monitor)
        bufferedWriter = buffered
        sessionWriter = buffered
    }

    /// Signs in the dev user on the Supabase path (no-op on mock). Call once at launch.
    func bootstrap() async {
        guard let authGateway else { return }
        do { _ = try await authGateway.ensureSignedIn() }
        catch { print("[Supabase] dev sign-in failed: \(error)") }
    }

    /// Drains the offline buffer best-effort (BAK-32). Call on launch and on
    /// foreground; the connectivity monitor also triggers it on reconnect.
    func flushPending() async { await bufferedWriter.flushPending() }

    /// `-uiMock` launch argument (or DEBUG default) selects the mock path.
    static func useMock(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains("-uiMock")
    }
}
