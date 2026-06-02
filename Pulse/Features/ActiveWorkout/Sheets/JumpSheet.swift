import SwiftUI

struct JumpSheet: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Text("JUMP TO EXERCISE")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            ScrollView {
                VStack(spacing: theme.spacing[1]) {
                    ForEach(model.workout.exercises.indices, id: \.self) { exIdx in
                        let steps = exerciseSteps(model.steps)[exIdx] ?? []
                        let done = steps.filter { model.doneSteps.contains($0) }.count
                        let glyph = done == steps.count ? "✓" : (exIdx == model.currentStep.exIdx ? "•" : "→")
                        Button { model.jump(toExerciseIndex: exIdx) } label: {
                            HStack {
                                Text(glyph).foregroundStyle(theme.accent2)
                                Text(model.displayName(forExercise: exIdx)).foregroundStyle(theme.ink)
                                Spacer()
                                Text("\(done)/\(steps.count)")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(theme.inkSoft)
                            }
                            .padding(theme.spacing[2])
                            .frame(maxWidth: .infinity)
                            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
                        }
                        .accessibilityIdentifier("jump.exercise.\(exIdx)")
                    }
                }
            }
        }
        .padding(theme.spacing[5])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
    }
}
