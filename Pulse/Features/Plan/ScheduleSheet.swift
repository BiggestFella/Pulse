import SwiftUI

/// Body content of the Schedule drawer. The chrome (drag handle, eyebrow,
/// title, ✕) is supplied by `pulseSheet` in `PlanView`. Content varies by the
/// day's state (AC-8..10).
struct ScheduleSheet: View {
    @Environment(Theme.self) private var theme
    let model: PlanModel
    let day: Int

    private var entry: ScheduledDay {
        model.schedule[day] ?? ScheduledDay(state: .empty, workoutName: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            switch entry.state {
            case .done:        doneContent
            case .plan, .today: scheduledContent
            case .empty:       emptyContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)   // keep pick/rest rows addressable (BAK-25)
        .accessibilityIdentifier("plan.scheduleSheet")
    }

    // AC-8: read-only, no edit actions.
    private var doneContent: some View {
        assignedRow(name: entry.workoutName ?? "Workout", tag: "DONE", border: theme.accent)
    }

    // AC-9: assigned row + CLEAR + REPLACE WITH list + rest option.
    private var scheduledContent: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            assignedRow(name: entry.workoutName ?? "Workout", tag: "PLANNED", border: theme.accent2)
            Button("CLEAR") { Task { await model.clear(day: day) } }
                .buttonStyle(PressableButtonStyle(variant: .secondary, size: .sm))
                .accessibilityIdentifier("plan.sheet.clear")
            Text("REPLACE WITH").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
            pickerList
        }
    }

    // AC-10: PICK A WORKOUT list + rest option.
    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("PICK A WORKOUT").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
            pickerList
        }
    }

    private var pickerList: some View {
        VStack(spacing: theme.spacing[2]) {
            ForEach(model.savedWorkouts) { w in
                pickRow(name: w.name, sub: w.sub, dashed: false) {
                    Task { await model.assign(day: day, workout: w) }
                }
                .accessibilityIdentifier("plan.sheet.pick.\(w.id.uuidString)")
            }
            pickRow(name: "Rest day", sub: "RECOVERY", dashed: true) {
                Task { await model.assignRestDay(day) }
            }
            .accessibilityIdentifier("plan.sheet.rest")
        }
    }

    private func assignedRow(name: String, tag: String, border: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).pulseStyle(.rowName).foregroundStyle(theme.ink)
                Text(tag).pulseStyle(.rowSub).foregroundStyle(theme.inkSoft)
            }
            Spacer()
        }
        .padding(theme.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 2))
    }

    private func pickRow(name: String, sub: String, dashed: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).pulseStyle(.rowName).foregroundStyle(theme.ink)
                    Text(sub).pulseStyle(.rowSub).foregroundStyle(theme.inkSoft)
                }
                Spacer()
                Image(systemName: "plus").foregroundStyle(theme.accent)
            }
            .padding(theme.spacing[3])
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(dashed ? theme.inkFaint : theme.accent,
                                  style: StrokeStyle(lineWidth: dashed ? 1 : 2,
                                                     dash: dashed ? [4, 4] : []))
            )
            .contentShape(Rectangle())   // full-row hit target (same fix as the exercise picker, BAK-26/25)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    let theme = Theme()
    let model = PlanModel(schedule: InMemoryScheduleRepository(store: MockStore()),
                          workouts: InMemoryWorkoutRepository(store: MockStore()))
    return ScheduleSheet(model: model, day: 15)
        .padding(theme.spacing[5])
        .background(theme.bg)
        .environment(theme)
        .task { await model.load() }
}
