import SwiftUI

/// Header (THIS WEEK · <done> OF <planned> DONE) + 7 display-only day cells.
struct TodayWeekStrip: View {
    @Environment(Theme.self) private var theme
    let week: [WeekDayCell]
    let progressLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            HStack {
                Eyebrow("THIS WEEK")
                Spacer()
                Eyebrow(progressLabel)
            }
            HStack(spacing: theme.spacing[1]) {
                ForEach(week) { cell in WeekCell(cell: cell) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today.weekStrip")
    }
}

private struct WeekCell: View {
    @Environment(Theme.self) private var theme
    let cell: WeekDayCell

    var body: some View {
        Text(cell.dayLetter)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .aspectRatio(0.82, contentMode: .fit)
            .background(fill, in: RoundedRectangle(cornerRadius: 8))
            .overlay(border)
            .opacity(cell.state == .rest ? 0.5 : 1)
    }

    private var fill: Color { cell.state == .done ? theme.accent : .clear }
    private var textColor: Color { cell.state == .done ? theme.onAccent : theme.inkSoft }

    @ViewBuilder private var border: some View {
        switch cell.state {
        case .done:  RoundedRectangle(cornerRadius: 8).strokeBorder(theme.accent, lineWidth: 1.5)
        case .today: RoundedRectangle(cornerRadius: 8).strokeBorder(theme.accent2, lineWidth: 2)
        case .plan:  RoundedRectangle(cornerRadius: 8).strokeBorder(theme.inkFaint, lineWidth: 1.5)
        case .rest:  RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(theme.inkFaint,
                                      style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }
}

#Preview {
    @Previewable @State var theme = Theme()
    return TodayWeekStrip(week: TodaySnapshot.sampleWeek, progressLabel: "3 OF 5 DONE")
        .padding().background(theme.bg).environment(theme)
}
