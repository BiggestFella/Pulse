import SwiftUI

struct LibraryView: View {
    @Environment(Theme.self) private var theme
    @Environment(RepositoryContainer.self) private var repos
    @State private var model: LibraryModel?
    @State private var path: [LibraryRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let model {
                    screen(model)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("library.loading")
                }
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationDestination(for: LibraryRoute.self) { route in
                routeStub(route)
            }
        }
        .task {
            guard model == nil else { return }
            let m = LibraryModel(library: MockLibraryRepository(),
                                 exerciseRepo: repos.exercises, prRepo: repos.prs)
            model = m
            await m.load()
        }
    }

    private func screen(_ model: LibraryModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                topBar(model)
                Text("Library.")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("library.h1")
                    .padding(.top, 4)
                searchField.padding(.top, 10)
                filterRow(model).padding(.top, 12)
                bodyContent(model).padding(.top, 14)
            }
            .padding(.horizontal, 18).padding(.top, 8)
        }
        .sheet(isPresented: Binding(get: { model.isCreateSheetPresented },
                                    set: { model.isCreateSheetPresented = $0 })) {
            CreateChooserSheet(
                onPick: { route in model.dismissCreate(); path.append(route) },
                onClose: { model.dismissCreate() })
                .presentationDetents([.height(360)])
                .environment(theme)
        }
    }

    private func topBar(_ model: LibraryModel) -> some View {
        HStack {
            StatLabel("LIBRARY")
            Spacer()
            Button { model.presentCreate() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(theme.inkFaint, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library.create")
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.inkSoft)
            Text("Search workouts, exercises…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.inkSoft)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.inkFaint, lineWidth: 1.5))
        .accessibilityIdentifier("library.search")
    }

    private func filterRow(_ model: LibraryModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LibraryFilter.allCases, id: \.self) { f in
                    FilterChip(label: f.label, isOn: model.selectedFilter == f) { model.select(f) }
                        .accessibilityIdentifier("chip.\(f.rawValue)")
                }
            }
        }
    }

    @ViewBuilder private func bodyContent(_ model: LibraryModel) -> some View {
        switch model.loadState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                .accessibilityIdentifier("library.loading")
        case .error:
            VStack(spacing: 12) {
                Text("Couldn't load your library.")
                    .font(.system(size: 15)).foregroundStyle(theme.inkSoft)
                Button("Retry") { Task { await model.retry() } }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .accessibilityIdentifier("library.retry")
            }
            .frame(maxWidth: .infinity).padding(.top, 40)
            .accessibilityIdentifier("library.error")
        case .loaded:
            if model.selectedFilter == .exercises {
                exercisesBody(model)
            } else {
                defaultBody(model)
            }
        }
    }

    @ViewBuilder private func defaultBody(_ model: LibraryModel) -> some View {
        if model.isAllEmpty {
            emptyState("Nothing here yet. Tap + to build your first workout.")
                .accessibilityIdentifier("library.empty")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                StatLabel("FOLDERS · \(model.folders.count)")
                ForEach(model.folders) { folder in
                    FolderRow(folder: folder) {
                        path.append(folder.isProgram
                            ? .programDetail(folderID: folder.id)
                            : .folderDetail(folderID: folder.id))
                    }
                }
                HStack {
                    StatLabel("RECENT")
                    Spacer()
                    StatLabel("BROWSE EXERCISES →")
                        .contentShape(Rectangle())
                        .onTapGesture { model.select(.exercises) }
                        .accessibilityIdentifier("library.browseExercises")
                }
                .padding(.top, 8)
                ForEach(model.recentWorkouts) { RecentRow(workout: $0) }
            }
        }
    }

    @ViewBuilder private func exercisesBody(_ model: LibraryModel) -> some View {
        if model.isCatalogEmpty {
            emptyState("No exercises in your catalog yet.")
                .accessibilityIdentifier("catalog.empty")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.catalog) { group in
                    StatLabel("\(group.muscle) · \(group.items.count)").padding(.top, 8)
                    ForEach(group.items) { ex in
                        CatalogRow(exercise: ex) { path.append(.exerciseDetail(id: ex.id)) }
                    }
                }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15)).foregroundStyle(theme.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.top, 40)
    }

    private func routeStub(_ route: LibraryRoute) -> some View {
        Text(route.marker)
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg.ignoresSafeArea())
            .accessibilityIdentifier("route.\(route.marker)")
    }
}

#Preview {
    LibraryView()
        .environment(Theme())
        .environment(RepositoryContainer(useMock: true))
}
