import SwiftUI

/// Placeholder destination for the Workout History NavRow. The real History
/// screen + session detail are owned by a separate backlog item (BAK-17); this
/// stub makes the You tab's "Workout history" push real and testable today.
struct WorkoutHistoryPlaceholderView: View {
    @Environment(Theme.self) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            VStack(spacing: theme.spacing[2]) {
                Text("Workout History")
                    .font(PulseFont.oswald("Oswald-Bold", size: 28))
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("destination-history")
                Text("COMING SOON")
                    .pulseStyle(.eyebrow)
                    .foregroundStyle(theme.inkSoft)
            }
        }
        .navigationTitle("Workout History")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        WorkoutHistoryPlaceholderView().environment(Theme())
    }
}
