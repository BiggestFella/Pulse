import SwiftUI

struct RoutineBuilderView: View {
    @State private var model: RoutineBuilderModel
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    init(model: RoutineBuilderModel) { _model = State(initialValue: model) }

    private let dowLetters = ["M", "T", "W", "T", "F", "S", "S"]
    private let dowNames = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    var body: some View {
        BuilderScaffold(
            eyebrow: "NEW ROUTINE", primaryLabel: "Save routine →",
            saving: model.saveState == .saving,
            onCancel: { dismiss() },
            onPrimary: { Task { await model.save() } }
        ) {
            VStack(alignment: .leading, spacing: theme.spacing[4]) {
                TextField("Routine name", text: $model.name)
                    .font(.system(size: 30, weight: .bold)).foregroundStyle(theme.ink)
                    .accessibilityIdentifier("routine-name")

                StatLabel("PROGRAM LENGTH")
                HStack(spacing: theme.spacing[3]) {
                    Button { model.decWeeks() } label: { Image(systemName: "minus") }
                        .buttonStyle(IconButtonStyle())
                        .accessibilityIdentifier("weeks-dec")
                    Text("\(model.weeks)wks")
                        .font(PulseFont.oswald("Oswald-Bold", size: 26))
                        .foregroundStyle(theme.ink)
                        .accessibilityIdentifier("weeks-value")
                    Button { model.incWeeks() } label: { Image(systemName: "plus") }
                        .buttonStyle(IconButtonStyle())
                        .accessibilityIdentifier("weeks-inc")
                }

                HStack {
                    StatLabel("WEEKLY SPLIT")
                    Spacer()
                    StatLabel("\(model.workoutsPerWeek) WORKOUTS / WK")
                        .accessibilityIdentifier("eyebrow-\(model.workoutsPerWeek) WORKOUTS / WK")
                }

                dayList

                Button { model.pickerPresented = true } label: {
                    Text("+ ADD / CREATE WORKOUT")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity).padding(theme.spacing[4])
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6])))
                }
                .accessibilityIdentifier("add-workout")

                Button { model.addRestDay() } label: {
                    Text("+ Add rest day")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.inkSoft)
                        .frame(maxWidth: .infinity).padding(theme.spacing[3])
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(theme.inkFaint, style: StrokeStyle(lineWidth: 2, dash: [4])))
                }
                .accessibilityIdentifier("add-rest")

                if case let .error(msg) = model.saveState {
                    Text(msg).foregroundStyle(theme.accent2).accessibilityIdentifier("save-error")
                }
            }
            .padding(.vertical, theme.spacing[3])
        }
        .sheet(isPresented: $model.pickerPresented) {
            WorkoutPickerSheet(
                saved: model.savedWorkouts, loading: model.savedLoading, errorText: model.savedError,
                onRetry: { Task { await model.loadSavedWorkouts() } },
                onCreateNew: {
                    model.addWorkout(BuilderDay(name: "New workout", sub: "Build from scratch"))
                    model.pickerPresented = false
                },
                onPick: { w in
                    let n = w.exercises.count
                    model.addWorkout(BuilderDay(name: w.name,
                                                sub: "\(n) exercise\(n == 1 ? "" : "s")",
                                                sourceWorkoutID: w.id))
                    model.pickerPresented = false
                })
            .environment(theme)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .task { if model.savedWorkouts.isEmpty { await model.loadSavedWorkouts() } }
        }
        .onChange(of: model.saveState) { _, new in if new == .saved { dismiss() } }
    }

    private var dayList: some View {
        VStack(spacing: theme.spacing[2]) {
            ForEach(Array(model.days.enumerated()), id: \.element.id) { idx, day in
                HStack(spacing: theme.spacing[2]) {
                    BuilderBadge(text: idx < dowLetters.count ? dowLetters[idx] : "D", tinted: false)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.name).foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                        Text("\(dow(idx)) · \(day.sub)").foregroundStyle(theme.inkSoft).font(.system(size: 13))
                    }
                    Spacer()
                    Button { model.removeDay(id: day.id) } label: { Image(systemName: "xmark") }
                        .foregroundStyle(theme.inkSoft)
                        .accessibilityIdentifier("remove-day-\(idx)")
                }
                .padding(theme.spacing[3])
                .opacity(day.isRest ? 0.55 : 1)
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(theme.inkFaint, style: StrokeStyle(lineWidth: day.isRest ? 2 : 1,
                                                               dash: day.isRest ? [4] : [])))
            }
        }
    }

    private func dow(_ idx: Int) -> String {
        idx < dowNames.count ? dowNames[idx] : "DAY \(idx + 1)"
    }
}

#Preview {
    let theme = Theme()
    return NavigationStack {
        RoutineBuilderView(model: RoutineBuilderModel(
            routines: InMemoryProgramRepository(store: MockStore()),
            workouts: InMemoryWorkoutRepository(store: MockStore())))
    }
    .environment(theme)
}
