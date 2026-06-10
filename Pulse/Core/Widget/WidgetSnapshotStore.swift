import Foundation

/// Reads/writes the `WidgetSnapshot` to the shared App Group container (BAK-19).
/// The app writes; the widget reads. A missing or corrupt payload (including a
/// week that isn't exactly 7 cells) degrades to the sample rather than crashing
/// the extension. Cross-compiled into both targets.
struct WidgetSnapshotStore {
    static let appGroup = "group.au.com.codeheroes.pulse"
    private static let key = "widget-snapshot"
    private let defaults: UserDefaults

    /// `defaults` is injectable for tests; production uses the App Group suite
    /// (falling back to `.standard` only if the suite can't be opened).
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.appGroup) ?? .standard
    }

    func write(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Test seam for the corrupt-payload path.
    func writeRaw(_ data: Data) { defaults.set(data, forKey: Self.key) }

    /// The stored snapshot, or the sample when absent/corrupt/invalid.
    func read() -> WidgetSnapshot {
        guard let data = defaults.data(forKey: Self.key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.hasValidWeek
        else { return .sample }
        return snapshot
    }
}
