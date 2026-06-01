import SwiftUI

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

    init(useMock: Bool) {
        if useMock {
            let store = MockStore()
            programs = InMemoryProgramRepository(store: store)
            workouts = InMemoryWorkoutRepository(store: store)
            exercises = InMemoryExerciseRepository(store: store)
            sessions = InMemorySessionRepository(store: store)
            schedule = InMemoryScheduleRepository(store: store)
            stats = InMemoryStatsRepository(store: store)
            prs = InMemoryPRRepository(store: store)
        } else {
            programs = SupabaseProgramRepository()
            workouts = SupabaseWorkoutRepository()
            exercises = SupabaseExerciseRepository()
            sessions = SupabaseSessionRepository()
            schedule = SupabaseScheduleRepository()
            stats = SupabaseStatsRepository()
            prs = SupabasePRRepository()
        }
    }

    /// `-uiMock` launch argument (or DEBUG default) selects the mock path.
    static func useMock(arguments: [String] = CommandLine.arguments) -> Bool {
        arguments.contains("-uiMock")
    }
}
