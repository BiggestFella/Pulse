import Foundation

/// One internally-consistent mock world. Every id referenced across graphs
/// resolves: a session's `workoutID` points at a real workout; a
/// `SessionSet.exerciseID` at a real catalog exercise. Built once as
/// `static let`s so all mock repositories share the same ids.
enum SampleData {

    // MARK: Calendar helpers
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2 // Monday
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_AU")
        return c
    }()
    private static func daysAgo(_ n: Int) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: -n, to: Date())!)
    }

    // MARK: Exercise catalog (20 exercises, grouped by muscle)
    private static func ex(_ name: String, _ muscle: String,
                           _ variationNames: [String]) -> Exercise {
        let vars = variationNames.map { Variation(name: $0, equipment: nil) }
        return Exercise(name: name, muscleGroup: muscle,
                        variations: vars, defaultVariationID: vars.first?.id)
    }

    static let exercises: [Exercise] = [
        // Chest
        ex("Bench Press", "Chest", ["Barbell", "Dumbbell", "Smith"]),
        ex("Incline Press", "Chest", ["Barbell", "Dumbbell"]),
        ex("Cable Fly", "Chest", ["High", "Low"]),
        ex("Push-Up", "Chest", ["Bodyweight"]),                 // single-variation
        // Back
        ex("Deadlift", "Back", ["Conventional", "Sumo"]),
        ex("Pull-Up", "Back", ["Bodyweight", "Weighted"]),
        ex("Barbell Row", "Back", ["Overhand", "Underhand"]),
        ex("Lat Pulldown", "Back", ["Wide", "Close", "Neutral"]),
        ex("Seated Cable Row", "Back", ["V-Bar"]),              // single-variation
        // Shoulders
        ex("Overhead Press", "Shoulders", ["Barbell", "Dumbbell"]),
        ex("Lateral Raise", "Shoulders", ["Dumbbell", "Cable"]),
        ex("Face Pull", "Shoulders", ["Rope"]),                 // single-variation
        // Legs
        ex("Back Squat", "Legs", ["High-Bar", "Low-Bar"]),
        ex("Front Squat", "Legs", ["Barbell"]),                 // single-variation
        ex("Leg Press", "Legs", ["45°", "Horizontal"]),
        ex("Romanian Deadlift", "Legs", ["Barbell", "Dumbbell"]),
        ex("Leg Curl", "Legs", ["Seated", "Lying"]),
        ex("Calf Raise", "Legs", ["Standing", "Seated"]),
        // Arms
        ex("Barbell Curl", "Arms", ["Straight", "EZ-Bar"]),
        ex("Triceps Pushdown", "Arms", ["Rope", "Bar"]),
    ]

    private static func byName(_ name: String) -> Exercise {
        exercises.first { $0.name == name }!
    }

    // MARK: Workouts
    private static func we(_ name: String, superset: String? = nil,
                           sets: [SetSpec]) -> WorkoutExercise {
        let exercise = byName(name)
        return WorkoutExercise(exercise: exercise,
                               variationID: exercise.defaultVariationID,
                               supersetGroup: superset, sets: sets)
    }
    private static func working(_ reps: Int, _ rir: Int) -> SetSpec {
        SetSpec(reps: reps, rir: rir, type: .working)
    }
    private static let warmup = SetSpec(reps: 8, rir: 0, type: .warmup)

    static let pushWorkout = Workout(
        name: "Push", weekdays: [1], order: 0,
        exercises: [
            we("Bench Press", sets: [warmup, working(8, 2), working(8, 1), working(6, 0)]),
            we("Overhead Press", sets: [working(10, 2), working(10, 2)]),
            we("Incline Press", superset: "A", sets: [working(12, 2), working(12, 1)]),
            we("Cable Fly", superset: "A", sets: [working(15, 1), working(15, 0)]),
            we("Triceps Pushdown", sets: [working(12, 1), working(12, 0)]),
        ])

    static let pullWorkout = Workout(
        name: "Pull", weekdays: [3], order: 1,
        exercises: [
            we("Deadlift", sets: [warmup, working(5, 2), working(5, 1)]),
            we("Pull-Up", sets: [working(8, 2), working(8, 1)]),
            we("Barbell Row", sets: [working(10, 2), working(10, 1)]),
            we("Lat Pulldown", sets: [working(12, 1), working(12, 0)]),
            we("Barbell Curl", sets: [working(12, 1), working(12, 0)]),
        ])

    static let legsWorkout = Workout(
        name: "Legs", weekdays: [5], order: 2,
        exercises: [
            we("Back Squat", sets: [warmup, working(6, 2), working(6, 1), working(5, 0)]),
            we("Romanian Deadlift", sets: [working(10, 2), working(10, 1)]),
            we("Leg Press", sets: [working(12, 2), working(12, 1)]),
            we("Leg Curl", superset: "B", sets: [working(12, 1)]),
            we("Calf Raise", superset: "B", sets: [working(15, 0), working(15, 0)]),
        ])

    // MARK: Program
    static let program = Program(
        name: "Push / Pull / Legs", weeks: 6, isActive: true,
        workouts: [pushWorkout, pullWorkout, legsWorkout])

    // MARK: Library folders (mock path)
    /// A sample Library folder for the mock path; the sample program lives inside it.
    static let folder = Folder(
        id: UUID(uuidString: "A1B2C3D4-0000-4000-8000-000000000001")!,
        name: "Push Pull Legs", color: .blue, parentID: nil)
    static let folders: [Folder] = [folder]
    static let programFolderID: [Program.ID: Folder.ID] = [program.id: folder.id]

    // MARK: Sessions (10 sessions across the last ~30 days, progressive overload)
    private static func loggedSets(for workout: Workout, weightBump: Double) -> [SessionSet] {
        var out: [SessionSet] = []
        var order = 0
        for we in workout.exercises {
            let base: Double
            switch we.exercise.muscleGroup {
            case "Legs": base = 100
            case "Back": base = 80
            case "Chest": base = 60
            default: base = 30
            }
            for spec in we.sets where spec.type != .warmup {
                let resolvedType: SetType = spec.type == .amrap ? .amrap : .working
                // Demo signal: heavier bump → lower RIR (harder). nil for the very
                // first batch so "legacy / untagged" rows coexist with tagged ones.
                let rir: Int? = weightBump == 0 ? nil : max(0, 3 - Int(weightBump / 2.5))
                out.append(SessionSet(exerciseID: we.exercise.id, order: order,
                                      reps: spec.reps, weight: base + weightBump,
                                      type: resolvedType, rir: rir))
                order += 1
            }
        }
        return out
    }

    static let sessions: [WorkoutSession] = {
        let plan: [(workout: Workout, daysAgo: Int, bump: Double)] = [
            (pushWorkout, 22, 0),  (pullWorkout, 20, 0),  (legsWorkout, 18, 0),
            (pushWorkout, 15, 2.5),(pullWorkout, 13, 2.5),(legsWorkout, 11, 2.5),
            (pushWorkout, 8, 5),   (pullWorkout, 6, 5),   (legsWorkout, 4, 5),
            (pushWorkout, 1, 10),  // fresh PR day
        ]
        return plan.map { item in
            let start = calendar.date(byAdding: .hour, value: 18, to: daysAgo(item.daysAgo))!
            let end = calendar.date(byAdding: .minute, value: 62, to: start)!
            return WorkoutSession(workoutID: item.workout.id, startedAt: start,
                                  endedAt: end,
                                  sets: loggedSets(for: item.workout, weightBump: item.bump))
        }
    }()

    // MARK: Schedule (one month)
    static let schedule: [Date: DayPlan] = {
        var out: [Date: DayPlan] = [:]
        let completedByDay = Dictionary(
            grouping: sessions, by: { calendar.startOfDay(for: $0.startedAt) })
        for offset in -27...2 {
            let day = daysAgo(-offset)
            let weekday = calendar.component(.weekday, from: day) // 1=Sun…7=Sat
            let isTraining = [2, 4, 6].contains(weekday) // Mon/Wed/Fri (Gregorian)
            if let session = completedByDay[day]?.first {
                out[day] = .done(session.id)
            } else if isTraining {
                // Assign by weekday (not offset) so the planned workout matches the
                // weekday-based hero `todaysWorkout(on:)` — Mon→Push, Wed→Pull,
                // Fri→Legs. Map Gregorian (1=Sun…7=Sat) to app weekday (Mon→1…Sun→7)
                // the same way the repository does, then pick the workout that owns it.
                let appWeekday = ((weekday + 5) % 7) + 1
                let w = [pushWorkout, pullWorkout, legsWorkout]
                    .first { $0.weekdays.contains(appWeekday) } ?? pushWorkout
                out[day] = .workout(w.id)
            } else {
                out[day] = .rest
            }
        }
        return out
    }()
}
