import WidgetKit

/// Timeline entry for the static "Today's Workout" widget (BAK-19).
struct PulseEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// Reads the shared App Group snapshot (mock fallback when absent/corrupt) and
/// produces a now-entry + a next-midnight entry, re-requesting at midnight. All
/// entry logic lives in the shared, unit-tested `WidgetTimeline`.
struct PulseProvider: TimelineProvider {
    private let store = WidgetSnapshotStore()

    func placeholder(in context: Context) -> PulseEntry {
        PulseEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (PulseEntry) -> Void) {
        completion(PulseEntry(date: .now, snapshot: store.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PulseEntry>) -> Void) {
        let now = Date()
        let entries = WidgetTimeline.entries(snapshot: store.read(), now: now)
            .map { PulseEntry(date: $0.date, snapshot: $0.snapshot) }
        completion(Timeline(entries: entries, policy: .after(WidgetTimeline.nextRefresh(after: now))))
    }
}
