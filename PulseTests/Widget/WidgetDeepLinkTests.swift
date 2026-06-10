import XCTest
@testable import Pulse

final class WidgetDeepLinkTests: XCTestCase {
    func testURLsAreStable() {
        XCTAssertEqual(WidgetDeepLink.startToday.url.absoluteString, "pulse://start-today")
        XCTAssertEqual(WidgetDeepLink.today.url.absoluteString, "pulse://today")
    }

    func testParsesKnownRoutes() {
        XCTAssertEqual(WidgetDeepLink(URL(string: "pulse://start-today")!), .startToday)
        XCTAssertEqual(WidgetDeepLink(URL(string: "pulse://today")!), .today)
    }

    func testRejectsUnknownOrForeignURLs() {
        XCTAssertNil(WidgetDeepLink(URL(string: "pulse://nope")!))
        XCTAssertNil(WidgetDeepLink(URL(string: "https://today")!))
    }

    func testRoundTripsThroughURL() {
        for link in [WidgetDeepLink.startToday, .today] {
            XCTAssertEqual(WidgetDeepLink(link.url), link)
        }
    }
}
