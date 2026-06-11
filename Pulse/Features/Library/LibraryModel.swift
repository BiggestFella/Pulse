import Foundation
import Observation

enum LibraryLoadState: Equatable { case loading, loaded, error }

@MainActor
@Observable
final class LibraryModel {
    var selectedFilter: LibraryFilter = .all
    private(set) var loadState: LibraryLoadState = .loading
    private(set) var folders: [LibraryFolder] = []
    private(set) var topWorkouts: [Workout] = []
    private(set) var topPrograms: [Program] = []
    private(set) var recentWorkouts: [WorkoutSummary] = []
    private(set) var catalog: [MuscleGroupCatalog] = []
    var isCreateSheetPresented = false

    private let folderRepo: any FolderRepository
    private let sessionRepo: any SessionRepository
    private let workoutRepo: any WorkoutRepository
    private let exerciseRepo: any ExerciseRepository
    private let prRepo: any PRRepository

    init(folders: any FolderRepository,
         sessionRepo: any SessionRepository,
         workoutRepo: any WorkoutRepository,
         exerciseRepo: any ExerciseRepository,
         prRepo: any PRRepository) {
        self.folderRepo = folders
        self.sessionRepo = sessionRepo
        self.workoutRepo = workoutRepo
        self.exerciseRepo = exerciseRepo
        self.prRepo = prRepo
    }

    var isAllEmpty: Bool {
        folders.isEmpty && topWorkouts.isEmpty && topPrograms.isEmpty && recentWorkouts.isEmpty
    }
    var isCatalogEmpty: Bool { catalog.allSatisfy(\.items.isEmpty) }

    func load() async {
        loadState = .loading
        do {
            let contents = try await folderRepo.contents(of: nil)
            let sessions = try await sessionRepo.fetchSessions(limit: 10)
            let workouts = try await workoutRepo.fetchWorkouts()
            let exercises = try await exerciseRepo.fetchCatalog()
            let prIDs = Set(try await prRepo.allPRs().map(\.exerciseID))

            self.folders = contents.folders.map(Self.project)
            self.topWorkouts = contents.workouts
            self.topPrograms = contents.programs
            self.recentWorkouts = Self.recent(sessions, workouts: workouts)
            self.catalog = Self.group(exercises, prIDs: prIDs)
            self.loadState = .loaded
        } catch {
            self.folders = []; self.topWorkouts = []; self.topPrograms = []
            self.recentWorkouts = []; self.catalog = []
            self.loadState = .error
        }
    }

    func retry() async { await load() }
    func select(_ filter: LibraryFilter) { selectedFilter = filter }
    func presentCreate() { isCreateSheetPresented = true }
    func dismissCreate() { isCreateSheetPresented = false }

    // MARK: - Projections

    static func project(_ folder: Folder) -> LibraryFolder {
        LibraryFolder(id: folder.id, name: folder.name, sub: "", color: folder.color)
    }

    /// Join logged sessions to their workout names, newest first.
    static func recent(_ sessions: [WorkoutSession], workouts: [Workout]) -> [WorkoutSummary] {
        let nameByID = Dictionary(workouts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return sessions.map { s in
            WorkoutSummary(id: s.id.uuidString,
                           name: nameByID[s.workoutID] ?? "Workout",
                           sub: "\(s.sets.count) set\(s.sets.count == 1 ? "" : "s")")
        }
    }

    /// Group catalog exercises by muscle, preserving first-appearance order.
    static func group(_ exercises: [Exercise], prIDs: Set<Exercise.ID>) -> [MuscleGroupCatalog] {
        var order: [String] = []
        var byMuscle: [String: [CatalogExercise]] = [:]
        for ex in exercises {
            if !order.contains(ex.muscleGroup) { order.append(ex.muscleGroup) }
            byMuscle[ex.muscleGroup, default: []].append(
                CatalogExercise(id: ex.id.uuidString,
                                name: ex.name,
                                equipment: ex.variations.first?.equipment ?? "",
                                variationCount: ex.variations.count,
                                hasPR: prIDs.contains(ex.id)))
        }
        return order.map { MuscleGroupCatalog(muscle: $0, items: byMuscle[$0] ?? []) }
    }
}
