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
    private(set) var pendingDelete: PendingFolderDelete?
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

    func requestDelete(_ folder: LibraryFolder) async {
        let count = (try? await folderRepo.contents(of: folder.id)).map {
            $0.folders.count + $0.workouts.count + $0.programs.count
        } ?? 0
        if count == 0 {
            try? await folderRepo.deleteFolder(id: folder.id)
            await load()
        } else {
            pendingDelete = PendingFolderDelete(folder: folder, itemCount: count)
        }
    }

    func confirmDelete() async {
        guard let pending = pendingDelete else { return }
        pendingDelete = nil
        try? await folderRepo.deleteFolder(id: pending.folder.id)
        await load()
    }

    func cancelDelete() { pendingDelete = nil }

    // MARK: - Projections

    static func project(_ folder: Folder) -> LibraryFolder {
        LibraryFolder(id: folder.id, name: folder.name, sub: "", color: folder.color)
    }

    /// Join logged sessions to their workout names, newest first.
    static func recent(_ sessions: [WorkoutSession], workouts: [Workout], now: Date = Date()) -> [WorkoutSummary] {
        let nameByID = Dictionary(workouts.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return sessions.map { s in
            let setCount = s.sets.count
            return WorkoutSummary(
                id: s.id.uuidString,
                name: nameByID[s.workoutID] ?? "Workout",
                sub: "\(setCount) set\(setCount == 1 ? "" : "s") · \(relativeDay(s.startedAt, now: now))")
        }
    }

    /// Relative day label: Today / Yesterday / "N days ago" (2–6) / "d MMM" (7+).
    static func relativeDay(_ date: Date, now: Date) -> String {
        let cal = SampleData.calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1:   return "Today"
        case 1:      return "Yesterday"
        case 2...6:  return "\(days) days ago"
        default:
            let f = DateFormatter()
            f.calendar = cal
            f.dateFormat = "d MMM"
            return f.string(from: date)
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
