import SwiftUI

/// Read-only detail for a saved workout, with a Start button that launches the
/// active session. Per-workout settings (schedule, targets, rest, …) live in the
/// gear sheet (`WorkoutSettingsSheet`).
struct WorkoutDetailView: View {
    @State private var model: WorkoutDetailModel
    private let onEdit: (Workout.ID) -> Void
    private let settingsModel: () -> WorkoutSettingsModel
    @State private var showSettings = false
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    init(model: WorkoutDetailModel,
         onEdit: @escaping (Workout.ID) -> Void = { _ in },
         settingsModel: @escaping () -> WorkoutSettingsModel) {
        _model = State(initialValue: model)
        self.onEdit = onEdit
        self.settingsModel = settingsModel
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.title)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("workoutDetail.title")
                    .padding(.top, 8)

                content.padding(.top, 14)
            }
            .padding(.horizontal, 18).padding(.top, 8)
            .padding(.bottom, 96)   // room for the sticky Start button
        }
        .background(theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { startBar }
        .task { await model.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityIdentifier("workoutDetail.settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { onEdit(model.workoutID) }
                    .accessibilityIdentifier("workoutDetail.edit")
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: { Task { await model.load() } }) {
            WorkoutSettingsSheet(model: settingsModel(), title: model.title,
                                 onDeleted: { dismiss() })
                .environment(theme).presentationDetents([.large])
        }
    }

    @ViewBuilder private var content: some View {
        switch model.loadState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                .accessibilityIdentifier("workoutDetail.loading")
        case .error:
            Text("Couldn't load this workout.")
                .font(.system(size: 15)).foregroundStyle(theme.inkSoft)
                .frame(maxWidth: .infinity).padding(.top, 40)
                .accessibilityIdentifier("workoutDetail.error")
        case .loaded:
            VStack(alignment: .leading, spacing: 6) {
                StatLabel("EXERCISES · \(model.rows.count)")
                ForEach(model.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.variationName.isEmpty ? row.exerciseName
                                                        : "\(row.exerciseName) · \(row.variationName)")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.ink)
                        Text(row.setSummary)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.inkSoft)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12).padding(.horizontal, 14)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.inkFaint, lineWidth: 1.5))
                    .accessibilityIdentifier("workoutDetail.row.\(row.exerciseName)")
                }
            }
        }
    }

    @ViewBuilder private var startBar: some View {
        VStack(spacing: 4) {
            Button { model.start() } label: {
                Text("Start workout").frame(maxWidth: .infinity)
            }
            .buttonStyle(PressableButtonStyle(variant: .primary, size: .lg))
            .disabled(!model.canStart)
            .accessibilityIdentifier("workoutDetail.start")

            if model.loadState == .loaded && !model.canStart {
                Text("This workout has no exercises yet.")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(theme.inkSoft)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
