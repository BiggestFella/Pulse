import SwiftUI

struct FolderBuilderView: View {
    @State private var model: FolderBuilderModel
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    init(model: FolderBuilderModel) { _model = State(initialValue: model) }

    var body: some View {
        BuilderScaffold(
            eyebrow: "NEW FOLDER", primaryLabel: "Create folder →",
            saving: model.saveState == .saving,
            onCancel: { dismiss() },
            onPrimary: { Task { await model.save() } }
        ) {
            VStack(spacing: theme.spacing[5]) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(theme.folderColor(model.colorToken))
                    .frame(width: 120, height: 96)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.ink, lineWidth: 3))
                    .shadow(color: theme.ink, radius: 0, x: 4, y: 4)
                    .accessibilityIdentifier("folder-preview")

                TextField("Folder name", text: $model.name)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(theme.ink)
                    .accessibilityIdentifier("folder-name")

                StatLabel("FOLDER COLOR")

                HStack(spacing: theme.spacing[3]) {
                    ForEach(FolderColor.allCases, id: \.self) { c in
                        Button { model.select(color: c) } label: {
                            Circle()
                                .fill(theme.folderColor(c))
                                .frame(width: 40, height: 40)
                                .overlay(Circle().stroke(theme.ink,
                                                         lineWidth: model.colorToken == c ? 3 : 0))
                                .overlay(Circle().stroke(theme.accent2,
                                                         lineWidth: model.colorToken == c ? 2 : 0)
                                            .padding(-4))
                        }
                        .accessibilityIdentifier("swatch-\(c.rawValue)")
                        .accessibilityAddTraits(model.colorToken == c ? [.isSelected] : [])
                    }
                }

                if case let .error(msg) = model.saveState {
                    Text(msg).foregroundStyle(theme.accent2).accessibilityIdentifier("save-error")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, theme.spacing[6])
        }
        .onChange(of: model.saveState) { _, new in if new == .saved { dismiss() } }
    }
}

#Preview {
    let theme = Theme()
    return NavigationStack {
        FolderBuilderView(model: FolderBuilderModel(folders: InMemoryFolderRepository()))
    }
    .environment(theme)
}
