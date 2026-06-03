import Foundation

/// Live repository stubs. Every method throws `.notImplemented` until live
/// wiring lands; they exist so the live composition path type-checks and the
/// app launches when `-uiMock` is false.

struct SupabaseProgramRepository: ProgramRepository {
    func fetchPrograms() async throws -> [Program] { throw RepositoryError.notImplemented }
    func fetchProgram(id: Program.ID) async throws -> Program? { throw RepositoryError.notImplemented }
    func activeProgram() async throws -> Program? { throw RepositoryError.notImplemented }
    func saveProgram(_ program: Program) async throws -> Program { throw RepositoryError.notImplemented }
    func deleteProgram(id: Program.ID) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseWorkoutRepository: WorkoutRepository {
    func fetchWorkouts() async throws -> [Workout] { throw RepositoryError.notImplemented }
    func fetchWorkout(id: Workout.ID) async throws -> Workout? { throw RepositoryError.notImplemented }
    func todaysWorkout(on date: Date) async throws -> Workout? { throw RepositoryError.notImplemented }
    func saveWorkout(_ workout: Workout) async throws -> Workout { throw RepositoryError.notImplemented }
    func deleteWorkout(id: Workout.ID) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseExerciseRepository: ExerciseRepository {
    func fetchCatalog() async throws -> [Exercise] { throw RepositoryError.notImplemented }
    func fetchExercises(muscleGroup: String) async throws -> [Exercise] { throw RepositoryError.notImplemented }
    func fetchExercise(id: Exercise.ID) async throws -> Exercise? { throw RepositoryError.notImplemented }
    func alternatives(for exerciseID: Exercise.ID) async throws -> [Exercise] { throw RepositoryError.notImplemented }
    func saveExercise(_ exercise: Exercise) async throws -> Exercise { throw RepositoryError.notImplemented }
}

struct SupabaseSessionRepository: SessionRepository {
    func startSession(workoutID: Workout.ID, at: Date) async throws -> WorkoutSession { throw RepositoryError.notImplemented }
    func appendSet(_ set: SessionSet, to sessionID: WorkoutSession.ID) async throws { throw RepositoryError.notImplemented }
    func finishSession(id: WorkoutSession.ID, endedAt: Date) async throws -> WorkoutSession { throw RepositoryError.notImplemented }
    func fetchSessions(limit: Int?) async throws -> [WorkoutSession] { throw RepositoryError.notImplemented }
    func fetchSession(id: WorkoutSession.ID) async throws -> WorkoutSession? { throw RepositoryError.notImplemented }
    func lastSessions(forExercise: Exercise.ID, limit: Int) async throws -> [WorkoutSession] { throw RepositoryError.notImplemented }
    func deleteSession(id: WorkoutSession.ID) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseScheduleRepository: ScheduleRepository {
    func plan(for date: Date) async throws -> DayPlan? { throw RepositoryError.notImplemented }
    func upcoming(from date: Date, days: Int) async throws -> [(date: Date, plan: DayPlan)] { throw RepositoryError.notImplemented }
    func setPlan(_ plan: DayPlan?, on date: Date) async throws { throw RepositoryError.notImplemented }
}

struct SupabaseStatsRepository: StatsRepository {
    func volumeSeries(range: StatRange) async throws -> [VolumePoint] { throw RepositoryError.notImplemented }
    func summary(range: StatRange) async throws -> StatsSummary { throw RepositoryError.notImplemented }
    func volumeByMuscle(range: StatRange) async throws -> [MuscleVolume] { throw RepositoryError.notImplemented }
    func currentStreak() async throws -> Int { throw RepositoryError.notImplemented }
    func exerciseVolumeHistory(_ exerciseID: Exercise.ID, lastN: Int) async throws -> [VolumePoint] { throw RepositoryError.notImplemented }
}

struct SupabasePRRepository: PRRepository {
    func allPRs() async throws -> [PersonalRecord] { throw RepositoryError.notImplemented }
    func prs(muscleGroup: String) async throws -> [PersonalRecord] { throw RepositoryError.notImplemented }
    func personalBest(forExercise: Exercise.ID) async throws -> PersonalRecord? { throw RepositoryError.notImplemented }
    func newPRs(in range: StatRange) async throws -> [PersonalRecord] { throw RepositoryError.notImplemented }
}

struct SupabaseUserRepository: UserRepository {
    func currentProfile() async throws -> UserProfile { throw RepositoryError.notImplemented }
    func profileSummary() async throws -> ProfileStats { throw RepositoryError.notImplemented }
}

struct SupabaseSettingsRepository: SettingsRepository {
    func load() async throws -> UserSettings { throw RepositoryError.notImplemented }
    func save(_ settings: UserSettings) async throws { throw RepositoryError.notImplemented }
}
