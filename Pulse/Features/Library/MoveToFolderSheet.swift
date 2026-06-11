import SwiftUI

@MainActor
@Observable
final class MoveToFolderModel {
    let moving: LibraryItemRef
    private(set) var options: [Indented] = []     // selectable destinations
    private let folderRepo: any FolderRepository

    struct Indented: Identifiable, Equatable {
        let id: UUID?        // nil = Library root
        let name: String
        let depth: Int
    }

    init(moving: LibraryItemRef, folders: any FolderRepository) {
        self.moving = moving
        self.folderRepo = folders
    }

    func load() async {
        // 1. Collect every folder by walking the tree from root.
        var all: [Folder] = []
        func gather(parent: UUID?) async {
            let c = try? await folderRepo.contents(of: parent)
            for f in (c?.folders ?? []) {
                all.append(f)
                await gather(parent: f.id)
            }
        }
        await gather(parent: nil)

        // 2. When moving a folder, exclude itself + its descendants (can't nest into own subtree).
        var excluded: Set<UUID> = []
        if case let .folder(movingID) = moving {
            excluded = descendants(of: movingID, in: all).union([movingID])
        }

        // 3. Build the indented option list (root + every allowed folder).
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        func depth(of id: UUID) -> Int {
            var d = 0; var cur = byID[id]?.parentID
            while let c = cur { d += 1; cur = byID[c]?.parentID }
            return d
        }
        var opts: [Indented] = [Indented(id: nil, name: "Library root", depth: 0)]
        for f in all where !excluded.contains(f.id) {
            opts.append(Indented(id: f.id, name: f.name, depth: depth(of: f.id) + 1))
        }
        options = opts
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
