import SwiftUI

struct CalendarMonthView: View {
    @Environment(Theme.self) private var theme
    let model: PlanModel

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[5]) {
            header
            summaryCard
            weekdayRow
            dayGrid
            todayRow
        }
        .padding(.horizontal, theme.spacing[5])
        .accessibilityIdentifier("plan.calendar")
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(model.month.title).pulseStyle(.h1).foregroundStyle(theme.ink)
            Spacer()
            Text(String(model.month.year)).pulseStyle(.statNumeral).foregroundStyle(theme.inkSoft)
        }
    }

    private var summaryCard: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: theme.spacing[0]) {
                Text("THIS MONTH").pulseStyle(.eyebrow).foregroundStyle(theme.onAccent.opacity(0.7))
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(model.summary.done)").pulseStyle(.statNumeral).foregroundStyle(theme.onAccent)
                    Text("/ \(model.summary.planned)").pulseStyle(.rowSub).foregroundStyle(theme.onAccent.opacity(0.7))
                }
            }
            Spacer()
            Text("\(model.summary.pct)%").pulseStyle(.statNumeral).foregroundStyle(theme.onAccent)
        }
        .padding(theme.spacing[5])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radiusCard))
        .overlay(RoundedRectangle(cornerRadius: theme.radiusCard).stroke(theme.ink, lineWidth: 2))
        .accessibilityIdentifier("plan.summaryCard")
    }

    private var weekdayRow: some View {
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                Text(d).pulseStyle(.rowSub).foregroundStyle(theme.inkSoft)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: cols, spacing: 6) {
            ForEach(0..<model.month.monthStartOffset, id: \.self) { _ in
                Color.clear.frame(height: 44)
            }
            ForEach(1...model.month.daysInMonth, id: \.self) { day in
                dayCell(day)
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectDay(day) }
                    .accessibilityIdentifier("plan.day.\(day)")
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let entry = model.schedule[day] ?? ScheduledDay(state: .empty, workoutName: nil)
        ZStack {
            cellBackground(entry)
            VStack(spacing: 3) {
                Text("\(day)")
                    .pulseStyle(.rowName)
                    .foregroundStyle(entry.state == .done ? theme.onAccent : theme.ink)
                dot(entry)
            }
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private func cellBackground(_ entry: ScheduledDay) -> some View {
        let r = RoundedRectangle(cornerRadius: 10)
        switch entry.state {
        case .done:
            r.fill(theme.accent)
        case .today:
            r.fill(theme.surface).overlay(r.stroke(theme.accent2, lineWidth: 2))
        case .plan:
            r.fill(theme.accent.opacity(0.14)).overlay(r.stroke(theme.accent2, lineWidth: 1))
        case .empty:
            r.fill(.clear)
                .overlay(
                    r.strokeBorder(theme.inkFaint,
                                   style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                )
                .opacity(entry.isRest ? 0.5 : 1)
        }
    }

    @ViewBuilder
    private func dot(_ entry: ScheduledDay) -> some View {
        switch entry.state {
        case .done:  Circle().fill(theme.onAccent).frame(width: 4, height: 4)
        case .today, .plan: Circle().fill(theme.accent2).frame(width: 4, height: 4)
        case .empty: Color.clear.frame(width: 4, height: 4)
        }
    }

    @ViewBuilder
    private var todayRow: some View {
        if let entry = model.agenda.first(where: { $0.isToday }), let name = entry.name {
            VStack(alignment: .leading, spacing: theme.spacing[1]) {
                Text("\(entry.dow) · \(model.month.monthAbbrevUpper) \(entry.day)")
                    .pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
                HStack(spacing: theme.spacing[2]) {
                    Text("T").pulseStyle(.rowSub).foregroundStyle(theme.onAccent)
                        .frame(width: 22, height: 22)
                        .background(theme.accent2, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).pulseStyle(.rowName).foregroundStyle(theme.ink)
                        if let sub = entry.sub {
                            Text(sub).pulseStyle(.rowSub).foregroundStyle(theme.inkSoft)
                        }
                    }
                    Spacer()
                    Text("→").pulseStyle(.rowName).foregroundStyle(theme.accent)
                }
                .padding(theme.spacing[3])
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.accent, lineWidth: 2))
                .contentShape(Rectangle())
                // Route through selectDay so a completed today opens the
                // read-only sheet instead of launching a workout (AC-? / review).
                .onTapGesture { model.selectDay(entry.day) }
                .accessibilityIdentifier("plan.todayRow")
            }
        }
    }
}

#Preview {
    let model = PlanModel(schedule: InMemoryScheduleRepository(store: MockStore()),
                          workouts: InMemoryWorkoutRepository(store: MockStore()))
    return ScrollView { CalendarMonthView(model: model) }
        .background(Theme().bg)
        .environment(Theme())
        .task { await model.load() }
}
