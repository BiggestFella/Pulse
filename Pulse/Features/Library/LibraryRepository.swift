import Foundation

/// Folders + recent workouts for the Library. Folders have no data model in the
/// data layer yet, so this is mock-backed UI-first sample data (a real Folder
/// model is a future addition); the exercise catalog comes from the merged
/// `ExerciseRepository` instead.
protocol LibraryRepository {
    func folders() async throws -> [LibraryFolder]
    func recentWorkouts() async throws -> [WorkoutSummary]
}

struct MockLibraryRepository: LibraryRepository {
    var shouldFail = false
    var empty = false

    func folders() async throws -> [LibraryFolder] {
        if shouldFail { throw RepositoryError.forced }
        if empty { return [] }
        return [
            LibraryFolder(id: "ppl", name: "Push / Pull / Legs",
                          sub: "6 workouts · active program", tint: .accent, isProgram: true),
            LibraryFolder(id: "cardio", name: "Cardio & Conditioning",
                          sub: "4 workouts", tint: .accent2, isProgram: false),
            LibraryFolder(id: "oneoffs", name: "One-offs",
                          sub: "7 workouts", tint: .neutral, isProgram: false),
        ]
    }

    func recentWorkouts() async throws -> [WorkoutSummary] {
        if shouldFail { throw RepositoryError.forced }
        if empty { return [] }
        return [
            WorkoutSummary(id: "chest-tris", name: "Chest & Tris", sub: "7 exercises · used today"),
            WorkoutSummary(id: "back-bis", name: "Back & Bis", sub: "6 exercises · 5d ago"),
            WorkoutSummary(id: "leg-day", name: "Leg day", sub: "5 exercises · 7d ago"),
        ]
    }
}
