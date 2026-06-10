import Foundation

/// Pure timeline logic for the widget (BAK-19), kept out of the WidgetKit
/// extension so it's unit-testable from the app test target. `PulseProvider`
/// maps these into WidgetKit `TimelineEntry`s.
struct WidgetTimelineEntry: Equatable {
    let date: Date
    let snapshot: WidgetSnapshot
}

enum WidgetTimeline {
    /// A now-entry (snapshot as-is) plus a next-midnight entry whose snapshot is
    /// neutralised, so a workout never shows stale into a new day.
    static func entries(snapshot: WidgetSnapshot, now: Date,
                        calendar: Calendar = .current) -> [WidgetTimelineEntry] {
        var result = [WidgetTimelineEntry(date: now, snapshot: snapshot)]
        if let midnight = nextMidnight(after: now, calendar: calendar) {
            result.append(WidgetTimelineEntry(date: midnight, snapshot: snapshot.staleNeutralized()))
        }
        return result
    }

    /// When WidgetKit should request the next timeline — the upcoming midnight.
    static func nextRefresh(after now: Date, calendar: Calendar = .current) -> Date {
        nextMidnight(after: now, calendar: calendar) ?? now.addingTimeInterval(3600)
    }

    private static func nextMidnight(after now: Date, calendar: Calendar) -> Date? {
        calendar.nextDate(after: now,
                          matching: DateComponents(hour: 0, minute: 0, second: 0),
                          matchingPolicy: .nextTime)
    }
}
