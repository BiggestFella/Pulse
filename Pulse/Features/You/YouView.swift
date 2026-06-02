import SwiftUI

struct YouView: View {
    @Environment(Theme.self) private var theme
    @Environment(RepositoryContainer.self) private var repos
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PaletteView()

                    VStack(alignment: .leading, spacing: 10) {
                        StatLabel("YOUR DATA")
                        NavigationLink {
                            StatsView(repository: repos.stats)
                        } label: {
                            HStack {
                                Text("Stats").foregroundStyle(theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(theme.inkSoft)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
                        }
                        .accessibilityIdentifier("you.stats")
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.bg)
            .navigationTitle("You")
        }
    }
}

#Preview {
    YouView()
        .environment(Theme())
        .environment(RepositoryContainer(useMock: true))
}
