import SwiftUI

struct RestView: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let remaining = model.remainingRest(now: context.date)
            content(remaining: remaining)
                .onChange(of: remaining <= 0) { _, done in
                    if done { model.afterRest() }
                }
        }
    }

    @ViewBuilder
    private func content(remaining: TimeInterval) -> some View {
        let total = model.restTotal
        let pct = total > 0 ? remaining / total : 0
        VStack(spacing: theme.spacing[3]) {
            HStack {
                Text("REST · BREATHE")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.inkSoft)
                Spacer()
                Button { model.afterRest() } label: { Image(systemName: "chevron.right").foregroundStyle(theme.ink) }
                    .accessibilityIdentifier("rest.forward")
            }
            Spacer()
            ZStack {
                Circle().stroke(theme.inkFaint, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: pct)
                    .stroke(theme.accent2, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: pct)
                VStack {
                    Text(timeString(remaining))
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(theme.accent2)
                        .accessibilityIdentifier("rest.time")
                    Text("OF 1:30")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(theme.inkSoft)
                }
            }
            .frame(width: 220, height: 220)
            Spacer()
            HStack(spacing: 6) {
                adjustChip("−15", -15)
                adjustChip("+15", 15)
                adjustChip("+30", 30)
            }
            if let next = model.nextStep { upNextCard(next) }
            Button("Skip rest →") { model.afterRest() }
                .buttonStyle(PressableButtonStyle(variant: .primary, size: .lg))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("rest.skip")
        }
        .padding(theme.spacing[5])
    }

    private func adjustChip(_ label: String, _ delta: TimeInterval) -> some View {
        Button("\(label)s") { model.adjustRest(delta) }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(theme.ink)
            .padding(.vertical, 6).padding(.horizontal, 14)
            .overlay(Capsule().strokeBorder(theme.inkFaint, lineWidth: 1.5))
            .accessibilityIdentifier("rest.adjust.\(Int(delta))")
    }

    private func upNextCard(_ next: WorkoutStep) -> some View {
        let ex = model.workout.exercises[next.exIdx]
        let set = ex.sets.indices.contains(next.setIdx) ? ex.sets[next.setIdx] : nil
        return HStack(spacing: 12) {
            Text("\(next.setIdx + 1)")
                .font(.headline.bold()).foregroundStyle(theme.onAccent)
                .frame(width: 36, height: 36)
                .background(theme.accent, in: Circle())
            VStack(alignment: .leading) {
                Text("UP NEXT" + (next.ssLabel(in: model.workout).map { " · \($0)" } ?? ""))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.inkSoft)
                Text(model.displayName(forExercise: next.exIdx))
                    .font(.subheadline.bold()).foregroundStyle(theme.ink)
            }
            Spacer()
            Text(set?.type == .failure ? "∞" : "\(set?.reps ?? 0)")
                .font(.title.bold()).foregroundStyle(theme.accent)
        }
        .padding(theme.spacing[2])
        .overlay(RoundedRectangle(cornerRadius: theme.radiusCard).strokeBorder(theme.accent, lineWidth: 2))
        .accessibilityIdentifier("rest.upNext")
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded()); return String(format: "%d:%02d", s / 60, s % 60)
    }
}

#Preview {
    let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                               historyRepo: MockHistoryRepository(),
                               sessionWriter: MockSessionWriter())
    m.startWorkout(ActiveWorkoutSample.workout); m.beginSets(); m.logSet(reps: 15, weight: 40)
    return RestView(model: m).environment(Theme())
}
