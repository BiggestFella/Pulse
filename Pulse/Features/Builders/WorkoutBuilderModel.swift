import Foundation
import Observation

@MainActor
@Observable
final class WorkoutBuilderModel {
    var name: String = "New workout"
    var tag: WorkoutTag = .push
    var items: [BuilderExercise] = BuilderSampleData.defaultWorkoutItems
    var pickerPresented = false
    var editingItemID: BuilderExercise.ID? = nil
    var saveState: SaveState = .idle

    // Exercise Picker state.
    var catalog: [BuilderCatalogGroup] = []
    var catalogLoading = false
    var catalogError: String? = nil

    private let catalogRepo: any ExerciseRepository
    private let workoutRepo: any WorkoutRepository

    init(catalog: any ExerciseRepository, workouts: any WorkoutRepository) {
        self.catalogRepo = catalog
        self.workoutRepo = workouts
    }

    var totalSets: Int { items.reduce(0) { $0 + $1.sets.count } }

    /// The set of exercise ids already in the builder (drives picker dimming).
    var addedExerciseIDs: Set<Exercise.ID> { Set(items.map { $0.exercise.id }) }

    func loadCatalog() async {
        catalogLoading = true
        catalogError = nil
        do {
            catalog = Self.group(try await catalogRepo.fetchCatalog())
        } catch {
            catalogError = "Couldn't load exercises."
        }
        catalogLoading = false
    }

    /// Group a flat catalog by muscle, preserving first-appearance order.
    static func group(_ exercises: [Exercise]) -> [BuilderCatalogGroup] {
        var order: [String] = []
        var byMuscle: [String: [Exercise]] = [:]
        for ex in exercises {
            if !order.contains(ex.muscleGroup) { order.append(ex.muscleGroup) }
            byMuscle[ex.muscleGroup, default: []].append(ex)
        }
        return order.map { BuilderCatalogGroup(muscle: $0, exercises: byMuscle[$0] ?? []) }
    }

    /// Append picked exercises (deduped against existing + within the batch),
    /// each seeded with one working set and its default variation.
    func addExercises(_ ids: [Exercise.ID]) {
        var present = addedExerciseIDs
        let lookup = Dictionary(
            uniqueKeysWithValues: catalog.flatMap { $0.exercises }.map { ($0.id, $0) })
        for id in ids where !present.contains(id) {
            guard let exercise = lookup[id] else { continue }
            present.insert(id)
            items.append(BuilderExercise(
                exercise: exercise,
                variationID: exercise.defaultVariationID,
                supersetGroup: nil,
                sets: [SetSpec(reps: 10, rir: 2, type: .working)]))
        }
    }

    func removeItem(id: BuilderExercise.ID) {
        items.removeAll { $0.id == id }
    }

    /// Reorder exercises (drag-to-move from the builder's edit mode). Operates on
    /// the flat `items` array; moving a row out of a contiguous superset run
    /// naturally breaks that run, which matches the user's intent.
    func move(from source: IndexSet, to destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
    }

    /// Toggle the link between row `idx` and `idx+1`. No-op on the last row.
    func toggleLink(at idx: Int) {
        guard idx >= 0, idx + 1 < items.count else { return }
        let a = items[idx].supersetGroup
        let b = items[idx + 1].supersetGroup
        if let a, a == b {
            items[idx + 1].supersetGroup = nil       // break the lower row out
        } else {
            let group = a ?? UUID().uuidString
            items[idx].supersetGroup = group
            items[idx + 1].supersetGroup = group
        }
    }

    func addSet(itemID: BuilderExercise.ID) {
        guard let i = items.firstIndex(where: { $0.id == itemID }),
              let last = items[i].sets.last else { return }
        items[i].sets.append(SetSpec(reps: last.reps, rir: last.rir, type: .working))
    }

    func removeSet(itemID: BuilderExercise.ID, index: Int) {
        guard let i = items.firstIndex(where: { $0.id == itemID }),
              items[i].sets.count > 1,
              items[i].sets.indices.contains(index) else { return }
        items[i].sets.remove(at: index)
    }

    func updateSet(itemID: BuilderExercise.ID, index: Int, reps: Int, rir: Int, type: SetType) {
        guard let i = items.firstIndex(where: { $0.id == itemID }),
              items[i].sets.indices.contains(index) else { return }
        items[i].sets[index].reps = max(0, reps)
        items[i].sets[index].rir = min(5, max(0, rir))
        items[i].sets[index].type = type
    }

    func save() async {
        saveState = .saving
        let workoutExercises = items.map {
            WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                            supersetGroup: $0.supersetGroup, sets: $0.sets)
        }
        let draft = Workout(name: name, weekday: nil, order: 0, exercises: workoutExercises)
        do {
            _ = try await workoutRepo.saveWorkout(draft)
            saveState = .saved
        } catch {
            saveState = .error("Couldn't save workout.")
        }
    }
}
