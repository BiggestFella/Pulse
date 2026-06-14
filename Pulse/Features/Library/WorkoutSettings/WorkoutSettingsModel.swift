import Foundation

@MainActor
@Observable
final class WorkoutSettingsModel {
    private(set) var loadState: LibraryLoadState = .loading
    var weekdays: Set<Int> = []
    var targets: Set<MuscleGroup> = []
    var restSeconds: Int?
    var notes: String = ""
    var folderID: Folder.ID?
    var folderOptions: [FolderOption] = []
    private(set) var deleted = false

    let workoutID: Workout.ID
    /// The full hydrated workout (incl. exercises). Every persist overrides ONE field
    /// on this and re-saves it, so a settings change never drops exercises/identity.
    private var workout: Workout?
    private let workoutRepo: any WorkoutRepository
    private let scheduleRepo: any ScheduleRepository
    private let folderRepo: any FolderRepository

    init(workoutID: Workout.ID,
         workoutRepo: any WorkoutRepository,
         scheduleRepo: any ScheduleRepository,
         folderRepo: any FolderRepository) {
        self.workoutID = workoutID
        self.workoutRepo = workoutRepo
        self.scheduleRepo = scheduleRepo
        self.folderRepo = folderRepo
    }

    func load() async {
        loadState = .loading
        guard let w = try? await workoutRepo.fetchWorkout(id: workoutID) else {
            loadState = .error; return
        }
        workout = w
        weekdays = Set(w.weekdays)
        targets = Set(w.targets)
        restSeconds = w.restSeconds
        notes = w.notes
        folderOptions = await FolderOptions.load(from: folderRepo)
        loadState = .loaded
    }

    /// Re-saves the hydrated workout with one field changed. Preserves id/order/exercises.
    private func persist(_ mutate: (inout Workout) -> Void) async {
        guard var w = workout else { return }
        mutate(&w)
        do { _ = try await workoutRepo.saveWorkout(w); workout = w } catch { }
    }

    func toggleWeekday(_ day: Int) async {
        if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
        let canonical = [1, 2, 3, 4, 5, 6, 7].filter { weekdays.contains($0) }
        await persist { $0.weekdays = canonical }
    }

    func scheduleOnDate(_ date: Date) async {
        try? await scheduleRepo.setPlan(.workout(workoutID), on: date)
    }

    func toggleTarget(_ m: MuscleGroup) async {
        if targets.contains(m) { targets.remove(m) } else { targets.insert(m) }
        let canonical = MuscleGroup.allCases.filter { targets.contains($0) }
        await persist { $0.targets = canonical }
    }

    func setRestSeconds(_ seconds: Int) async {
        let clamped = min(600, max(15, seconds))
        restSeconds = clamped
        await persist { $0.restSeconds = clamped }
    }

    func useDefaultRest() async {
        restSeconds = nil
        await persist { $0.restSeconds = nil }
    }

    func setNotes(_ text: String) async {
        notes = text
        await persist { $0.notes = text }
    }

    func setFolder(_ id: Folder.ID?) async {
        folderID = id
        try? await folderRepo.moveWorkout(id: workoutID, toFolder: id)
    }

    func delete() async {
        do { try await workoutRepo.deleteWorkout(id: workoutID); deleted = true } catch { }
    }
}
