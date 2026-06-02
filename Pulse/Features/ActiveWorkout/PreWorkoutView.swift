import SwiftUI

struct PreWorkoutView: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            HStack {
                Button(action: { model.endWorkout() }) {
                    Image(systemName: "chevron.left").foregroundStyle(theme.ink)
                }
                .accessibilityIdentifier("pre.back")
                Spacer()
            }

            Text("READY")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            Text(model.workout.name + ".")
                .font(.largeTitle.bold())
                .foregroundStyle(theme.ink)

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing[1]) {
                    ForEach(Array(model.workout.exercises.enumerated()), id: \.offset) { _, ex in
                        HStack {
                            Text(ex.exercise.name).foregroundStyle(theme.ink)
                            Spacer()
                            Text("\(ex.sets.count) sets")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(theme.inkSoft)
                        }
                        .padding(theme.spacing[2])
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
                    }
                }
            }

            Spacer()
            Button("Begin") { model.beginSets() }
                .buttonStyle(PressableButtonStyle(variant: .primary, size: .lg))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("pre.begin")
        }
        .padding(theme.spacing[5])
    }
}

#Preview {
    let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                               historyRepo: MockHistoryRepository(),
                               sessionWriter: MockSessionWriter())
    m.startWorkout(ActiveWorkoutSample.workout)
    return PreWorkoutView(model: m).environment(Theme())
}
