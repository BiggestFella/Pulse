import Foundation
import WidgetKit

/// App-side writer that maps the Today projection (`TodaySnapshot`) into a
/// `WidgetSnapshot`, persists it to the shared App Group, and asks WidgetKit to
/// reload (BAK-19). The widget extension only ever reads; this is the single
/// write path. `reload` is injected so tests don't touch the WidgetKit runtime.
struct WidgetSnapshotWriter {
    private let store: WidgetSnapshotStore
    private let reload: () -> Void

    init(store: WidgetSnapshotStore = WidgetSnapshotStore(),
         reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.store = store
        self.reload = reload
    }

    /// Builds and persists a snapshot from the latest Today data + current palette.
    func update(from today: TodaySnapshot, palette: Palette, now: Date = .now) {
        store.write(map(today, palette: palette, now: now))
        reload()
    }

    /// Re-skins the stored snapshot for a palette change without re-fetching data.
    func repaint(palette: Palette) {
        var snapshot = store.read()
        snapshot.palette = palette.rawValue
        store.write(snapshot)
        reload()
    }

    func map(_ today: TodaySnapshot, palette: Palette, now: Date = .now) -> WidgetSnapshot {
        let card = today.today
        return WidgetSnapshot(
            palette: palette.rawValue,
            generatedAt: now,
            programLabel: card?.programLabel,
            dayLabel: card?.dayLabel,
            todayWorkoutName: card?.name,
            exerciseCount: card?.exerciseCount,
            week: today.week.map { WeekCellSnapshot(dayLetter: $0.dayLetter, state: $0.state.rawValue) },
            streak: today.streak,
            startRoute: (card == nil ? WidgetDeepLink.today : .startToday).url.absoluteString)
    }
}
