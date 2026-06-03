import SwiftUI

/// Routine-builder workout picker: a pinned `Create new workout` card over a
/// scrollable `FROM YOUR LIBRARY` list of saved workouts. Picking either appends
/// a day to the routine and dismisses.
struct WorkoutPickerSheet: View {
    let saved: [Workout]
    let loading: Bool
    let errorText: String?
    let onRetry: () -> Void
    let onCreateNew: () -> Void
    let onPick: (Workout) -> Void
    @Environment(Theme.self) private var theme

    private func sub(for workout: Workout) -> String {
        let n = workout.exercises.count
        return "\(n) exercise\(n == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet,
                                   topTrailingRadius: theme.radiusSheet)
                .stroke(theme.ink, lineWidth: 2)
                .ignoresSafeArea(edges: .bottom)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet,
                                          topTrailingRadius: theme.radiusSheet))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Capsule().fill(theme.inkFaint).frame(width: 42, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 12)
            StatLabel("ADD TO ROUTINE").accessibilityIdentifier("eyebrow-ADD TO ROUTINE")
            Text("Add a workout.").pulseStyle(.h1).foregroundStyle(theme.ink)

            Button(action: onCreateNew) {
                HStack {
                    Image(systemName: "plus")
                        .foregroundStyle(theme.accent)
                        .frame(width: 40, height: 40)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.accent, lineWidth: 2))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create new workout").foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                        Text("Build from scratch").foregroundStyle(theme.inkSoft).font(.system(size: 13))
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(theme.accent)
                }
                .padding(theme.spacing[3])
                .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.accent, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("wpicker-create-new")
        }
        .padding(.horizontal, theme.spacing[5])
        .padding(.bottom, theme.spacing[3])
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("wpicker-loading")
        } else if let errorText {
            VStack(spacing: theme.spacing[3]) {
                Text(errorText).foregroundStyle(theme.inkSoft)
                Button("Retry", action: onRetry).accessibilityIdentifier("wpicker-retry")
            }
            .frame(maxWidth: .infinity, minHeight: 120)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing[2]) {
                    StatLabel("FROM YOUR LIBRARY")
                    ForEach(saved) { w in
                        Button { onPick(w) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(w.name).foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                                    Text(sub(for: w)).foregroundStyle(theme.inkSoft).font(.system(size: 13))
                                }
                                Spacer()
                                Image(systemName: "plus").foregroundStyle(theme.accent)
                            }
                            .padding(theme.spacing[3])
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.inkFaint, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("wpicker-row-\(w.name)")
                    }
                }
                .padding(.horizontal, theme.spacing[5])
                .padding(.bottom, theme.spacing[5])
            }
            .scrollIndicators(.hidden)
        }
    }
}

#Preview {
    let theme = Theme()
    return WorkoutPickerSheet(saved: SampleData.program.workouts, loading: false, errorText: nil,
                              onRetry: {}, onCreateNew: {}, onPick: { _ in })
        .environment(theme)
}
