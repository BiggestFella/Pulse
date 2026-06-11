import SwiftUI

@MainActor
@Observable
final class FolderDetailModel {
    let folderID: UUID
    let title: String
    private(set) var loadState: LibraryLoadState = .loading
    private(set) var folders: [LibraryFolder] = []
    private(set) var workouts: [Workout] = []
    private(set) var programs: [Program] = []

    private let folderRepo: any FolderRepository

    init(folderID: UUID, title: String, folders: any FolderRepository) {
        self.folderID = folderID
        self.title = title
        self.folderRepo = folders
    }

    func load() async {
        loadState = .loading
        do {
            let c = try await folderRepo.contents(of: folderID)
            folders = c.folders.map(LibraryModel.project)
            workouts = c.workouts
            programs = c.programs
            loadState = .loaded
        } catch {
            folders = []; workouts = []; programs = []
            loadState = .error
        }
    }

    func delete(_ folder: LibraryFolder) async {
        try? await folderRepo.deleteFolder(id: folder.id)
        await load()
    }
}

struct FolderDetailView: View {
    @State private var model: FolderDetailModel
    let onOpenFolder: (UUID, String) -> Void
    let onOpenWorkout: (Workout) -> Void
    let onOpenProgram: (Program) -> Void
    let onMove: (LibraryItemRef) -> Void
    @Environment(Theme.self) private var theme

    init(model: FolderDetailModel,
         onOpenFolder: @escaping (UUID, String) -> Void,
         onOpenWorkout: @escaping (Workout) -> Void,
         onOpenProgram: @escaping (Program) -> Void,
         onMove: @escaping (LibraryItemRef) -> Void) {
        _model = State(initialValue: model)
        self.onOpenFolder = onOpenFolder
        self.onOpenWorkout = onOpenWorkout
        self.onOpenProgram = onOpenProgram
        self.onMove = onMove
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("folderDetail.title")
                Group {
                    switch model.loadState {
                    case .loading:
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    case .error:
                        Text("Couldn't load this folder.")
                            .foregroundStyle(theme.inkSoft).padding(.top, 40)
                    case .loaded:
                        FolderContentsSection(
                            folders: model.folders, workouts: model.workouts, programs: model.programs,
                            onOpenFolder: { id in
                                let name = model.folders.first { $0.id == id }?.name ?? "Folder"
                                onOpenFolder(id, name)
                            },
                            onOpenWorkout: onOpenWorkout, onOpenProgram: onOpenProgram,
                            onMove: onMove,
                            onDelete: { folder in Task { await model.delete(folder) } })
                            .padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .background(theme.bg.ignoresSafeArea())
        .task { await model.load() }
        .accessibilityIdentifier("folderDetail.\(model.folderID)")
    }
}
