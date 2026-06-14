import SwiftUI

@MainActor
@Observable
final class MoveToFolderModel {
    let moving: LibraryItemRef
    private(set) var options: [FolderOption] = []     // selectable destinations
    private let folderRepo: any FolderRepository

    init(moving: LibraryItemRef, folders: any FolderRepository) {
        self.moving = moving
        self.folderRepo = folders
    }

    func load() async {
        // When moving a folder, exclude itself + its descendants (can't nest into
        // its own subtree). Gathering the tree + indenting is shared with the wizard.
        var excluded: Set<UUID> = []
        if case let .folder(movingID) = moving {
            let all = await allFolders()
            excluded = descendants(of: movingID, in: all).union([movingID])
        }
        options = await FolderOptions.load(from: folderRepo, excluding: excluded)
    }

    private func allFolders() async -> [Folder] {
        var all: [Folder] = []
        func gather(parent: UUID?) async {
            let c = try? await folderRepo.contents(of: parent)
            for f in (c?.folders ?? []) { all.append(f); await gather(parent: f.id) }
        }
        await gather(parent: nil)
        return all
    }

    func confirm(destination: UUID?) async {
        switch moving {
        case .folder(let id):  try? await folderRepo.moveFolder(id: id, toParent: destination)
        case .workout(let id): try? await folderRepo.moveWorkout(id: id, toFolder: destination)
        case .program(let id): try? await folderRepo.moveProgram(id: id, toFolder: destination)
        }
    }

    private func descendants(of root: UUID, in all: [Folder]) -> Set<UUID> {
        var result: Set<UUID> = []
        var frontier = [root]
        while let cur = frontier.popLast() {
            for f in all where f.parentID == cur {
                if result.insert(f.id).inserted { frontier.append(f.id) }
            }
        }
        return result
    }
}

struct MoveToFolderSheet: View {
    @State private var model: MoveToFolderModel
    let onDone: () -> Void
    @Environment(Theme.self) private var theme

    init(model: MoveToFolderModel, onDone: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            StatLabel("MOVE TO")
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.options) { opt in
                        Button {
                            Task { await model.confirm(destination: opt.id); onDone() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: opt.id == nil ? "tray.full" : "folder")
                                    .foregroundStyle(theme.inkSoft)
                                Text(opt.name).foregroundStyle(theme.ink)
                                Spacer()
                            }
                            .padding(.leading, CGFloat(opt.depth) * 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("move.dest.\(opt.id?.uuidString ?? "root")")
                    }
                }
            }
        }
        .padding(theme.spacing[5])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .task { await model.load() }
    }
}
