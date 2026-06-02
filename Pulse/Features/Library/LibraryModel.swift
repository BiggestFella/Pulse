import Foundation
import Observation

enum LibraryLoadState: Equatable { case loading, loaded, error }

@MainActor
@Observable
final class LibraryModel {
    var selectedFilter: LibraryFilter = .all
    private(set) var loadState: LibraryLoadState = .loading
    private(set) var folders: [LibraryFolder] = []
    private(set) var recentWorkouts: [WorkoutSummary] = []
    private(set) var catalog: [MuscleGroupCatalog] = []
    var isCreateSheetPresented = false

    private let library: LibraryRepository
    private let exerciseRepo: any ExerciseRepository
    private let prRepo: any PRRepository

    init(library: LibraryRepository, exerciseRepo: any ExerciseRepository, prRepo: any PRRepository) {
        self.library = library
        self.exerciseRepo = exerciseRepo
        self.prRepo = prRepo
    }

    /// True when, under the All view, there is nothing to show.
    var isAllEmpty: Bool { folders.isEmpty && recentWorkouts.isEmpty }
    var isCatalogEmpty: Bool { catalog.allSatisfy(\.items.isEmpty) }

    func load() async {
        loadState = .loading
        do {
            let folders = try await library.folders()
            let recent = try await library.recentWorkouts()
            let exercises = try await exerciseRepo.fetchCatalog()
            let prIDs = Set(try await prRepo.allPRs().map(\.exerciseID))
            self.folders = folders
            self.recentWorkouts = recent
            self.catalog = Self.group(exercises, prIDs: prIDs)
            self.loadState = .loaded
        } catch {
            self.folders = []
            self.recentWorkouts = []
            self.catalog = []
            self.loadState = .error
        }
    }

    func retry() async { await load() }
    func select(_ filter: LibraryFilter) { selectedFilter = filter }
    func presentCreate() { isCreateSheetPresented = true }
    func dismissCreate() { isCreateSheetPresented = false }

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
