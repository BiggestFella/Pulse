import SwiftUI

/// One folder row. Program folder → programDetail; others → folderDetail (routing
/// handled by the caller's `onTap`).
struct FolderRow: View {
    let folder: LibraryFolder
    let onTap: () -> Void
    var body: some View {
        LibraryRow(
            onTap: onTap,
            leading: { FolderIcon(tint: folder.tint) },
            content: { RowNameBlock(name: folder.name, sub: folder.sub) })
        .accessibilityIdentifier("folder.\(folder.id)")
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
