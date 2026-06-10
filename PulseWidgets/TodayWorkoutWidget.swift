import SwiftUI
import WidgetKit

/// The static "Today's Workout" widget (BAK-19): today's workout, week strip, and
/// streak across five families, rendered from the shared snapshot in the user's
/// palette, deep-linking back into the app. Live Activity is registered separately.
struct TodayWorkoutWidget: Widget {
    private let kind = "TodayWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PulseProvider()) { entry in
            TodayWorkoutWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Today's Workout")
        .description("Today's workout, week progress, and streak.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryRectangular, .accessoryCircular])
    }
}

struct TodayWorkoutWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot
    private var theme: WidgetTheme { WidgetTheme(palette: Palette(rawValue: snapshot.palette) ?? .default) }

    var body: some View {
        content.widgetURL(URL(string: snapshot.startRoute))
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .systemSmall:           SmallWidgetView(snapshot: snapshot, theme: theme)
        case .systemMedium:          MediumWidgetView(snapshot: snapshot, theme: theme)
        case .systemLarge:           LargeWidgetView(snapshot: snapshot, theme: theme)
        case .accessoryRectangular:  AccessoryRectangularView(snapshot: snapshot)
        case .accessoryCircular:     AccessoryCircularView(snapshot: snapshot)
        default:                     SmallWidgetView(snapshot: snapshot, theme: theme)
        }
    }
}

// MARK: - Home Screen families (accent fill; highlight text uses onAccent, never accent2)

/// Eyebrow + exercise numeral + workout name, or the rest treatment.
private struct WorkoutLockup: View {
    let snapshot: WidgetSnapshot
    let theme: WidgetTheme
    var numeralSize: CGFloat = 40
    var nameSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.isRestDay ? "REST DAY" : "TODAY · \(snapshot.programLabel ?? "")")
                .font(.laLabel(10))
                .foregroundStyle(theme.onAccent.opacity(0.85))
            Spacer(minLength: 4)
            if snapshot.isRestDay {
                Text("Recover.").font(.laName(nameSize)).foregroundStyle(theme.onAccent)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(snapshot.exerciseCount ?? 0)")
                        .font(.laNumeral(numeralSize)).foregroundStyle(theme.onAccent)
                    Text("EXERCISES")
                        .font(.laLabel(9)).foregroundStyle(theme.onAccent.opacity(0.85))
                }
                Text(snapshot.todayWorkoutName ?? "")
                    .font(.laName(nameSize)).foregroundStyle(theme.onAccent).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 7-cell week strip in onAccent emphasis (no accent2 on the accent fill).
private struct WeekStripMini: View {
    let week: [WeekCellSnapshot]
    let theme: WidgetTheme

    var body: some View {
        HStack(spacing: 5) {
            ForEach(Array(week.enumerated()), id: \.offset) { _, cell in
                VStack(spacing: 3) {
                    Text(cell.dayLetter).font(.laLabel(9)).foregroundStyle(theme.onAccent.opacity(0.7))
                    marker(cell.state)
                }
            }
        }
    }

    @ViewBuilder private func marker(_ state: String) -> some View {
        switch state {
        case "done":  Circle().fill(theme.onAccent).frame(width: 8, height: 8)
        case "today": Circle().strokeBorder(theme.onAccent, lineWidth: 2).frame(width: 8, height: 8)
        case "plan":  Circle().fill(theme.onAccent.opacity(0.35)).frame(width: 8, height: 8)
        default:      Circle().strokeBorder(theme.onAccent.opacity(0.3), lineWidth: 1).frame(width: 8, height: 8)
        }
    }
}

private struct StreakNumeral: View {
    let streak: Int
    let theme: WidgetTheme
    var size: CGFloat = 22
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text("\(streak)").font(.laNumeral(size)).foregroundStyle(theme.onAccent)
            Text("D").font(.laLabel(10)).foregroundStyle(theme.onAccent.opacity(0.8))
        }
    }
}

private struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot
    let theme: WidgetTheme
    var body: some View {
        WorkoutLockup(snapshot: snapshot, theme: theme)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(theme.accent, for: .widget)
    }
}

private struct MediumWidgetView: View {
    let snapshot: WidgetSnapshot
    let theme: WidgetTheme
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            WorkoutLockup(snapshot: snapshot, theme: theme)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 10) {
                StreakNumeral(streak: snapshot.streak, theme: theme)
                WeekStripMini(week: snapshot.week, theme: theme)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(theme.accent, for: .widget)
    }
}

private struct LargeWidgetView: View {
    let snapshot: WidgetSnapshot
    let theme: WidgetTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WorkoutLockup(snapshot: snapshot, theme: theme, numeralSize: 64, nameSize: 20)
            if let day = snapshot.dayLabel {
                Text(day.uppercased()).font(.laLabel(10)).foregroundStyle(theme.onAccent.opacity(0.85))
            }
            Spacer(minLength: 4)
            HStack(alignment: .bottom) {
                WeekStripMini(week: snapshot.week, theme: theme)
                Spacer()
                StreakNumeral(streak: snapshot.streak, theme: theme, size: 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .containerBackground(theme.accent, for: .widget)
    }
}

// MARK: - Lock Screen families (system monochrome; no token fills)

private struct AccessoryRectangularView: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.isRestDay ? "REST DAY" : "TODAY · \(snapshot.programLabel ?? "")")
                .font(.headline).widgetAccentable()
            Text(snapshot.isRestDay
                 ? "Recover."
                 : "\(snapshot.todayWorkoutName ?? "") · \(snapshot.exerciseCount ?? 0) EX")
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }
}

private struct AccessoryCircularView: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        let planned = max(snapshot.plannedCount, 1)   // guard all-rest divide-by-zero
        Gauge(value: Double(snapshot.doneCount), in: 0...Double(planned)) {
            Text("WK")
        } currentValueLabel: {
            Text("\(snapshot.doneCount)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .containerBackground(.clear, for: .widget)
    }
}
