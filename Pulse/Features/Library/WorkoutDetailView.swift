import SwiftUI

/// Read-only detail for a saved workout, with a Start button that launches the
/// active session. Weekday repeats editor and schedule-on-date live here.
struct WorkoutDetailView: View {
    @State private var model: WorkoutDetailModel
    private let onEdit: (Workout.ID) -> Void
    @State private var showScheduleSheet = false
    @State private var schedulePicked = Date()
    @Environment(Theme.self) private var theme

    init(model: WorkoutDetailModel, onEdit: @escaping (Workout.ID) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onEdit = onEdit
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
                Button("Edit") { onEdit(model.workoutID) }
                    .accessibilityIdentifier("workoutDetail.edit")
            }
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
                StatLabel("REPEATS ON")
                    .padding(.top, 4)
                let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(zip(1...7, dayLabels)), id: \.0) { day, label in
                            PillChip(
                                label: label,
                                selected: model.weekdays.contains(day),
                                fill: theme.accent,
                                onFill: theme.onAccent
                            ) {
                                Task { await model.toggleWeekday(day) }
                            }
                            .accessibilityIdentifier("repeat-day-\(day)")
                        }
                    }
                }
                .padding(.top, 2).padding(.bottom, 8)

                Button {
                    schedulePicked = Date()
                    showScheduleSheet = true
                } label: {
                    Text("Schedule on a date")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10).padding(.horizontal, 14)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.inkFaint, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workoutDetail.scheduleDate")
                .sheet(isPresented: $showScheduleSheet) {
                    NavigationStack {
                        DatePicker("Pick a date", selection: $schedulePicked, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .padding()
                            .navigationTitle("Schedule Workout")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("Cancel") { showScheduleSheet = false }
                                }
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Add") {
                                        showScheduleSheet = false
                                        Task { await model.scheduleOnDate(schedulePicked) }
                                    }
                                    .fontWeight(.semibold)
                                }
                            }
                    }
                    .presentationDetents([.medium, .large])
                    .environment(theme)
                }
                .padding(.bottom, 8)

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
