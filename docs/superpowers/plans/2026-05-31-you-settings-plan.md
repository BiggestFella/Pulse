# You / Settings (BAK-13) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Follow strict TDD for every step in a logic task (model, analytics helper, repositories, mocks): write the failing test, run it and see it fail, write the minimal implementation, run it and see it pass, then commit. View-assembly tasks are validated by `#Preview` + an XCUITest, not line-by-line TDD.

**Goal:** Ship the **You** tab — the profile/settings landing screen. It renders the lifter's identity (avatar, name, membership), a 3-up MiniStat strip (streak / sessions / volume), a "YOUR DATA" hub of NavRows that push to Stats / Personal Records / Workout History, a live **Palette** swatch picker (Coastal/Mint) that re-skins the whole app instantly, and a **Preferences** card (units display, default rest timer, auto-progress toggle, rest-sound toggle). Logic lives in an `@Observable` `YouModel` bound to BAK-6 repository protocols backed by in-memory mocks; the screen never touches Supabase.

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. The screen is `YouView` + `YouModel` in `Pulse/Features/You/`, with reusable subviews under `Pulse/Features/You/Components/`. Data is read/written only through repository protocols (`UserRepository`, `StatsRepository`, `SettingsRepository`) in `Pulse/Core/Data/`; this feature defines those protocols + in-memory mocks + sample data (owned by BAK-6, created here against mocks for the UI-first build). Domain structs (`UserProfile`, `ProfileStats`, `UserSettings`) live in `Pulse/Core/Models/`. The active `Palette` is owned by the existing injected `Theme` (`Pulse/Core/DesignSystem/Theme.swift`), which already persists to `UserDefaults` key `"pulse-pal"`; the swatch picker is a thin control that reads/writes `theme.palette`. Project is generated from `project.yml` via XcodeGen.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency (`async`/`await`), `@Observable`, XCTest + XCUITest, XcodeGen.

---

## Prerequisites (verify before starting)

This feature depends on two foundation features. The buildable skeleton, `Theme`/`Palette`, and domain-model file already exist from the Foundation layer (PR #1); the **Design System (BAK-7)** and **Data layer (BAK-6)** pieces this feature needs (profile/stats/settings models, the three repository protocols + mocks, and the typography/eyebrow/row primitives) are created here against mocks where they are not yet present.

- [ ] **Step 0a: Confirm the project generates and builds green**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 0b: Confirm the foundation pieces this plan builds on exist**

Run:
```bash
ls Pulse/Core/DesignSystem/Theme.swift Pulse/Core/DesignSystem/Palette.swift \
   Pulse/App/AppShell.swift Pulse/Features/You/YouView.swift
```
Expected: all four paths print (no "No such file"). `Theme` is `@Observable`, owns `var palette: Palette`, and persists to `UserDefaults` key `"pulse-pal"`. `Palette` is `enum Palette: String, CaseIterable { case coastal, mint }` with `.tokens` and a `static let default`.

- [ ] **Step 0c: Confirm the branch**

Run: `git checkout -b feature/BAK-13-you-settings`
Expected: switched to a new branch.

---

## Task 1: Inject `Theme` from the app root so palette is app-global

**Files:**
- Modify: `Pulse/App/PulseApp.swift`
- Modify: `Pulse/App/AppShell.swift`

The swatch picker must re-skin the **entire** app, so a single `Theme` instance must be owned at the root and injected into the environment. Today `AppShell` does not own or inject one. This task wires it. (No new logic — verified by the existing app-launch UI test still passing.)

- [ ] **Step 1: Own a `Theme` at the app entry point and inject it**

Replace `Pulse/App/PulseApp.swift` with:
```swift
import SwiftUI

@main
struct PulseApp: App {
    @State private var theme = Theme()

    var body: some Scene {
        WindowGroup {
            AppShell()
                .environment(theme)
                .background(theme.bg.ignoresSafeArea())
        }
    }
}
```

- [ ] **Step 2: Read the injected `Theme` in `AppShell` and tint the bar**

Replace `Pulse/App/AppShell.swift` with:
```swift
import SwiftUI

struct AppShell: View {
    @Environment(Theme.self) private var theme

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "bolt.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            YouView()
                .tabItem { Label("You", systemImage: "person.fill") }
        }
        .tint(theme.accent)
    }
}

#Preview {
    AppShell().environment(Theme())
}
```

- [ ] **Step 3: Build and run the existing UI test to confirm nothing broke**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseUITests/PulseUITests/testAppLaunches test
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Pulse/App
git commit -m "feat(you): own and inject app-global Theme from the root scene"
```

---

## Task 2: Domain models — `UserProfile`, `ProfileStats`, `UserSettings` (TDD)

**Files:**
- Create: `Pulse/Core/Models/ProfileModels.swift`
- Test: `PulseTests/ProfileModelsTests.swift`

Per the product decisions, v1 is **kg-only** and there is **no units toggle**: `UserSettings.units` is a display-only enum fixed to `.kg` (formatting kept in one place so a later feature can localize it). The default rest timer is stored in seconds.

- [ ] **Step 1: Write the failing test `PulseTests/ProfileModelsTests.swift`**

```swift
import XCTest
@testable import Pulse

final class ProfileModelsTests: XCTestCase {
    func testUserSettingsDefaultsAreKgRest90AutoOnSoundOn() {
        let s = UserSettings.default
        XCTAssertEqual(s.units, .kg)
        XCTAssertEqual(s.defaultRestSeconds, 90)
        XCTAssertTrue(s.autoProgressWeight)
        XCTAssertTrue(s.soundOnRestEnd)
    }

    func testUnitsDisplayLabelIsKgMetric() {
        XCTAssertEqual(Units.kg.displayLabel, "KG · METRIC")
    }

    func testRestTimerDisplayLabelFormatsSeconds() {
        XCTAssertEqual(UserSettings.default.restTimerLabel, "90s")
    }

    func testProfileStatsEmptyIsAllZero() {
        let z = ProfileStats.empty
        XCTAssertEqual(z.streakDays, 0)
        XCTAssertEqual(z.totalSessions, 0)
        XCTAssertEqual(z.totalVolumeKg, 0)
    }

    func testUserSettingsCodableRoundTrip() throws {
        let original = UserSettings(units: .kg, defaultRestSeconds: 120,
                                    autoProgressWeight: false, soundOnRestEnd: true)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testProfileFallbackInitialIsQuestionMarkWhenNameEmpty() {
        let p = UserProfile(displayName: "", memberSince: Date(), programLabel: "PPL")
        XCTAssertEqual(p.avatarInitial, "?")
    }

    func testProfileInitialIsFirstLetterUppercased() {
        let p = UserProfile(displayName: "alex mason", memberSince: Date(), programLabel: "PPL")
        XCTAssertEqual(p.avatarInitial, "A")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseTests/ProfileModelsTests test
```
Expected: FAIL — `UserSettings` / `Units` / `ProfileStats` / `UserProfile` undefined (compile error).

- [ ] **Step 3: Write `Pulse/Core/Models/ProfileModels.swift`**

```swift
import Foundation

/// Weight unit system. v1 is kg-only (product decision); a real toggle + conversion
/// is a later feature. Keeping the label here localizes that future change.
enum Units: String, Codable, CaseIterable {
    case kg

    var displayLabel: String {
        switch self {
        case .kg: return "KG · METRIC"
        }
    }
}

/// Lifter identity shown in the You header.
struct UserProfile: Codable, Equatable {
    var displayName: String
    var memberSince: Date
    var programLabel: String

    /// Single uppercase initial for the avatar; falls back to "?" when name is empty.
    var avatarInitial: String {
        guard let first = displayName.trimmingCharacters(in: .whitespaces).first else {
            return "?"
        }
        return String(first).uppercased()
    }

    /// "Member since Feb 2024 · PPL"
    var subtitle: String {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = .current
        f.dateFormat = "LLL yyyy"
        return "Member since \(f.string(from: memberSince)) · \(programLabel)"
    }
}

/// Aggregate headline numbers for the MiniStat strip.
struct ProfileStats: Codable, Equatable {
    var streakDays: Int
    var totalSessions: Int
    var totalVolumeKg: Double
    var liftsTracked: Int
    var sessionsLogged: Int

    static let empty = ProfileStats(streakDays: 0, totalSessions: 0,
                                    totalVolumeKg: 0, liftsTracked: 0, sessionsLogged: 0)
}

/// Editable training preferences. Persisted via `SettingsRepository`.
struct UserSettings: Codable, Equatable {
    var units: Units
    var defaultRestSeconds: Int
    var autoProgressWeight: Bool
    var soundOnRestEnd: Bool

    static let `default` = UserSettings(units: .kg, defaultRestSeconds: 90,
                                        autoProgressWeight: true, soundOnRestEnd: true)

    /// "90s" — display value for the Default rest timer row.
    var restTimerLabel: String { "\(defaultRestSeconds)s" }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseTests/ProfileModelsTests test
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Regenerate (new source file) and commit**

```bash
xcodegen generate
git add Pulse/Core/Models/ProfileModels.swift PulseTests/ProfileModelsTests.swift project.yml
git commit -m "feat(you): UserProfile, ProfileStats, UserSettings domain models"
```

---

## Task 3: Volume formatting helper (TDD)

**Files:**
- Create: `Pulse/Core/Models/VolumeFormatter.swift`
- Test: `PulseTests/VolumeFormatterTests.swift`

The VOLUME MiniStat shows a compact numeral + unit (`2.1` `M`). Per product decisions, weight formatting lives in **one helper** so a later units feature can localize it. This helper splits a kg volume into a display value string and a unit suffix.

- [ ] **Step 1: Write the failing test `PulseTests/VolumeFormatterTests.swift`**

```swift
import XCTest
@testable import Pulse

final class VolumeFormatterTests: XCTestCase {
    func testMillionsCompactToOneDecimalM() {
        let r = VolumeFormatter.compact(2_100_000)
        XCTAssertEqual(r.value, "2.1")
        XCTAssertEqual(r.unit, "M")
    }

    func testThousandsCompactToK() {
        let r = VolumeFormatter.compact(48_500)
        XCTAssertEqual(r.value, "48.5")
        XCTAssertEqual(r.unit, "K")
    }

    func testSmallVolumeHasNoUnit() {
        let r = VolumeFormatter.compact(420)
        XCTAssertEqual(r.value, "420")
        XCTAssertEqual(r.unit, "")
    }

    func testZeroVolume() {
        let r = VolumeFormatter.compact(0)
        XCTAssertEqual(r.value, "0")
        XCTAssertEqual(r.unit, "")
    }

    func testWholeMillionDropsTrailingZero() {
        let r = VolumeFormatter.compact(3_000_000)
        XCTAssertEqual(r.value, "3")
        XCTAssertEqual(r.unit, "M")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseTests/VolumeFormatterTests test
```
Expected: FAIL — `VolumeFormatter` undefined.

- [ ] **Step 3: Write `Pulse/Core/Models/VolumeFormatter.swift`**

```swift
import Foundation

/// Compact display of a kg volume as a numeral + unit suffix ("2.1" + "M").
/// Single source of truth for volume formatting so a later units feature is localized.
enum VolumeFormatter {
    struct Compact: Equatable { let value: String; let unit: String }

    static func compact(_ kg: Double) -> Compact {
        let abs = Swift.abs(kg)
        if abs >= 1_000_000 { return Compact(value: trim(kg / 1_000_000), unit: "M") }
        if abs >= 1_000 { return Compact(value: trim(kg / 1_000), unit: "K") }
        return Compact(value: trim(kg), unit: "")
    }

    /// One decimal, dropping a trailing ".0".
    private static func trim(_ x: Double) -> String {
        let rounded = (x * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.1f", rounded)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseTests/VolumeFormatterTests test
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Regenerate and commit**

```bash
xcodegen generate
git add Pulse/Core/Models/VolumeFormatter.swift PulseTests/VolumeFormatterTests.swift project.yml
git commit -m "feat(you): compact volume formatter (kg -> value + K/M unit)"
```

---

## Task 4: Repository protocols + in-memory mocks (TDD)

**Files:**
- Create: `Pulse/Core/Data/UserRepository.swift`
- Create: `Pulse/Core/Data/StatsRepository.swift`
- Create: `Pulse/Core/Data/SettingsRepository.swift`
- Test: `PulseTests/MockRepositoryTests.swift`

These three protocols are owned by BAK-6; we define them here with in-memory mocks + sample data so the UI-first build has something to bind to. Real Supabase conformances land behind the same protocols later. Each mock also offers a controllable failure mode and an "empty/new user" variant so the model's edge cases are testable.

- [ ] **Step 1: Write the failing test `PulseTests/MockRepositoryTests.swift`**

```swift
import XCTest
@testable import Pulse

final class MockRepositoryTests: XCTestCase {
    func testMockUserRepositoryReturnsSampleProfile() async throws {
        let profile = try await MockUserRepository().currentProfile()
        XCTAssertEqual(profile.displayName, "Alex Mason")
        XCTAssertEqual(profile.programLabel, "PPL")
    }

    func testMockStatsRepositoryReturnsSampleSummary() async throws {
        let stats = try await MockStatsRepository().profileSummary()
        XCTAssertEqual(stats.streakDays, 27)
        XCTAssertEqual(stats.totalSessions, 183)
        XCTAssertEqual(stats.totalVolumeKg, 2_100_000)
        XCTAssertEqual(stats.liftsTracked, 8)
        XCTAssertEqual(stats.sessionsLogged, 183)
    }

    func testMockSettingsRepositoryLoadReturnsDefaults() async throws {
        let s = try await MockSettingsRepository().load()
        XCTAssertEqual(s, .default)
    }

    func testMockSettingsRepositorySavePersistsForNextLoad() async throws {
        let repo = MockSettingsRepository()
        var s = try await repo.load()
        s.autoProgressWeight = false
        try await repo.save(s)
        let reloaded = try await repo.load()
        XCTAssertFalse(reloaded.autoProgressWeight)
    }

    func testFailingMocksThrow() async {
        await XCTAssertThrowsErrorAsync(try await MockUserRepository(shouldFail: true).currentProfile())
        await XCTAssertThrowsErrorAsync(try await MockStatsRepository(shouldFail: true).profileSummary())
    }

    func testEmptyUserStatsAreZero() async throws {
        let stats = try await MockStatsRepository(variant: .emptyUser).profileSummary()
        XCTAssertEqual(stats, .empty)
    }
}

/// async throwing-assertion helper.
func XCTAssertThrowsErrorAsync(_ expression: @autoclosure () async throws -> some Any,
                               file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await expression(); XCTFail("Expected error", file: file, line: line) }
    catch { /* expected */ }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseTests/MockRepositoryTests test
```
Expected: FAIL — `MockUserRepository` / `MockStatsRepository` / `MockSettingsRepository` undefined.

- [ ] **Step 3: Write `Pulse/Core/Data/UserRepository.swift`**

```swift
import Foundation

/// Reads the current lifter's profile. Owned by BAK-6; mock here for the UI-first build.
protocol UserRepository {
    func currentProfile() async throws -> UserProfile
}

struct RepositoryError: Error, Equatable { let message: String }

/// In-memory mock with sample data mirroring the prototype.
final class MockUserRepository: UserRepository {
    private let shouldFail: Bool
    init(shouldFail: Bool = false) { self.shouldFail = shouldFail }

    func currentProfile() async throws -> UserProfile {
        if shouldFail { throw RepositoryError(message: "profile unavailable") }
        var components = DateComponents()
        components.year = 2024; components.month = 2; components.day = 1
        let memberSince = Calendar.current.date(from: components) ?? Date()
        return UserProfile(displayName: "Alex Mason",
                           memberSince: memberSince, programLabel: "PPL")
    }
}
```

- [ ] **Step 4: Write `Pulse/Core/Data/StatsRepository.swift`**

```swift
import Foundation

/// Aggregate stats for the You header + NavRow sub-counts. Owned by BAK-6.
protocol StatsRepository {
    func profileSummary() async throws -> ProfileStats
}

final class MockStatsRepository: StatsRepository {
    enum Variant { case sample, emptyUser }
    private let shouldFail: Bool
    private let variant: Variant
    init(shouldFail: Bool = false, variant: Variant = .sample) {
        self.shouldFail = shouldFail; self.variant = variant
    }

    func profileSummary() async throws -> ProfileStats {
        if shouldFail { throw RepositoryError(message: "stats unavailable") }
        switch variant {
        case .emptyUser: return .empty
        case .sample:
            return ProfileStats(streakDays: 27, totalSessions: 183,
                                totalVolumeKg: 2_100_000, liftsTracked: 8, sessionsLogged: 183)
        }
    }
}
```

- [ ] **Step 5: Write `Pulse/Core/Data/SettingsRepository.swift`**

```swift
import Foundation

/// Loads/saves training preferences (units, default rest, toggles). Owned by BAK-6.
/// Palette is NOT here — it is persisted by `Theme` via UserDefaults "pulse-pal".
protocol SettingsRepository {
    func load() async throws -> UserSettings
    func save(_ settings: UserSettings) async throws
}

/// In-memory mock: holds a mutable copy so save -> load round-trips within a session.
final class MockSettingsRepository: SettingsRepository {
    private let shouldFailLoad: Bool
    private let shouldFailSave: Bool
    private var stored: UserSettings

    init(shouldFailLoad: Bool = false, shouldFailSave: Bool = false,
         initial: UserSettings = .default) {
        self.shouldFailLoad = shouldFailLoad
        self.shouldFailSave = shouldFailSave
        self.stored = initial
    }

    func load() async throws -> UserSettings {
        if shouldFailLoad { throw RepositoryError(message: "settings load failed") }
        return stored
    }

    func save(_ settings: UserSettings) async throws {
        if shouldFailSave { throw RepositoryError(message: "settings save failed") }
        stored = settings
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseTests/MockRepositoryTests test
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 7: Regenerate and commit**

```bash
xcodegen generate
git add Pulse/Core/Data PulseTests/MockRepositoryTests.swift project.yml
git commit -m "feat(you): User/Stats/Settings repository protocols + in-memory mocks"
```

---

## Task 5: `YouModel` (TDD)

**Files:**
- Create: `Pulse/Features/You/YouModel.swift`
- Test: `PulseTests/YouModelTests.swift`

`YouModel` is the screen's `@Observable` model. It loads profile + stats + settings on appear, exposes a `LoadPhase`, and mutates/persists the two toggles. Palette is **not** owned here (the swatch picker writes `Theme`). On a repo failure, `load()` enters a non-fatal failed state but leaves `settings` at last-known/default so the screen still renders and the palette picker stays usable. Toggle saves are optimistic and persist; a failed save surfaces an error string without reverting (per product-decisions default: keep it simple, surface non-fatal error).

- [ ] **Step 1: Write the failing test `PulseTests/YouModelTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class YouModelTests: XCTestCase {

    private func makeModel(
        user: UserRepository = MockUserRepository(),
        stats: StatsRepository = MockStatsRepository(),
        settings: SettingsRepository = MockSettingsRepository()
    ) -> YouModel {
        YouModel(userRepo: user, statsRepo: stats, settingsRepo: settings)
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
        let model = makeModel(stats: MockStatsRepository(shouldFail: true))
        await model.load()
        guard case .failed = model.phase else {
            return XCTFail("expected .failed, got \(model.phase)")
        }
        XCTAssertEqual(model.settings, .default) // last-known/default retained
    }

    func testEmptyUserYieldsZeroStatsWithoutCrashing() async {
        let model = makeModel(stats: MockStatsRepository(variant: .emptyUser))
        await model.load()
        XCTAssertEqual(model.phase, .loaded)
        XCTAssertEqual(model.stats, .empty)
    }

    func testSetAutoProgressMutatesAndPersists() async {
        let repo = MockSettingsRepository()
        let model = makeModel(settings: repo)
        await model.load()
        await model.setAutoProgress(false)
        XCTAssertFalse(model.settings.autoProgressWeight)
        let persisted = try? await repo.load()
        XCTAssertEqual(persisted?.autoProgressWeight, false)
    }

    func testSetSoundOnRestMutatesAndPersists() async {
        let repo = MockSettingsRepository()
        let model = makeModel(settings: repo)
        await model.load()
        await model.setSoundOnRest(false)
        XCTAssertFalse(model.settings.soundOnRestEnd)
        let persisted = try? await repo.load()
        XCTAssertEqual(persisted?.soundOnRestEnd, false)
    }

    func testFailedSaveSurfacesErrorWithoutReverting() async {
        let repo = MockSettingsRepository(shouldFailSave: true)
        let model = makeModel(settings: repo)
        await model.load()
        await model.setAutoProgress(false)
        XCTAssertFalse(model.settings.autoProgressWeight) // optimistic value kept
        XCTAssertNotNil(model.saveError)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseTests/YouModelTests test
```
Expected: FAIL — `YouModel` / `LoadPhase` undefined.

- [ ] **Step 3: Write `Pulse/Features/You/YouModel.swift`**

```swift
import Foundation

enum LoadPhase: Equatable {
    case loading
    case loaded
    case failed(String)
}

@MainActor
@Observable
final class YouModel {
    private(set) var profile: UserProfile?
    private(set) var stats: ProfileStats?
    private(set) var settings: UserSettings = .default
    private(set) var phase: LoadPhase = .loading
    /// Non-fatal error from a failed preference save (nil when the last save succeeded).
    private(set) var saveError: String?

    private let userRepo: UserRepository
    private let statsRepo: StatsRepository
    private let settingsRepo: SettingsRepository

    init(userRepo: UserRepository,
         statsRepo: StatsRepository,
         settingsRepo: SettingsRepository) {
        self.userRepo = userRepo
        self.statsRepo = statsRepo
        self.settingsRepo = settingsRepo
    }

    func load() async {
        phase = .loading
        do {
            async let profileTask = userRepo.currentProfile()
            async let statsTask = statsRepo.profileSummary()
            async let settingsTask = settingsRepo.load()
            let (p, s, set) = try await (profileTask, statsTask, settingsTask)
            profile = p
            stats = s
            settings = set
            phase = .loaded
        } catch {
            // Non-fatal: keep last-known/default settings; the screen still renders.
            phase = .failed(String(describing: error))
        }
    }

    func setAutoProgress(_ on: Bool) async {
        settings.autoProgressWeight = on
        await persist()
    }

    func setSoundOnRest(_ on: Bool) async {
        settings.soundOnRestEnd = on
        await persist()
    }

    private func persist() async {
        do {
            try await settingsRepo.save(settings)
            saveError = nil
        } catch {
            // Optimistic: keep the new value, surface a non-fatal error.
            saveError = String(describing: error)
        }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseTests/YouModelTests test
```
Expected: `TEST SUCCEEDED`.

- [ ] **Step 5: Regenerate and commit**

```bash
xcodegen generate
git add Pulse/Features/You/YouModel.swift PulseTests/YouModelTests.swift project.yml
git commit -m "feat(you): YouModel — load snapshots, phases, persist toggles"
```

---

## Task 6: `MiniStat` component (view assembly)

**Files:**
- Create: `Pulse/Features/You/Components/MiniStat.swift`

A flat `surface` card with a Geist Mono eyebrow + Oswald numeral and optional small Hanken unit. Color treatment: STREAK → eyebrow & numeral `accent2`; VOLUME → eyebrow `accent`, numeral `ink`; SESSIONS → eyebrow `inkSoft`, numeral `ink`. All colors/spacing from `Theme`. (Validated by `#Preview` + the screen's UI test in Task 11.)

- [ ] **Step 1: Create `Pulse/Features/You/Components/MiniStat.swift`**

```swift
import SwiftUI

struct MiniStat: View {
    enum Tint { case accent, accent2, neutral }

    let label: String
    let value: String
    var unit: String = ""
    var tint: Tint = .neutral

    @Environment(Theme.self) private var theme

    private var eyebrowColor: Color {
        switch tint {
        case .accent: return theme.accent
        case .accent2: return theme.accent2
        case .neutral: return theme.inkSoft
        }
    }
    private var numeralColor: Color {
        tint == .accent2 ? theme.accent2 : theme.ink
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[0]) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(eyebrowColor)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.custom("Oswald", size: 24).weight(.bold))
                    .foregroundStyle(numeralColor)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.ink.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing[2])
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.spacing[3]))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)\(unit)")
    }
}

#Preview {
    HStack(spacing: 6) {
        MiniStat(label: "STREAK", value: "27", unit: "d", tint: .accent2)
        MiniStat(label: "SESSIONS", value: "183")
        MiniStat(label: "VOLUME", value: "2.1", unit: "M", tint: .accent)
    }
    .padding()
    .background(Theme().bg)
    .environment(Theme())
}
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/You/Components/MiniStat.swift project.yml
git commit -m "feat(you): MiniStat card component"
```

---

## Task 7: `NavRow` component (view assembly)

**Files:**
- Create: `Pulse/Features/You/Components/NavRow.swift`

A pressable `surface` row: 32pt rounded icon tile + name (Hanken 700) + sub (Geist Mono) + trailing chevron. The icon tile takes a fill color and either an SF Symbol or a 1–2 char label (Oswald). All colors/spacing from `Theme`.

- [ ] **Step 1: Create `Pulse/Features/You/Components/NavRow.swift`**

```swift
import SwiftUI

struct NavRow: View {
    enum Glyph { case symbol(String), text(String) }

    let glyph: Glyph
    let tileColor: Color
    var glyphColor: Color? = nil
    let name: String
    let sub: String
    let action: () -> Void

    @Environment(Theme.self) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: theme.spacing[4]) {
                tile
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.custom("HankenGrotesk-Bold", size: 16))
                        .foregroundStyle(theme.ink)
                    Text(sub)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.inkSoft)
            }
            .padding(.horizontal, theme.spacing[4])
            .padding(.vertical, theme.spacing[3])
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.spacing[3]))
        }
        .buttonStyle(PressableRowStyle())
    }

    @ViewBuilder private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: theme.spacing[1])
                .fill(tileColor)
                .frame(width: 32, height: 32)
            switch glyph {
            case .symbol(let n):
                Image(systemName: n)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(glyphColor ?? theme.onAccent)
            case .text(let t):
                Text(t)
                    .font(.custom("Oswald", size: 14).weight(.bold))
                    .foregroundStyle(glyphColor ?? theme.onAccent)
            }
        }
    }
}

/// Standard press feedback: subtle scale + opacity dip.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 6) {
        NavRow(glyph: .symbol("chart.bar.fill"), tileColor: Theme().accent,
               name: "Stats", sub: "Volume, PRs, charts") {}
        NavRow(glyph: .text("PR"), tileColor: Theme().accent2,
               name: "Personal records", sub: "8 lifts tracked") {}
    }
    .padding()
    .background(Theme().bg)
    .environment(Theme())
}
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/You/Components/NavRow.swift project.yml
git commit -m "feat(you): NavRow component with pressable row style"
```

---

## Task 8: `PaletteSwatchPicker` component (view assembly)

**Files:**
- Create: `Pulse/Features/You/Components/PaletteSwatchPicker.swift`

One circular swatch per `Palette.allCases`, filled with that palette's `accent`. The selected swatch is ringed (`2px solid ink` + `accent2` halo); unselected use a faint `inkFaint` border. Tapping a swatch sets `theme.palette` **without** `withAnimation` (background must not flash). The picker reads/writes the injected `Theme`, which persists to `"pulse-pal"`.

- [ ] **Step 1: Create `Pulse/Features/You/Components/PaletteSwatchPicker.swift`**

```swift
import SwiftUI

struct PaletteSwatchPicker: View {
    @Environment(Theme.self) private var theme

    var body: some View {
        HStack(spacing: theme.spacing[1]) {
            ForEach(Palette.allCases, id: \.self) { palette in
                swatch(palette)
            }
        }
    }

    private func swatch(_ palette: Palette) -> some View {
        let selected = theme.palette == palette
        return Circle()
            .fill(Color(hex: palette.tokens.accent))
            .frame(width: 26, height: 26)
            .overlay(
                Circle().stroke(selected ? theme.ink : theme.inkFaint,
                                lineWidth: selected ? 2 : 1.5)
            )
            .overlay(
                Circle().stroke(theme.accent2, lineWidth: selected ? 2 : 0)
                    .padding(-3)
            )
            .contentShape(Circle())
            .onTapGesture {
                // No withAnimation: the re-skin must be instant, no background flash.
                theme.palette = palette
            }
            .accessibilityElement()
            .accessibilityLabel("\(palette.rawValue.capitalized) palette")
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("swatch-\(palette.rawValue)")
    }
}

#Preview {
    PaletteSwatchPicker()
        .padding()
        .background(Theme().bg)
        .environment(Theme())
}
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/You/Components/PaletteSwatchPicker.swift project.yml
git commit -m "feat(you): PaletteSwatchPicker — instant re-skin, no background flash"
```

---

## Task 9: `PreferenceRow` component (view assembly)

**Files:**
- Create: `Pulse/Features/You/Components/PreferenceRow.swift`

Two row kinds inside one rounded `inkFaint`-bordered card: a **value row** (label + value text + chevron — display-only in v1; tapping is inert per product decisions, units/rest editing is out of scope) and a **toggle row** (label + pill switch, `on` = `accent`). Use a SwiftUI `Toggle` with a custom tint for the toggle row.

- [ ] **Step 1: Create `Pulse/Features/You/Components/PreferenceRow.swift`**

```swift
import SwiftUI

struct PreferenceValueRow: View {
    let label: String
    let value: String

    @Environment(Theme.self) private var theme

    var body: some View {
        HStack {
            Text(label)
                .font(.custom("HankenGrotesk-Medium", size: 15))
                .foregroundStyle(theme.ink)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.ink.opacity(0.4))
                .padding(.leading, theme.spacing[1])
        }
        .padding(.horizontal, theme.spacing[4])
        .padding(.vertical, theme.spacing[3])
    }
}

struct PreferenceToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    @Environment(Theme.self) private var theme

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(label)
                .font(.custom("HankenGrotesk-Medium", size: 15))
                .foregroundStyle(theme.ink)
        }
        .tint(theme.accent)
        .padding(.horizontal, theme.spacing[4])
        .padding(.vertical, theme.spacing[2])
    }
}

#Preview {
    @Previewable @State var auto = true
    return VStack(spacing: 0) {
        PreferenceValueRow(label: "Units", value: "KG · METRIC")
        PreferenceValueRow(label: "Default rest timer", value: "90s")
        PreferenceToggleRow(label: "Auto-progress weight", isOn: $auto)
    }
    .background(Theme().surface, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme().inkFaint, lineWidth: 1.5))
    .padding()
    .background(Theme().bg)
    .environment(Theme())
}
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/You/Components/PreferenceRow.swift project.yml
git commit -m "feat(you): PreferenceRow — value + toggle settings rows"
```

---

## Task 10: Navigation routes for the You stack

**Files:**
- Create: `Pulse/Features/You/YouRoute.swift`

The three NavRows push destinations onto the You tab's `NavigationStack`. Destination screens (Stats / PRs / History) are owned by other backlog items; here we define the route enum and a placeholder destination so the navigation intent is real and testable. (Trivial enum — no separate TDD task; exercised by the UI test in Task 11.)

- [ ] **Step 1: Create `Pulse/Features/You/YouRoute.swift`**

```swift
import SwiftUI

/// Stack destinations reachable from the You tab. Real screens are owned by
/// BAK-15 (Stats), BAK-16 (Personal Records), and the History backlog item;
/// these stubs make the push navigation testable today.
enum YouRoute: Hashable {
    case stats
    case personalRecords
    case workoutHistory

    var title: String {
        switch self {
        case .stats: return "Stats"
        case .personalRecords: return "Personal Records"
        case .workoutHistory: return "Workout History"
        }
    }
}

struct YouRouteDestination: View {
    let route: YouRoute
    @Environment(Theme.self) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            Text(route.title)
                .font(.custom("Oswald", size: 28).weight(.bold))
                .foregroundStyle(theme.ink)
        }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("destination-\(route.title)")
    }
}
```

- [ ] **Step 2: Regenerate and build**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Features/You/YouRoute.swift project.yml
git commit -m "feat(you): YouRoute enum + placeholder stack destinations"
```

---

## Task 11: Assemble `YouView` + acceptance UI tests

**Files:**
- Modify: `Pulse/Features/You/YouView.swift`
- Create: `PulseUITests/YouScreenTests.swift`

This composes everything into the screen: top bar, profile header, MiniStat strip, YOUR DATA NavRows (in a `NavigationStack` with `navigationDestination`), PALETTE row + swatch picker, PREFERENCES card. It loads the model on `.task`, shows a `redacted` skeleton while `.loading`, and a non-fatal banner on `.failed` while still rendering. The model is constructed with the in-memory mocks. Accessibility identifiers make every AC assertable.

- [ ] **Step 1: Replace `Pulse/Features/You/YouView.swift`**

```swift
import SwiftUI

struct YouView: View {
    @Environment(Theme.self) private var theme
    @State private var model = YouModel(
        userRepo: MockUserRepository(),
        statsRepo: MockStatsRepository(),
        settingsRepo: MockSettingsRepository()
    )
    @State private var path: [YouRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.spacing[4]) {
                        topBar
                        profileHeader
                        miniStatStrip
                        if case .failed = model.phase { errorBanner }
                        yourDataSection
                        paletteSection
                        preferencesSection
                    }
                    .padding(theme.spacing[5])
                }
                .redacted(reason: model.phase == .loading ? .placeholder : [])
            }
            .navigationDestination(for: YouRoute.self) { YouRouteDestination(route: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await model.load() }
    }

    // MARK: Sections

    private var topBar: some View {
        HStack {
            Text("YOU")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(theme.inkSoft)
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("you-overflow") // inert in v1 (product decision)
        }
    }

    private var profileHeader: some View {
        HStack(spacing: theme.spacing[4]) {
            Text(model.profile?.avatarInitial ?? "?")
                .font(.custom("Oswald", size: 30).weight(.bold))
                .foregroundStyle(theme.onAccent)
                .frame(width: 56, height: 56)
                .background(theme.accent, in: Circle())
                .overlay(Circle().stroke(theme.ink, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text((model.profile?.displayName ?? "—") + ".")
                    .font(.custom("HankenGrotesk-ExtraBold", size: 26))
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Text(model.profile?.subtitle ?? "Member since — · —")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.inkSoft)
                    .lineLimit(1)
            }
        }
        .accessibilityIdentifier("you-profile-header")
    }

    private var miniStatStrip: some View {
        let stats = model.stats ?? .empty
        let vol = VolumeFormatter.compact(stats.totalVolumeKg)
        return HStack(spacing: theme.spacing[0]) {
            MiniStat(label: "STREAK", value: "\(stats.streakDays)", unit: "d", tint: .accent2)
            MiniStat(label: "SESSIONS", value: "\(stats.totalSessions)")
            MiniStat(label: "VOLUME", value: vol.value, unit: vol.unit, tint: .accent)
        }
    }

    private var errorBanner: some View {
        Text("Couldn't refresh your stats. Showing saved settings.")
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(theme.accent2)
            .accessibilityIdentifier("you-error-banner")
    }

    private var yourDataSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[1]) {
            eyebrow("YOUR DATA")
            NavRow(glyph: .symbol("chart.bar.fill"), tileColor: theme.accent,
                   name: "Stats", sub: "Volume, PRs, charts") { path.append(.stats) }
                .accessibilityIdentifier("navrow-stats")
            NavRow(glyph: .text("PR"), tileColor: theme.accent2,
                   name: "Personal records",
                   sub: "\(model.stats?.liftsTracked ?? 0) lifts tracked") {
                path.append(.personalRecords)
            }
            .accessibilityIdentifier("navrow-prs")
            NavRow(glyph: .text("H"), tileColor: theme.inkFaint, glyphColor: theme.ink,
                   name: "Workout history",
                   sub: "\(model.stats?.sessionsLogged ?? 0) sessions logged") {
                path.append(.workoutHistory)
            }
            .accessibilityIdentifier("navrow-history")
        }
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[1]) {
            eyebrow("PALETTE")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Theme")
                        .font(.custom("HankenGrotesk-Bold", size: 16))
                        .foregroundStyle(theme.ink)
                    Text(theme.palette.rawValue.capitalized)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.inkSoft)
                        .accessibilityIdentifier("palette-label")
                }
                Spacer()
                PaletteSwatchPicker()
            }
            .padding(.horizontal, theme.spacing[4])
            .padding(.vertical, theme.spacing[3])
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.spacing[3]))
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[1]) {
            eyebrow("PREFERENCES")
            VStack(spacing: 0) {
                PreferenceValueRow(label: "Units", value: model.settings.units.displayLabel)
                PreferenceValueRow(label: "Default rest timer", value: model.settings.restTimerLabel)
                PreferenceToggleRow(label: "Auto-progress weight", isOn: Binding(
                    get: { model.settings.autoProgressWeight },
                    set: { v in Task { await model.setAutoProgress(v) } }))
                    .accessibilityIdentifier("toggle-autoprogress")
                PreferenceToggleRow(label: "Sound on rest end", isOn: Binding(
                    get: { model.settings.soundOnRestEnd },
                    set: { v in Task { await model.setSoundOnRest(v) } }))
                    .accessibilityIdentifier("toggle-sound")
            }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.spacing[4]))
            .overlay(RoundedRectangle(cornerRadius: theme.spacing[4])
                .stroke(theme.inkFaint, lineWidth: 1.5))
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(theme.inkSoft)
            .padding(.top, theme.spacing[2])
    }
}

#Preview {
    YouView().environment(Theme())
}
```

- [ ] **Step 2: Write the acceptance UI tests `PulseUITests/YouScreenTests.swift`**

```swift
import XCTest

final class YouScreenTests: XCTestCase {
    private func launchOnYou() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["You"].tap()
        return app
    }

    // AC1–AC4: header, profile, mini-stats, nav rows render.
    func testRendersHeaderProfileStatsAndNavRows() {
        let app = launchOnYou()
        XCTAssertTrue(app.staticTexts["YOU"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["you-profile-header"].exists)
        XCTAssertTrue(app.staticTexts["STREAK"].exists)
        XCTAssertTrue(app.staticTexts["SESSIONS"].exists)
        XCTAssertTrue(app.staticTexts["VOLUME"].exists)
        XCTAssertTrue(app.buttons["navrow-stats"].exists)
        XCTAssertTrue(app.buttons["navrow-prs"].exists)
        XCTAssertTrue(app.buttons["navrow-history"].exists)
    }

    // AC5: tapping a NavRow pushes the matching destination.
    func testNavRowPushesStatsDestination() {
        let app = launchOnYou()
        app.buttons["navrow-stats"].tap()
        XCTAssertTrue(app.otherElements["destination-Stats"].waitForExistence(timeout: 3))
    }

    func testNavRowPushesPersonalRecordsDestination() {
        let app = launchOnYou()
        app.buttons["navrow-prs"].tap()
        XCTAssertTrue(app.otherElements["destination-Personal Records"].waitForExistence(timeout: 3))
    }

    // AC6–AC7: swatch picker shows both palettes; tapping switches + persists.
    func testSwatchPickerSwitchesAndPersistsPalette() {
        let app = launchOnYou()
        XCTAssertTrue(app.otherElements["swatch-coastal"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["swatch-mint"].exists)
        app.otherElements["swatch-mint"].tap()
        XCTAssertTrue(app.staticTexts["Mint"].waitForExistence(timeout: 2))

        // Relaunch: choice persists via "pulse-pal".
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launch()
        relaunched.tabBars.buttons["You"].tap()
        XCTAssertTrue(relaunched.staticTexts["Mint"].waitForExistence(timeout: 5))

        // Reset back to Coastal so the test is rerunnable.
        relaunched.otherElements["swatch-coastal"].tap()
    }

    // AC8–AC9: preferences card shows four rows; toggling flips state.
    func testPreferencesRenderAndToggleFlips() {
        let app = launchOnYou()
        XCTAssertTrue(app.staticTexts["Units"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["KG · METRIC"].exists)
        XCTAssertTrue(app.staticTexts["Default rest timer"].exists)
        XCTAssertTrue(app.staticTexts["90s"].exists)

        let auto = app.switches["toggle-autoprogress"]
        XCTAssertTrue(auto.exists)
        let before = auto.value as? String
        auto.tap()
        XCTAssertNotEqual(auto.value as? String, before)
    }
}
```

- [ ] **Step 3: Regenerate, build, and run the full You suite**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseUITests/YouScreenTests test
```
Expected: `TEST SUCCEEDED` (all five UI tests pass).

- [ ] **Step 4: Commit**

```bash
git add Pulse/Features/You/YouView.swift PulseUITests/YouScreenTests.swift project.yml
git commit -m "feat(you): assemble YouView + acceptance UI tests (AC1–AC9)"
```

---

## Task 12: Loading + failure edge-case UI coverage

**Files:**
- Modify: `Pulse/Features/You/YouView.swift`
- Modify: `PulseUITests/YouScreenTests.swift`

AC10–AC11 require that loading shows a non-blocking placeholder and that a failing repo still renders the screen with the palette picker usable. We drive these deterministically with launch arguments that select mock variants, then assert.

- [ ] **Step 1: Honor launch arguments in `YouView`'s model construction**

In `Pulse/Features/You/YouView.swift`, replace the `@State private var model = ...` initializer with a computed factory that reads launch args:

```swift
    @State private var model = YouView.makeModel()

    static func makeModel() -> YouModel {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-you-fail-stats") {
            return YouModel(userRepo: MockUserRepository(),
                            statsRepo: MockStatsRepository(shouldFail: true),
                            settingsRepo: MockSettingsRepository())
        }
        return YouModel(userRepo: MockUserRepository(),
                        statsRepo: MockStatsRepository(),
                        settingsRepo: MockSettingsRepository())
    }
```

- [ ] **Step 2: Add the failure-path UI test to `PulseUITests/YouScreenTests.swift`**

```swift
    // AC10–AC11: a failing stats repo still renders the screen and keeps the
    // palette picker usable (palette is local-only, never blocked).
    func testFailingStatsStillRendersAndPaletteStillWorks() {
        let app = XCUIApplication()
        app.launchArguments += ["-you-fail-stats"]
        app.launch()
        app.tabBars.buttons["You"].tap()

        XCTAssertTrue(app.otherElements["you-error-banner"].waitForExistence(timeout: 5))
        // Screen still renders profile + preferences with defaults.
        XCTAssertTrue(app.otherElements["you-profile-header"].exists)
        XCTAssertTrue(app.staticTexts["KG · METRIC"].exists)
        // Palette picker remains fully functional.
        app.otherElements["swatch-mint"].tap()
        XCTAssertTrue(app.staticTexts["Mint"].waitForExistence(timeout: 2))
        app.otherElements["swatch-coastal"].tap() // reset
    }
```

- [ ] **Step 3: Regenerate, build, and run the full You suite**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseUITests/YouScreenTests test
```
Expected: `TEST SUCCEEDED` (six UI tests pass, including the failure path).

- [ ] **Step 4: Commit**

```bash
git add Pulse/Features/You/YouView.swift PulseUITests/YouScreenTests.swift project.yml
git commit -m "test(you): loading placeholder + failing-repo edge cases (AC10–AC11)"
```

---

## Task 13: Full suite, review, and PR

**Files:** (none — verification + PR)

- [ ] **Step 1: Run the entire test suite green**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test
```
Expected: `TEST SUCCEEDED` — `ProfileModelsTests`, `VolumeFormatterTests`, `MockRepositoryTests`, `YouModelTests`, and `YouScreenTests` all pass alongside the existing foundation tests.

- [ ] **Step 2: Token-only audit (AC12)**

Run:
```bash
grep -rnE 'Color\(red:|Color\(\.sRGB|#[0-9A-Fa-f]{6}' Pulse/Features/You || echo "no hardcoded colors in Features/You"
```
Expected: `no hardcoded colors in Features/You` (hex literals live only in `Palette.swift`; the swatch picker reads `palette.tokens.accent` via `Color(hex:)`, which is the design-system constructor, not an ad-hoc literal).

- [ ] **Step 3: Code review + security review**

Invoke the `code-reviewer` agent on the diff, then run `/security-review`. Address any findings.

- [ ] **Step 4: Open the PR**

```bash
git push -u origin feature/BAK-13-you-settings
gh pr create --fill --base main \
  --title "feat: You / Settings tab (BAK-13)" \
  --body "Implements the You tab: profile header, MiniStat strip, YOUR DATA nav rows, live palette swatch picker, and preferences. UI-first against BAK-6 mock repositories. Closes BAK-13."
```
Expected: PR created; CI runs build + test.

---

## Self-Review notes

- **AC coverage:** AC1 (top bar eyebrow + ⋯) Task 11; AC2 (avatar/name/sub) Tasks 2 + 11; AC3 (3-up MiniStat colors) Tasks 3 + 6 + 11; AC4 (YOUR DATA NavRows) Tasks 7 + 11; AC5 (push navigation) Tasks 10 + 11; AC6–AC7 (swatch picker, instant re-skin, persist, no flash) Task 8, tested Task 11; AC8–AC9 (preferences rows + toggle persistence) Tasks 9 + 11; AC10–AC11 (loading placeholder, non-fatal failure) Tasks 5 + 12; AC12 (token-only) Task 13 audit.
- **Product decisions honored:** kg-only with no units toggle — Units row is display-only `KG · METRIC` (Task 2); volume formatting centralized in one helper (Task 3); palette persisted to `"pulse-pal"` via `Theme` (Task 8); `⋯` overflow is an inert placeholder (Task 11).
- **TDD vs view-assembly:** models, formatter, mocks, and `YouModel` follow strict red→green→commit (Tasks 2–5); views (MiniStat, NavRow, swatch picker, preference rows, YouView) are validated by `#Preview` + XCUITest (Tasks 6–12).
- **Repository discipline:** the screen binds only to `UserRepository`/`StatsRepository`/`SettingsRepository` protocols backed by in-memory mocks; no Supabase calls. Palette lives in `Theme`, not the settings repo, exactly as the spec states.
- **Open questions resolved by product decisions:** units = kg only, no editor (Q1/Q2 → display-only); failed save keeps optimistic value + surfaces non-fatal error (Q5); `⋯` inert (Q6); Notifications out of scope (Q7).
