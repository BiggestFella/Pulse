import SwiftUI

/// The "What are you making?" chooser. Each pick routes via `onPick`; the host
/// dismisses the sheet.
struct CreateChooserSheet: View {
    let onPick: (LibraryRoute) -> Void
    let onClose: () -> Void
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    StatLabel("CREATE NEW")
                    Text("What are you making?")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(theme.ink)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").foregroundStyle(theme.inkSoft)
                }
                .accessibilityIdentifier("create.close")
            }

            option(icon: "bolt.fill", tile: theme.accent, glyph: theme.onAccent,
                   name: "Workout", sub: "A single session you can run",
                   id: "create.workout") { onPick(.createWizard) }
            option(icon: "calendar", tile: theme.accent2, glyph: theme.onAccent,
                   name: "Routine", sub: "A multi-week program of workouts",
                   id: "create.routine") { onPick(.routineBuilder) }
            option(icon: "square.grid.2x2.fill", tile: theme.inkFaint, glyph: theme.ink,
                   name: "Folder", sub: "Group workouts together",
                   id: "create.folder") { onPick(.folderCreate) }
            Spacer()
        }
        .padding(theme.spacing[5])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
    }

    private func option(icon: String, tile: Color, glyph: Color,
                        name: String, sub: String, id: String,
                        action: @escaping () -> Void) -> some View {
        LibraryRow(
            onTap: action,
            leading: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(tile)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(glyph)
                }
                .frame(width: 38, height: 38)
            },
            content: { RowNameBlock(name: name, sub: sub) })
        .accessibilityIdentifier(id)
    }
}

#Preview {
    CreateChooserSheet(onPick: { _ in }, onClose: {}).environment(Theme())
}
