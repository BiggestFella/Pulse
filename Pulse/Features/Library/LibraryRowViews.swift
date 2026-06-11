import SwiftUI

/// One folder row.
struct FolderRow: View {
    let folder: LibraryFolder
    let onTap: () -> Void
    var body: some View {
        LibraryRow(
            onTap: onTap,
            leading: { FolderIcon(color: folder.color) },
            content: { RowNameBlock(name: folder.name, sub: folder.sub) })
        .accessibilityIdentifier("folder.\(folder.id)")
    }
}

/// One workout row inside the Library (a workout that lives in this folder / at root).
struct LibraryWorkoutRow: View {
    let workout: Workout
    let onTap: () -> Void
    var body: some View {
        LibraryRow(
            onTap: onTap,
            content: { RowNameBlock(
                name: workout.name,
                sub: "\(workout.exercises.count) exercise\(workout.exercises.count == 1 ? "" : "s")") })
        .accessibilityIdentifier("workout.\(workout.id)")
    }
}

/// One program row inside the Library.
struct LibraryProgramRow: View {
    let program: Program
    let onTap: () -> Void
    var body: some View {
        LibraryRow(
            onTap: onTap,
            content: { RowNameBlock(name: program.name, sub: "\(program.weeks)-week program") })
        .accessibilityIdentifier("program.\(program.id)")
    }
}

/// One recent-workout row (display-only in this release).
struct RecentRow: View {
    let workout: WorkoutSummary
    var body: some View {
        LibraryRow(content: { RowNameBlock(name: workout.name, sub: workout.sub) })
            .accessibilityIdentifier("recent.\(workout.id)")
    }
}

/// One catalog exercise row, with an optional PR tag.
struct CatalogRow: View {
    let exercise: CatalogExercise
    let onTap: () -> Void
    var body: some View {
        LibraryRow(
            onTap: onTap,
            content: { RowNameBlock(name: exercise.name, sub: exercise.subline) },
            trailing: exercise.hasPR ? AnyView(PrTag()) : nil)
        .accessibilityIdentifier("library.exercise.\(exercise.name)")
    }
}
