import Foundation
import Observation

@MainActor
@Observable
final class WorkoutBuilderModel {
    var name: String = "New workout"
    var targets: Set<MuscleGroup> = []
    /// Empty by default: a new workout is built from the real catalog so every
    /// exercise has a valid id (a hardcoded sample seed produced ids that don't
    /// exist in the backend → the save hit a foreign-key error). Previews/tests
    /// pass a seed explicitly.
    var items: [BuilderExercise]
    var pickerPresented = false
    var isReordering = false
    var editingItemID: BuilderExercise.ID? = nil
    var saveState: SaveState = .idle
    /// The builder row currently being replaced (drives a single-select picker).
    var replacingItemID: BuilderExercise.ID? = nil

    // Exercise Picker state.
    var catalog: [BuilderCatalogGroup] = []
    var catalogLoading = false
    var catalogError: String? = nil

    private let catalogRepo: any ExerciseRepository
    private let workoutRepo: any WorkoutRepository

    init(catalog: any ExerciseRepository, workouts: any WorkoutRepository,
         items: [BuilderExercise] = []) {
        self.catalogRepo = catalog
        self.workoutRepo = workouts
        self.items = items
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

    /// Append picked exercises (deduped against existing + within the batch), each
    /// seeded with its chosen variation (fallback: the exercise default) and one
    /// working set.
    func addExercises(_ picked: [PickedExercise]) {
        var present = addedExerciseIDs
        let lookup = catalogByID
        for p in picked where !present.contains(p.id) {
            guard let exercise = lookup[p.id] else { continue }
            present.insert(p.id)
            items.append(BuilderExercise(
                exercise: exercise,
                variationID: p.variationID ?? exercise.defaultVariationID,
                supersetGroup: nil,
                sets: [SetSpec(reps: 10, rir: 2, type: .working)]))
        }
    }

    /// All catalog exercises by id (loaded catalog), for resolving picks.
    private var catalogByID: [Exercise.ID: Exercise] {
        Dictionary(uniqueKeysWithValues: catalog.flatMap { $0.exercises }.map { ($0.id, $0) })
    }

    /// Swap the exercise at `itemID` for `picked`, keeping its sets and superset
    /// grouping. Variation resets to the picked variation (or the new exercise's
    /// default).
    func replaceExercise(itemID: BuilderExercise.ID, with picked: PickedExercise) {
        guard let i = items.firstIndex(where: { $0.id == itemID }),
              let exercise = catalogByID[picked.id] else { return }
        items[i].exercise = exercise
        items[i].variationID = picked.variationID ?? exercise.defaultVariationID
        // sets and supersetGroup intentionally untouched
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

    /// Switch which variation of the exercise this item uses (e.g. barbell vs
    /// dumbbell). The picked id must belong to the exercise's `variations`.
    func updateVariation(itemID: BuilderExercise.ID, variationID: Variation.ID?) {
        guard let i = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[i].variationID = variationID
    }

    /// Toggle a muscle Target on/off.
    func toggleTarget(_ m: MuscleGroup) {
        if targets.contains(m) { targets.remove(m) } else { targets.insert(m) }
    }

    /// The draft persisted by `save()`. Targets are emitted in canonical
    /// `MuscleGroup.allCases` order for deterministic storage/tests.
    func makeDraft() -> Workout {
        let workoutExercises = items.map {
            WorkoutExercise(exercise: $0.exercise, variationID: $0.variationID,
                            supersetGroup: $0.supersetGroup, sets: $0.sets)
        }
        return Workout(name: name, order: 0,
                       exercises: workoutExercises,
                       targets: MuscleGroup.allCases.filter { targets.contains($0) })
    }

    func save() async {
        saveState = .saving
        do {
            _ = try await workoutRepo.saveWorkout(makeDraft())
            saveState = .saved
        } catch {
            // Surface the underlying reason (no program to attach to, auth/network,
            // a foreign-key violation, …) instead of an opaque failure.
            saveState = .error("Couldn't save workout — \(error.localizedDescription)")
        }
    }
}
