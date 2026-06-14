import Foundation
import Observation

@MainActor
@Observable
final class RoutineBuilderModel {
    var name: String = "New routine"
    var weeks: Int = 8
    var days: [BuilderDay] = BuilderSampleData.defaultRoutineDays
    var pickerPresented = false
    var saveState: SaveState = .idle

    // Workout Picker state.
    var savedWorkouts: [Workout] = []
    var savedLoading = false
    var savedError: String? = nil

    private let routineRepo: any ProgramRepository
    private let workoutRepo: any WorkoutRepository

    init(routines: any ProgramRepository, workouts: any WorkoutRepository) {
        self.routineRepo = routines
        self.workoutRepo = workouts
    }

    var workoutsPerWeek: Int { days.filter { !$0.isRest }.count }

    func loadSavedWorkouts() async {
        savedLoading = true
        savedError = nil
        do {
            savedWorkouts = try await workoutRepo.fetchWorkouts()
        } catch {
            savedError = "Couldn't load workouts."
        }
        savedLoading = false
    }

    func incWeeks() { weeks += 1 }
    func decWeeks() { weeks = max(1, weeks - 1) }

    func addWorkout(_ day: BuilderDay) { days.append(day) }

    func addRestDay() {
        days.append(BuilderDay(name: "Rest", sub: "Recovery", isRest: true))
    }

    func removeDay(id: BuilderDay.ID) { days.removeAll { $0.id == id } }

    func save() async {
        saveState = .saving
        let workouts = days.enumerated()
            .filter { !$0.element.isRest }
            .map { idx, day in
                Workout(name: day.name, order: idx, exercises: [])
            }
        let draft = Program(name: name, weeks: weeks, workouts: workouts)
        do {
            _ = try await routineRepo.saveProgram(draft)
            saveState = .saved
        } catch {
            saveState = .error("Couldn't save routine.")
        }
    }
}
