import Foundation
import Supabase

/// Live repository stubs. Each holds the shared `SupabaseClient`; method bodies
/// are filled in per repo (and split into their own files) as they're
/// implemented. Unimplemented methods still throw `.notImplemented` so the live
/// composition path type-checks.

struct SupabaseProgramRepository: ProgramRepository {
    let client: SupabaseClient
    func fetchPrograms() async throws -> [Program] { throw RepositoryError.notImplemented }
    func fetchProgram(id: Program.ID) async throws -> Program? { throw RepositoryError.notImplemented }
    func activeProgram() async throws -> Program? { throw RepositoryError.notImplemented }
    func saveProgram(_ program: Program) async throws -> Program { throw RepositoryError.notImplemented }
    func deleteProgram(id: Program.ID) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseWorkoutRepository: WorkoutRepository {
    let client: SupabaseClient
    func fetchWorkouts() async throws -> [Workout] { throw RepositoryError.notImplemented }
    func fetchWorkout(id: Workout.ID) async throws -> Workout? { throw RepositoryError.notImplemented }
    func todaysWorkout(on date: Date) async throws -> Workout? { throw RepositoryError.notImplemented }
    func saveWorkout(_ workout: Workout) async throws -> Workout { throw RepositoryError.notImplemented }
    func deleteWorkout(id: Workout.ID) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseSessionRepository: SessionRepository {
    let client: SupabaseClient
    func startSession(workoutID: Workout.ID, at: Date) async throws -> WorkoutSession { throw RepositoryError.notImplemented }
    func appendSet(_ set: SessionSet, to sessionID: WorkoutSession.ID) async throws { throw RepositoryError.notImplemented }
    func finishSession(id: WorkoutSession.ID, endedAt: Date) async throws -> WorkoutSession { throw RepositoryError.notImplemented }
    func fetchSessions(limit: Int?) async throws -> [WorkoutSession] { throw RepositoryError.notImplemented }
    func fetchSession(id: WorkoutSession.ID) async throws -> WorkoutSession? { throw RepositoryError.notImplemented }
    func lastSessions(forExercise: Exercise.ID, limit: Int) async throws -> [WorkoutSession] { throw RepositoryError.notImplemented }
    func deleteSession(id: WorkoutSession.ID) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseScheduleRepository: ScheduleRepository {
    let client: SupabaseClient
    func plan(for date: Date) async throws -> DayPlan? { throw RepositoryError.notImplemented }
    func upcoming(from date: Date, days: Int) async throws -> [(date: Date, plan: DayPlan)] { throw RepositoryError.notImplemented }
    func setPlan(_ plan: DayPlan?, on date: Date) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseStatsRepository: StatsRepository {
    let client: SupabaseClient
    func volumeSeries(range: StatRange) async throws -> [VolumePoint] { throw RepositoryError.notImplemented }
    func summary(range: StatRange) async throws -> StatsSummary { throw RepositoryError.notImplemented }
    func volumeByMuscle(range: StatRange) async throws -> [MuscleVolume] { throw RepositoryError.notImplemented }
    func currentStreak() async throws -> Int { throw RepositoryError.notImplemented }
    func exerciseVolumeHistory(_ exerciseID: Exercise.ID, lastN: Int) async throws -> [VolumePoint] { throw RepositoryError.notImplemented }
}

struct SupabasePRRepository: PRRepository {
    let client: SupabaseClient
    func allPRs() async throws -> [PersonalRecord] { throw RepositoryError.notImplemented }
    func prs(muscleGroup: String) async throws -> [PersonalRecord] { throw RepositoryError.notImplemented }
    func personalBest(forExercise: Exercise.ID) async throws -> PersonalRecord? { throw RepositoryError.notImplemented }
    func newPRs(in range: StatRange) async throws -> [PersonalRecord] { throw RepositoryError.notImplemented }
}

struct SupabaseUserRepository: UserRepository {
    let client: SupabaseClient
    func currentProfile() async throws -> UserProfile { throw RepositoryError.notImplemented }
    func profileSummary() async throws -> ProfileStats { throw RepositoryError.notImplemented }
}

struct SupabaseSettingsRepository: SettingsRepository {
    let client: SupabaseClient
    func load() async throws -> UserSettings { throw RepositoryError.notImplemented }
    func save(_ settings: UserSettings) async throws { throw RepositoryError.notImplemented }
}
