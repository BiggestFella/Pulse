import SwiftUI

struct SummaryView: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    var body: some View {
        let s = model.summary
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("WORKOUT COMPLETE · \(dateString)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            Text(model.workout.name + ".")
                .font(.largeTitle.bold()).foregroundStyle(theme.ink)
            Text("Day \(model.workout.order + 1) · program")
                .font(.subheadline).foregroundStyle(theme.inkSoft)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                statBox("VOLUME", value: volumeK(s.totalVolume), sub: "kg total")
                statBox("TIME", value: "\(s.elapsedMinutes)", sub: "min elapsed")
                statBox("SETS", value: "\(s.completedSets)/\(s.totalSets)", sub: "complete", dim: true)
                statBox("PR", value: "+\(s.prCount)", sub: "this session", accent: true)
            }

            Text("LOG")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(theme.inkSoft)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.logRows) { row in
                        HStack {
                            Text("\(row.id + 1)").font(.caption.bold()).foregroundStyle(theme.ink)
                                .frame(width: 20, height: 20)
                                .background(theme.surface2, in: Circle())
                            VStack(alignment: .leading) {
                                Text(row.name).font(.subheadline).foregroundStyle(theme.ink)
                                Text(row.summaryLine).font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(theme.inkSoft)
                            }
                            Spacer()
                            if row.isPR { Text("PR").font(.caption2.bold()).foregroundStyle(theme.accent2) }
                            Text(volumeK(row.volume)).foregroundStyle(theme.ink)
                        }
                        .padding(theme.spacing[2])
                        .frame(maxWidth: .infinity)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Edit log") { }   // destination deferred per spec; inert v1
                    .buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
                Button("Done →") { Task { await model.finishAndSave() } }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("summary.done")
            }
        }
        .padding(theme.spacing[5])
    }

    private func statBox(_ label: String, value: String, sub: String,
                         dim: Bool = false, accent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(.caption2, design: .monospaced)).foregroundStyle(theme.inkSoft)
            Text(value).font(.title.bold())
                .foregroundStyle(dim ? theme.inkSoft : theme.ink)
            Text(sub).font(.caption2).foregroundStyle(theme.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing[2])
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: theme.radiusCard)
            .strokeBorder(accent ? theme.accent2 : .clear, lineWidth: 2))
    }

    private func volumeK(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v / 1000) : String(Int(v))
    }
    private var dateString: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d"; return f.string(from: .now).uppercased()
    }
}

#Preview {
    let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                               historyRepo: MockHistoryRepository(),
                               sessionWriter: MockSessionWriter())
    m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
    m.logSet(reps: 12, weight: 100); m.afterRest(); m.logSet(reps: 10, weight: 110)
    return SummaryView(model: m).environment(Theme())
}
