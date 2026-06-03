import Foundation

/// Pure calendar arithmetic for the Plan month grid. Monday-start week.
/// Callers pass an explicit `Calendar` (the model uses `Calendar.current`).
enum MonthMath {
    static func context(for date: Date, calendar: Calendar) -> MonthContext {
        var cal = calendar
        cal.firstWeekday = 2 // Monday

        let comps = cal.dateComponents([.year, .month], from: date)
        let first = cal.date(from: comps)!
        let daysInMonth = cal.range(of: .day, in: .month, for: first)!.count

        // weekday: 1=Sun ... 7=Sat. Convert to Monday-start 0...6.
        let weekday = cal.component(.weekday, from: first)
        let offset = (weekday + 5) % 7   // Mon->0, Tue->1, ... Sun->6

        let title = monthName(comps.month!) + "."
        let abbrev = monthAbbrev(comps.month!)

        return MonthContext(
            title: title,
            year: comps.year!,
            monthStartOffset: offset,
            daysInMonth: daysInMonth,
            monthAbbrevUpper: abbrev
        )
    }

    static func dowAbbrev(year: Int, month: Int, day: Int, calendar: Calendar) -> String {
        let d = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        let wd = calendar.component(.weekday, from: d) // 1=Sun
        let names = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
        return names[wd - 1]
    }

    private static func monthName(_ m: Int) -> String {
        ["January", "February", "March", "April", "May", "June",
         "July", "August", "September", "October", "November", "December"][m - 1]
    }

    private static func monthAbbrev(_ m: Int) -> String {
        ["JAN", "FEB", "MAR", "APR", "MAY", "JUN",
         "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"][m - 1]
    }
}
