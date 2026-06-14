import Foundation
import Observation

/// One exercise row on the Workout Detail screen.
struct WorkoutDetailRow: Identifiable, Equatable {
    let id: UUID            // WorkoutExercise.id
    let exerciseName: String
    let variationName: String
    let setSummary: String  // e.g. "4 sets · 12·10·8·6"
}

/// Read-only detail for a saved workout, with a Start action that hands the
/// hydrated workout to the active session via `onStart`.
@MainActor
@Observable
final class WorkoutDetailModel {
    let title: String
    private(set) var loadState: LibraryLoadState = .loading
    private(set) var rows: [WorkoutDetailRow] = []
    private(set) var workout: Workout?
    private(set) var weekdays: Set<Int> = []

    private let workoutID: UUID
    private let workoutRepo: any WorkoutRepository
    private let scheduleRepo: any ScheduleRepository
    private let onStart: (Workout) -> Void

    init(workoutID: UUID,
         title: String,
         workoutRepo: any WorkoutRepository,
         scheduleRepo: any ScheduleRepository,
         onStart: @escaping (Workout) -> Void) {
        self.workoutID = workoutID
        self.title = title
        self.workoutRepo = workoutRepo
        self.scheduleRepo = scheduleRepo
        self.onStart = onStart
    }

    /// Start is available only once the workout has loaded with ≥1 exercise.
    var canStart: Bool { workout?.exercises.isEmpty == false }

    func load() async {
        loadState = .loading
        do {
            guard let w = try await workoutRepo.fetchWorkout(id: workoutID) else {
                workout = nil; rows = []; loadState = .error; return
            }
            workout = w
            weekdays = Set(w.weekdays)
            rows = w.exercises.map(Self.row)
            loadState = .loaded
        } catch {
            workout = nil; rows = []; loadState = .error
        }
    }

    func start() {
        guard let workout, canStart else { return }
        onStart(workout)
    }

    func toggleWeekday(_ day: Int) async {
        guard var w = workout else { return }
        if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
        w.weekdays = [1, 2, 3, 4, 5, 6, 7].filter { weekdays.contains($0) }  // canonical order
        do { _ = try await workoutRepo.saveWorkout(w); workout = w } catch { }
    }

    func scheduleOnDate(_ date: Date) async {
        guard let id = workout?.id else { return }
        try? await scheduleRepo.setPlan(.workout(id), on: date)
    }

    /// Project a `WorkoutExercise` into a display row. Variation name resolves
    /// from the chosen variation (or the exercise default); the set summary is
    /// the rep ladder joined by "·".
    static func row(_ we: WorkoutExercise) -> WorkoutDetailRow {
        let variation = we.exercise.variations.first {
            $0.id == (we.variationID ?? we.exercise.defaultVariationID)
        }
        let reps = we.sets.map { String($0.reps) }.joined(separator: "·")
        let n = we.sets.count
        let summary = "\(n) set\(n == 1 ? "" : "s")\(reps.isEmpty ? "" : " · \(reps)")"
        return WorkoutDetailRow(
            id: we.id,
            exerciseName: we.exercise.name,
            variationName: variation?.name ?? "",
            setSummary: summary)
    }
}
