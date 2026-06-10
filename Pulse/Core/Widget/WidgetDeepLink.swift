import Foundation

/// Deep links the widget taps into and the app resolves (BAK-19). Shared so the
/// widget builds the URL and `AppShell` parses it from one source of truth.
enum WidgetDeepLink: Equatable {
    /// A workout is scheduled today → start it.
    case startToday
    /// Rest day / no workout → just open the Today tab.
    case today

    static let scheme = "pulse"

    var host: String {
        switch self {
        case .startToday: return "start-today"
        case .today:      return "today"
        }
    }

    var url: URL {
        // Host-only URL, e.g. "pulse://start-today".
        URL(string: "\(Self.scheme)://\(host)")!
    }

    /// Parses an incoming URL back into a route, or nil if it isn't ours.
    init?(_ url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        // Host carries the route; tolerate it landing in the path on some forms.
        let key = url.host ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch key {
        case Self.startToday.host: self = .startToday
        case Self.today.host:      self = .today
        default:                   return nil
        }
    }
}
