import XCTest
@testable import Pulse

final class SaveClassificationTests: XCTestCase {
    func testOfflineErrorIsConnectionMessage() {
        let msg = SaveClassification.failureMessage(for: URLError(.notConnectedToInternet))
        XCTAssertTrue(msg.localizedCaseInsensitiveContains("connection"),
                      "a connectivity error should still mention the connection — got: \(msg)")
    }

    func testGenericErrorSurfacesItsDescriptionNotConnection() {
        struct Boom: LocalizedError { var errorDescription: String? { "boom detail" } }
        let msg = SaveClassification.failureMessage(for: Boom())
        XCTAssertTrue(msg.contains("boom detail"), "a hard error should surface its real reason — got: \(msg)")
        XCTAssertFalse(msg.localizedCaseInsensitiveContains("check your connection"),
                       "a non-connectivity error must not blame the connection — got: \(msg)")
    }

    func testNonOfflineURLErrorIsNotBlamedOnConnection() {
        // A non-connectivity URLError (e.g. a 4xx/5xx surfaced as badServerResponse)
        // is a hard failure, not the "check your connection" bucket.
        let msg = SaveClassification.failureMessage(for: URLError(.badServerResponse))
        XCTAssertFalse(msg.localizedCaseInsensitiveContains("check your connection"),
                       "a server-side failure must not blame the connection — got: \(msg)")
    }
}
