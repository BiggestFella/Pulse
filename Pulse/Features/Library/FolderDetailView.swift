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
    private(set) var pendingDelete: PendingFolderDelete?

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

    func requestDelete(_ folder: LibraryFolder) async {
        let count = (try? await folderRepo.contents(of: folder.id)).map {
            $0.folders.count + $0.workouts.count + $0.programs.count
        } ?? 0
        if count == 0 {
            try? await folderRepo.deleteFolder(id: folder.id)
            await load()
        } else {
            pendingDelete = PendingFolderDelete(folder: folder, itemCount: count)
        }
    }

    func confirmDelete() async {
        guard let pending = pendingDelete else { return }
        pendingDelete = nil
        try? await folderRepo.deleteFolder(id: pending.folder.id)
        await load()
    }

    func cancelDelete() { pendingDelete = nil }
}

struct FolderDetailView: View {
    @State private var model: FolderDetailModel
    let refreshID: Int
    let onOpenFolder: (UUID, String) -> Void
    let onOpenWorkout: (Workout) -> Void
    let onOpenProgram: (Program) -> Void
    let onMove: (LibraryItemRef) -> Void
    let onCreateHere: () -> Void
    @Environment(Theme.self) private var theme

    init(model: FolderDetailModel,
         refreshID: Int,
         onOpenFolder: @escaping (UUID, String) -> Void,
         onOpenWorkout: @escaping (Workout) -> Void,
         onOpenProgram: @escaping (Program) -> Void,
         onMove: @escaping (LibraryItemRef) -> Void,
         onCreateHere: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.refreshID = refreshID
        self.onOpenFolder = onOpenFolder
        self.onOpenWorkout = onOpenWorkout
        self.onOpenProgram = onOpenProgram
        self.onMove = onMove
        self.onCreateHere = onCreateHere
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(model.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .accessibilityIdentifier("folderDetail.title")
                    Spacer()
                    Button { onCreateHere() } label: {
                        Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(theme.ink)
                            .frame(width: 34, height: 34).overlay(Circle().strokeBorder(theme.inkFaint, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("folderDetail.create")
                }
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
                            onDelete: { folder in Task { await model.requestDelete(folder) } })
                            .padding(.top, 14)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .background(theme.bg.ignoresSafeArea())
        .task { await model.load() }
        .onChange(of: refreshID) { _, _ in Task { await model.load() } }
        .alert("Delete folder?", isPresented: Binding(
            get: { model.pendingDelete != nil }, set: { if !$0 { model.cancelDelete() } })) {
            Button("Cancel", role: .cancel) { model.cancelDelete() }
            Button("Delete", role: .destructive) { Task { await model.confirmDelete() } }
        } message: {
            Text(deleteMessage(model.pendingDelete))
        }
        .accessibilityIdentifier("folderDetail.\(model.folderID)")
    }
}

/// Confirmation copy for deleting a non-empty folder.
func deleteMessage(_ pending: PendingFolderDelete?) -> String {
    guard let pending else { return "" }
    let n = pending.itemCount
    return "Delete \"\(pending.folder.name)\" and the \(n) item\(n == 1 ? "" : "s") inside it? This can't be undone."
}
