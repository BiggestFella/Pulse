import Foundation

/// Shared mutable backing store for all in-memory repositories. `@MainActor`
/// so concurrent session reads/writes during a workout are isolation-safe.
/// Seeded from `SampleData`; supports forced-error and injected-latency modes
/// for testing loading/empty/error states.
@MainActor
final class MockStore {
    var programs: [Program]
    var exercises: [Exercise]
    var sessions: [WorkoutSession]
    var schedule: [Date: DayPlan]
    /// Library folders (in-memory). Membership of workouts/programs in a folder is
    /// tracked by id-maps rather than on the domain models (which don't carry folder_id).
    var folders: [Folder] = []
    var workoutFolderID: [Workout.ID: Folder.ID] = [:]
    var programFolderID: [Program.ID: Folder.ID] = [:]

    /// When true, every repository method throws `RepositoryError.forced`.
    var forceError = false
    /// Artificial latency applied before each method returns (loading state).
    var latency: Duration = .zero

    init(seeded: Bool = true) {
        if seeded {
            programs = [SampleData.program]
            exercises = SampleData.exercises
            sessions = SampleData.sessions
            schedule = SampleData.schedule
            folders = SampleData.folders
            programFolderID = SampleData.programFolderID
        } else {
            programs = []; exercises = []; sessions = []; schedule = [:]
        }
    }

    /// Call at the top of every repository method.
    func gate() async throws {
        if latency > .zero { try? await Task.sleep(for: latency) }
        if forceError { throw RepositoryError.forced }
    }

    /// All workouts across all programs (workouts live under programs).
    var allWorkouts: [Workout] { programs.flatMap(\.workouts) }
}
