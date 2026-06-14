import Foundation

/// A selectable folder destination in an indented (root-first) tree list.
/// `id == nil` is the Library root.
struct FolderOption: Identifiable, Equatable {
    let id: UUID?
    let name: String
    let depth: Int
}

enum FolderOptions {
    /// Walks the folder tree from root and returns an indented, root-first list of
    /// destinations. `excluding` drops the given folder ids (used when moving a
    /// folder, so it can't nest into itself or its subtree); pass `[]` when picking
    /// a destination for a brand-new item.
    @MainActor
    static func load(from folders: any FolderRepository,
                     excluding: Set<UUID> = []) async -> [FolderOption] {
        var all: [Folder] = []
        func gather(parent: UUID?) async {
            let c = try? await folders.contents(of: parent)
            for f in (c?.folders ?? []) { all.append(f); await gather(parent: f.id) }
        }
        await gather(parent: nil)

        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        func depth(of id: UUID) -> Int {
            var d = 0; var cur = byID[id]?.parentID
            while let c = cur { d += 1; cur = byID[c]?.parentID }
            return d
        }
        var opts: [FolderOption] = [FolderOption(id: nil, name: "Library root", depth: 0)]
        for f in all where !excluding.contains(f.id) {
            opts.append(FolderOption(id: f.id, name: f.name, depth: depth(of: f.id) + 1))
        }
        return opts
    }
}
