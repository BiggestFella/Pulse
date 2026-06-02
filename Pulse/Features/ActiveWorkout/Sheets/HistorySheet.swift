import SwiftUI

struct HistorySheet: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme
    @State private var sets: [SessionSet] = []

    private var exIdx: Int { model.currentStep.exIdx }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Text("RECENT")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            Text(model.displayName(forExercise: exIdx))
                .font(.title3.bold()).foregroundStyle(theme.ink)
            ForEach(Array(sets.enumerated()), id: \.offset) { _, s in
                HStack {
                    Text("\(s.reps) reps").foregroundStyle(theme.ink)
                    Spacer()
                    Text(WeightFormat.kg(s.weight))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.inkSoft)
                }
                .padding(theme.spacing[2])
                .frame(maxWidth: .infinity)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
            }
            Spacer()
        }
        .padding(theme.spacing[5])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .task { sets = await model.history(for: exIdx) }
    }
}
