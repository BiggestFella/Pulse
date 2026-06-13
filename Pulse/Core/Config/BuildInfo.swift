import Foundation

/// Build identity read from the bundle's Info.plist, surfaced in the You-tab
/// footer so a running build is identifiable. `version`/`build` come from the
/// standard bundle keys; `commit`/`date` are stamped at build time by the
/// "Stamp build" postBuildScript (see project.yml).
struct BuildInfo: Equatable {
    let version: String   // CFBundleShortVersionString (MARKETING_VERSION)
    let build: String     // CFBundleVersion (CURRENT_PROJECT_VERSION)
    let commit: String    // short git SHA (e.g. "a459da7", "a459da7-dirty")
    let date: String      // build date (e.g. "12 Jun 2026")

    init(info: [String: Any]) {
        func str(_ key: String) -> String { (info[key] as? String) ?? "—" }
        version = str("CFBundleShortVersionString")
        build = str("CFBundleVersion")
        commit = str("GitCommit")
        date = str("BuildDate")
    }

    static func fromBundle(_ bundle: Bundle = .main) -> BuildInfo {
        BuildInfo(info: bundle.infoDictionary ?? [:])
    }

    /// e.g. "v0.1.0 (1) · a459da7 · 12 Jun 2026".
    var footerLabel: String {
        "v\(version) (\(build)) · \(commit) · \(date)"
    }
}
