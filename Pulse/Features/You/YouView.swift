import SwiftUI

struct YouView: View {
    @Environment(Theme.self) private var theme
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PaletteView()
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.bg)
            .navigationTitle("You")
        }
    }
}

#Preview { YouView().environment(Theme()) }
