import Foundation

/// Records cue calls in order for unit tests. Reference type so the model's
/// stored copy and the test's handle observe the same call log.
final class MockRestCueService: RestCuePlaying {
    enum Call: Equatable { case prepare, warn, end, teardown }
    private(set) var calls: [Call] = []

    var warnCount: Int { calls.filter { $0 == .warn }.count }
    var endCount: Int { calls.filter { $0 == .end }.count }
    var prepareCount: Int { calls.filter { $0 == .prepare }.count }
    var teardownCount: Int { calls.filter { $0 == .teardown }.count }

    func prepare() { calls.append(.prepare) }
    func warn() { calls.append(.warn) }
    func end() { calls.append(.end) }
    func teardown() { calls.append(.teardown) }
}
