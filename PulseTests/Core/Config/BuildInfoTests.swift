import XCTest
@testable import Pulse

final class BuildInfoTests: XCTestCase {
    func testFooterLabelFormatsAllFields() {
        let info = BuildInfo(info: [
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "1",
            "GitCommit": "a459da7",
            "BuildDate": "12 Jun 2026",
        ])
        XCTAssertEqual(info.footerLabel, "v0.1.0 (1) · a459da7 · 12 Jun 2026")
    }

    func testMissingKeysFallBackToDash() {
        let info = BuildInfo(info: [:])
        XCTAssertEqual(info.version, "—")
        XCTAssertEqual(info.commit, "—")
        XCTAssertEqual(info.footerLabel, "v— (—) · — · —")
    }

    func testDirtyCommitIsPreservedVerbatim() {
        let info = BuildInfo(info: [
            "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
            "GitCommit": "a459da7-dirty", "BuildDate": "12 Jun 2026",
        ])
        XCTAssertEqual(info.commit, "a459da7-dirty")
    }
}
