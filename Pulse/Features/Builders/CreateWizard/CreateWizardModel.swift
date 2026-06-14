import Foundation

@MainActor
@Observable
final class CreateWizardModel {
    enum Step: Int, CaseIterable { case name, targets, schedule, folder }

    var step: Step = .name
    var name: String = ""
    var targets: Set<MuscleGroup> = []
    var weekdays: Set<Int> = []
    var folderID: Folder.ID?

    var folderOptions: [FolderOption] = []
    var creating = false

    private let workoutRepo: any WorkoutRepository
    private let folderRepo: any FolderRepository

    init(workouts: any WorkoutRepository,
         folders: any FolderRepository,
         folderID: Folder.ID? = nil) {
        self.workoutRepo = workouts
        self.folderRepo = folders
        self.folderID = folderID
    }

    var isFirstStep: Bool { step == .name }
    var isLastStep: Bool { step == Step.allCases.last }
    var stepNumber: Int { step.rawValue + 1 }          // 1-based, for the progress bar
    var stepCount: Int { Step.allCases.count }

    /// Name is required; Targets/Schedule/Folder are optional.
    var canAdvance: Bool {
        switch step {
        case .name: return !name.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    func next() { if let n = Step(rawValue: step.rawValue + 1) { step = n } }
    func back() { if let p = Step(rawValue: step.rawValue - 1) { step = p } }

    func toggleTarget(_ m: MuscleGroup) {
        if targets.contains(m) { targets.remove(m) } else { targets.insert(m) }
    }
    func toggleWeekday(_ day: Int) {
        if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
    }

    func loadFolders() async {
        folderOptions = await FolderOptions.load(from: folderRepo)
    }

    /// Persists the draft workout (name + targets + weekdays, zero exercises) and
    /// places it in the chosen folder. Returns the new workout id, or nil on failure.
    func create() async -> Workout.ID? {
        creating = true
        defer { creating = false }
        let draft = Workout(
            name: name.trimmingCharacters(in: .whitespaces),
            weekdays: [1, 2, 3, 4, 5, 6, 7].filter { weekdays.contains($0) },   // canonical order
            order: 0,
            exercises: [],
            targets: MuscleGroup.allCases.filter { targets.contains($0) })
        do {
            let saved = try await workoutRepo.saveWorkout(draft)
            if let folderID { try await folderRepo.moveWorkout(id: saved.id, toFolder: folderID) }
            return saved.id
        } catch {
            return nil
        }
    }
}
