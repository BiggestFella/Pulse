import SwiftUI

struct AgendaListView: View {
    @Environment(Theme.self) private var theme
    let model: PlanModel

    var body: some View {
        VStack(spacing: theme.spacing[4]) {
            ForEach(model.agenda) { entry in
                row(entry)
                    .accessibilityIdentifier("plan.agenda.\(entry.day)")
            }
        }
        .padding(.horizontal, theme.spacing[5])
        .accessibilityIdentifier("plan.agenda")
    }

    @ViewBuilder
    private func row(_ entry: AgendaEntry) -> some View {
        let interactive = entry.isToday
        HStack(alignment: .top, spacing: theme.spacing[3]) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.dow).pulseStyle(.eyebrow)
                    .foregroundStyle(entry.isToday ? theme.accent2 : theme.inkSoft)
                Text("\(entry.day)")
                    .pulseStyle(.statNumeral)
                    .foregroundStyle(numberColor(entry))
                    .scaleEffect(entry.isToday ? 1.0 : 0.82, anchor: .leading)
            }
            .frame(width: 64, alignment: .leading)

            workoutRow(entry)
        }
        .opacity(entry.isRest || entry.name == nil ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if interactive { model.onStartWorkout() } }
    }

    private func numberColor(_ entry: AgendaEntry) -> Color {
        if entry.isToday { return theme.accent }
        if entry.isRest || entry.name == nil { return theme.inkSoft }
        return theme.ink
    }

    @ViewBuilder
    private func workoutRow(_ entry: AgendaEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name ?? "Unscheduled").pulseStyle(.rowName).foregroundStyle(theme.ink)
                if let sub = entry.sub {
                    Text(sub).pulseStyle(.rowSub).foregroundStyle(theme.inkSoft)
                }
            }
            Spacer()
            if entry.isToday {
                Text("→").pulseStyle(.rowName).foregroundStyle(theme.accent)
            } else if entry.name != nil && !entry.isRest {
                Image(systemName: "chevron.right").foregroundStyle(theme.inkSoft)
            }
        }
        .padding(theme.spacing[3])
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(entry.isToday ? theme.accent : theme.inkFaint,
                        lineWidth: entry.isToday ? 2 : 1)
        )
    }
}

#Preview {
    let model = PlanModel(schedule: InMemoryScheduleRepository(store: MockStore()),
                          workouts: InMemoryWorkoutRepository(store: MockStore()))
    return ScrollView { AgendaListView(model: model) }
        .background(Theme().bg)
        .environment(Theme())
        .task { model.mode = .agenda; await model.load() }
}
