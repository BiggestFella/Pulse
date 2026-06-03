import SwiftUI

struct PlanView: View {
    @Environment(Theme.self) private var theme
    @Environment(RepositoryContainer.self) private var repos
    @State private var model: PlanModel?
    var onStartWorkout: () -> Void = {}

    var body: some View {
        Group {
            if let model {
                screen(model)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("plan.loading")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.bg.ignoresSafeArea())
        .task {
            guard model == nil else { return }
            let m = PlanModel(schedule: repos.schedule, workouts: repos.workouts)
            m.onStartWorkout = onStartWorkout
            model = m
            await m.load()
        }
    }

    @ViewBuilder
    private func screen(_ model: PlanModel) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing[4]) {
            Text("PLAN").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
                .padding(.horizontal, theme.spacing[5])
                .padding(.top, theme.spacing[4])
            toggle(model)
            ScrollView { body(model) }
        }
        .pulseSheet(isPresented: sheetBinding(model),
                    eyebrow: model.sheetEyebrow(for: model.scheduleSheetDay ?? 1),
                    title: model.sheetTitle(for: model.scheduleSheetDay ?? 1)) {
            if let day = model.scheduleSheetDay {
                ScheduleSheet(model: model, day: day)
            }
        }
    }

    private func sheetBinding(_ model: PlanModel) -> Binding<Bool> {
        Binding(get: { model.scheduleSheetDay != nil },
                set: { if !$0 { model.scheduleSheetDay = nil } })
    }

    @ViewBuilder
    private func toggle(_ model: PlanModel) -> some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            segment("Calendar", isOn: model.mode == .calendar) { model.mode = .calendar }
            segment("Agenda", isOn: model.mode == .agenda) { model.mode = .agenda }
        }
        .padding(3)
        .background(theme.surface, in: Capsule())
        .overlay(Capsule().stroke(theme.inkFaint, lineWidth: 1))
        .padding(.horizontal, theme.spacing[5])
        .accessibilityIdentifier("plan.toggle")
    }

    private func segment(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased()).pulseStyle(.rowSub)
                .foregroundStyle(isOn ? theme.bg : theme.inkSoft)
                .frame(maxWidth: .infinity)
                .padding(.vertical, theme.spacing[2])
                .background(isOn ? theme.ink : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("plan.toggle.\(label.lowercased())")
    }

    @ViewBuilder
    private func body(_ model: PlanModel) -> some View {
        switch model.loadState {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                .accessibilityIdentifier("plan.loading")
        case .failed:
            VStack(spacing: theme.spacing[3]) {
                Text("Couldn't load your schedule.").pulseStyle(.rowName).foregroundStyle(theme.ink)
                Button("RETRY") { Task { await model.load() } }
                    .buttonStyle(PressableButtonStyle(variant: .secondary, size: .sm))
                    .accessibilityIdentifier("plan.retry")
            }
            .frame(maxWidth: .infinity, minHeight: 240)
            .accessibilityIdentifier("plan.error")
        case .loaded:
            if model.mode == .calendar {
                CalendarMonthView(model: model)
            } else {
                AgendaListView(model: model)
            }
        }
    }
}

#Preview {
    PlanView()
        .environment(Theme())
        .environment(RepositoryContainer(useMock: true))
}
