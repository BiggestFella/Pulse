import XCTest
@testable import Pulse

@MainActor
final class YouModelTests: XCTestCase {

    private func makeModel(
        user: any UserRepository = InMemoryUserRepository(),
        settings: any SettingsRepository = InMemorySettingsRepository()
    ) -> YouModel {
        YouModel(userRepo: user, settingsRepo: settings)
    }

    func testInitialPhaseIsLoading() {
        XCTAssertEqual(makeModel().phase, .loading)
    }

    func testLoadPopulatesSnapshotsAndMarksLoaded() async {
        let model = makeModel()
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.profile?.displayName, "Alex Mason")
        XCTAssertEqual(model.stats?.streakDays, 27)
        XCTAssertEqual(model.settings, .default)
    }

    func testLoadFailureEntersFailedButKeepsDefaultSettings() async {
        let model = makeModel(user: InMemoryUserRepository(shouldFail: true))
        await model.load()
        guard case .failed = model.phase else {
            return XCTFail("expected .failed, got \(model.phase)")
        }
        XCTAssertEqual(model.settings, .default) // last-known/default retained
    }

    func testEmptyUserYieldsZeroStatsWithoutCrashing() async {
        let model = makeModel(user: InMemoryUserRepository(variant: .emptyUser))
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.stats, .empty)
    }

    func testSetAutoProgressMutatesAndPersists() async {
        let repo = InMemorySettingsRepository()
        let model = makeModel(settings: repo)
        await model.load()
        await model.setAutoProgress(false)
        XCTAssertFalse(model.settings.autoProgressWeight)
        let persisted = try? await repo.load()
        XCTAssertEqual(persisted?.autoProgressWeight, false)
    }

    func testSetSoundOnRestMutatesAndPersists() async {
        let repo = InMemorySettingsRepository()
        let model = makeModel(settings: repo)
        await model.load()
        await model.setSoundOnRest(false)
        XCTAssertFalse(model.settings.soundOnRestEnd)
        let persisted = try? await repo.load()
        XCTAssertEqual(persisted?.soundOnRestEnd, false)
    }

    func testFailedSaveSurfacesErrorWithoutReverting() async {
        let repo = InMemorySettingsRepository(shouldFailSave: true)
        let model = makeModel(settings: repo)
        await model.load()
        await model.setAutoProgress(false)
        XCTAssertFalse(model.settings.autoProgressWeight) // optimistic value kept
        XCTAssertNotNil(model.saveError)
    }
}
