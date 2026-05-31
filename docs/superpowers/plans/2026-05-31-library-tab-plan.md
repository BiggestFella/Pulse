# Library Tab Implementation Plan (BAK-10)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Library tab — the browse-and-organize surface for folders, recent workouts, and the exercise catalog grouped by muscle — plus the **Create chooser** sheet (Workout / Routine / Folder). The screen binds to the BAK-6 repository protocols backed by in-memory mocks; no Supabase calls. Delivers `LibraryModel` (`@Observable`), `LibraryView` with its row subviews and the Create chooser sheet, the display models, and the repository protocols + mocks this feature consumes.

**Architecture:** Native SwiftUI (iOS 17+), MVVM + `@Observable`. `LibraryView` is a tab root hosting a `NavigationStack`. The view renders state held by `LibraryModel`; the model loads data through two repository protocols (`LibraryRepository`, `ExerciseCatalogRepository`) and never touches Supabase directly. Display structs in `Core/Models` are UI-first projections. Navigation destinations (Exercise/Program/Folder Detail, the Builders) are separate features — this feature only routes to them via a `LibraryRoute` enum and a path-driven `navigationDestination`. All visuals come from `Theme` tokens.

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency (`async`/`await`), XcodeGen, XCTest + XCUITest.

**Prerequisites (must be built first):**
- **Design System (BAK-7)** — `Theme` / `Palette` tokens. These exist today (`Pulse/Core/DesignSystem/Theme.swift`, `Palette.swift`). The reusable components this screen needs (`FilterChip`, `FolderIcon`, `PrTag`, eyebrow text style, the `LibraryRow` container, the sheet chrome) are **created in Task 2 of this plan** under `Core/DesignSystem`, because BAK-7's component library is not yet in the repo. If BAK-7 has since landed those components, skip Task 2 and reuse them instead.
- **Data layer (BAK-6)** — the repository protocols, in-memory mocks, and sample fixtures. These are **created in Task 4 of this plan** under `Core/Data` because BAK-6's protocol set is not yet in the repo. If BAK-6 has since defined `LibraryRepository` / `ExerciseCatalogRepository`, reuse those and skip the protocol declarations, keeping only the mocks if needed.
- The buildable skeleton, `Theme`/`Palette`, and the domain models (`Exercise`, `Variation`, …) from the Foundation plan are already merged.

**Verification destination:** all `xcodebuild` test commands use `-destination 'platform=iOS Simulator,name=iPhone 17'`.

**Product-decision constraints (authoritative, from `docs/superpowers/specs/2026-05-31-product-decisions.md`):**
- **PR badge source is the derived est-1RM PR data set**, not an ad-hoc `pr` flag on `Exercise`. This feature's `CatalogExercise.hasPR` is supplied by the catalog repository (the mock seeds the same exercises the prototype flags: `bench`, `pulldown`, `deadlift`, `squat`, `ohp`). The PR-derivation engine itself is BAK-16/BAK-6 analytics; here we only consume a `hasPR: Bool` already computed upstream.
- **Decorative search field & inert placeholders** render as non-functional in v1.
- **kg-only**, Monday-start, etc. do not affect this screen (no weights/dates computed here).

---

## Task 1: Display models for the Library (TDD)

**Files:**
- Create: `Pulse/Core/Models/LibraryModels.swift`
- Create: `PulseTests/LibraryModelsTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/LibraryModelsTests.swift`**

```swift
import XCTest
@testable import Pulse

final class LibraryModelsTests: XCTestCase {
    func testFilterHasFiveCasesInOrder() {
        XCTAssertEqual(LibraryFilter.allCases,
                       [.all, .workouts, .folders, .exercises, .programs])
    }

    func testFilterDisplayLabelsAreTitleCase() {
        XCTAssertEqual(LibraryFilter.all.label, "All")
        XCTAssertEqual(LibraryFilter.exercises.label, "Exercises")
        XCTAssertEqual(LibraryFilter.programs.label, "Programs")
    }

    func testCatalogExerciseShowsVariationsSuffixOnlyWhenPositive() {
        let withVars = CatalogExercise(
            id: "cablefly", name: "Cable Fly", equipment: "CABLE",
            variationCount: 2, hasPR: false)
        let noVars = CatalogExercise(
            id: "incline", name: "Incline DB Press", equipment: "DUMBBELL",
            variationCount: 0, hasPR: false)
        XCTAssertEqual(withVars.subline, "CABLE · 2 variations")
        XCTAssertEqual(noVars.subline, "DUMBBELL")
    }

    func testFolderColorTokenMapsToThemeRole() {
        XCTAssertEqual(FolderColor.accent, LibraryFolder(
            id: "ppl", name: "Push / Pull / Legs", sub: "6 workouts",
            color: .accent, isProgram: true).color)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `LibraryFilter`, `CatalogExercise`, `LibraryFolder`, `FolderColor` undefined.

- [ ] **Step 3: Write `Pulse/Core/Models/LibraryModels.swift`**

```swift
import Foundation

/// Filter chips across the top of the Library. `.all` is the default.
enum LibraryFilter: String, CaseIterable, Equatable {
    case all, workouts, folders, exercises, programs

    /// Title-case label shown on the chip.
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Which `Theme` color role tints a folder icon. Keeps the model
/// palette-agnostic — `Theme` resolves the actual `Color`.
enum FolderColor: Equatable {
    case accent, accent2, inkFaint
}

/// A folder row in the Library. UI-first projection; the persisted shape
/// (folder contents, computed counts) is a BAK-6 concern.
struct LibraryFolder: Identifiable, Equatable {
    let id: String
    let name: String
    let sub: String
    let color: FolderColor
    let isProgram: Bool
}

/// A recent-workout row (name + sub-line such as "7 exercises · used today").
struct WorkoutSummary: Identifiable, Equatable {
    let id: String
    let name: String
    let sub: String
}

/// One catalog exercise row under the Exercises filter.
struct CatalogExercise: Identifiable, Equatable {
    let id: String
    let name: String
    let equipment: String
    let variationCount: Int
    let hasPR: Bool

    /// "{EQUIP}" or "{EQUIP} · N variations" when `variationCount > 0`.
    /// NB: prototype copy reads "1 variations"; we preserve that for parity.
    var subline: String {
        variationCount > 0
            ? "\(equipment) · \(variationCount) variations"
            : equipment
    }
}

/// A muscle group and its exercises, in catalog display order.
struct MuscleGroupCatalog: Identifiable, Equatable {
    var id: String { muscle }
    let muscle: String
    let items: [CatalogExercise]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (LibraryModelsTests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Core/Models/LibraryModels.swift PulseTests/LibraryModelsTests.swift
git commit -m "feat: Library display models (filter, folder, catalog projections)"
```

---

## Task 2: Design-system components the Library needs (FilterChip, FolderIcon, PrTag, eyebrow/row styles)

**Files:**
- Create: `Pulse/Core/DesignSystem/LibraryComponents.swift`

> Pure SwiftUI view assembly using `Theme` tokens — validated by previews and by the UI tests in Task 7. No line-by-line TDD. If BAK-7 already provides these, skip this task and reuse its components (keep the same call sites used below).

- [ ] **Step 1: Write `Pulse/Core/DesignSystem/LibraryComponents.swift`**

```swift
import SwiftUI

// MARK: - Eyebrow (Geist Mono, uppercase, letter-spaced)

/// Small uppercase label/section header. Pass `tappable` to render the
/// "BROWSE EXERCISES →" affordance style (still a plain Text — tap is wired
/// by the caller's `.onTapGesture`).
struct EyebrowText: View {
    let text: String
    @Environment(Theme.self) private var theme

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundStyle(theme.inkSoft)
    }
}

// MARK: - FilterChip

struct FilterChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void
    @Environment(Theme.self) private var theme

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .foregroundStyle(isOn ? theme.bg : theme.inkSoft)
                .background(isOn ? theme.ink : .clear)
                .overlay(
                    Capsule().strokeBorder(isOn ? theme.ink : theme.inkFaint,
                                           lineWidth: 1.5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - FolderIcon (tinted folder glyph drawn from tokens)

struct FolderIcon: View {
    let color: FolderColor
    @Environment(Theme.self) private var theme

    private var fill: Color {
        switch color {
        case .accent:   return theme.accent
        case .accent2:  return theme.accent2
        case .inkFaint: return theme.inkFaint
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 7)
                .fill(fill)
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(theme.ink, lineWidth: 1.5))
                .frame(width: 30, height: 30)
            // little folder tab
            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                .fill(fill)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                    .stroke(theme.ink, lineWidth: 1.5))
                .frame(width: 14, height: 6)
                .offset(x: 6, y: -3)
        }
        .frame(width: 30, height: 30)
    }
}

// MARK: - PrTag

struct PrTag: View {
    @Environment(Theme.self) private var theme

    var body: some View {
        Text("PR")
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(0.9)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(theme.onAccent)   // onAccent on an accent-2 fill
            .background(theme.accent2)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - LibraryRow (card-ish row container with a trailing chevron)

struct LibraryRow<Leading: View, Content: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var content: () -> Content
    var trailing: AnyView?
    let onTap: (() -> Void)?
    @Environment(Theme.self) private var theme

    init(onTap: (() -> Void)? = nil,
         @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
         @ViewBuilder content: @escaping () -> Content,
         trailing: AnyView? = nil) {
        self.onTap = onTap
        self.leading = leading
        self.content = content
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            leading()
            content()
            Spacer(minLength: 6)
            if let trailing { trailing }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.inkFaint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: theme.radiusCard)
            .strokeBorder(theme.inkFaint, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard))
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }
}

/// Name + sub-line block used inside `LibraryRow`. Single-line, tail-truncated.
struct RowNameBlock: View {
    let name: String
    let sub: String
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.ink)
                .lineLimit(1).truncationMode(.tail)
            Text(sub)
                .font(.system(size: 12))
                .foregroundStyle(theme.inkSoft)
                .lineLimit(1).truncationMode(.tail)
        }
    }
}
```

- [ ] **Step 2: Add previews (both palettes) at the bottom of the same file**

```swift
#Preview("Coastal") {
    let theme = Theme(); theme.palette = .coastal
    return VStack(spacing: 10) {
        HStack {
            FilterChip(label: "All", isOn: true) {}
            FilterChip(label: "Exercises", isOn: false) {}
        }
        LibraryRow(
            leading: { FolderIcon(color: .accent) },
            content: { RowNameBlock(name: "Push / Pull / Legs",
                                    sub: "6 workouts · active program") })
        LibraryRow(
            content: { RowNameBlock(name: "Barbell Bench Press",
                                    sub: "BARBELL") },
            trailing: AnyView(PrTag()))
        EyebrowText(text: "BROWSE EXERCISES →")
    }
    .padding()
    .background(theme.bg)
    .environment(theme)
}

#Preview("Mint") {
    let theme = Theme(); theme.palette = .mint
    return VStack(spacing: 10) {
        FilterChip(label: "All", isOn: true) {}
        LibraryRow(leading: { FolderIcon(color: .accent2) },
                   content: { RowNameBlock(name: "Cardio & Conditioning",
                                           sub: "4 workouts") })
    }
    .padding().background(theme.bg).environment(theme)
}
```

- [ ] **Step 3: Generate and build**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add Pulse/Core/DesignSystem/LibraryComponents.swift
git commit -m "feat: Library design-system components (chip, folder icon, PR tag, row)"
```

---

## Task 3: Sheet chrome component (Create chooser container)

**Files:**
- Create: `Pulse/Core/DesignSystem/PulseSheet.swift`

> Per product decisions, sheets use native `.sheet` + `.presentationDetents` with custom styled content (26pt top radius, scrim handled natively, drag handle). This task provides only the *content chrome* (handle, eyebrow, title, ✕). Presentation is wired in Task 6. Pure view assembly — validated by preview + the Task 7 UI test.

- [ ] **Step 1: Write `Pulse/Core/DesignSystem/PulseSheet.swift`**

```swift
import SwiftUI

/// Styled content chrome for a Pulse bottom sheet: drag handle, eyebrow,
/// title, and a ✕ close control. Host it inside a native `.sheet`.
struct PulseSheet<Content: View>: View {
    let eyebrow: String
    let title: String
    let onClose: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(theme.inkFaint)
                .frame(width: 40, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .accessibilityHidden(true)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    EyebrowText(text: eyebrow)
                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(theme.ink)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("sheet.close")
            }

            content()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 26,
                                          topTrailingRadius: 26))
    }
}

#Preview {
    let theme = Theme()
    return PulseSheet(eyebrow: "CREATE NEW",
                      title: "What are you making?",
                      onClose: {}) {
        Text("rows go here").foregroundStyle(theme.inkSoft)
    }
    .environment(theme)
}
```

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add Pulse/Core/DesignSystem/PulseSheet.swift
git commit -m "feat: PulseSheet styled bottom-sheet chrome"
```

---

## Task 4: Repository protocols + in-memory mocks (TDD)

**Files:**
- Create: `Pulse/Core/Data/LibraryRepository.swift`
- Create: `Pulse/Core/Data/ExerciseCatalogRepository.swift`
- Create: `Pulse/Core/Data/Mocks/MockLibraryRepository.swift`
- Create: `Pulse/Core/Data/Mocks/MockExerciseCatalogRepository.swift`
- Create: `PulseTests/MockRepositoryTests.swift`

> The protocols are the BAK-6 contract; the mocks are deterministic in-memory fixtures mirroring the design prototype. Logic (sample data, failure toggling) is TDD'd.

- [ ] **Step 1: Write the failing test `PulseTests/MockRepositoryTests.swift`**

```swift
import XCTest
@testable import Pulse

final class MockRepositoryTests: XCTestCase {
    func testLibraryMockReturnsThreeFoldersWithProgramFirst() async throws {
        let repo = MockLibraryRepository()
        let folders = try await repo.folders()
        XCTAssertEqual(folders.count, 3)
        XCTAssertEqual(folders.first?.name, "Push / Pull / Legs")
        XCTAssertTrue(folders.first?.isProgram == true)
        XCTAssertEqual(folders.first?.color, .accent)
        XCTAssertEqual(folders.filter { $0.isProgram }.count, 1)
    }

    func testLibraryMockReturnsThreeRecentWorkouts() async throws {
        let repo = MockLibraryRepository()
        let recent = try await repo.recentWorkouts()
        XCTAssertEqual(recent.map(\.name),
                       ["Chest & Tris", "Back & Bis", "Leg day"])
        XCTAssertEqual(recent.first?.sub, "7 exercises · used today")
    }

    func testCatalogMockGroupsByMuscleInOrderWithCounts() async throws {
        let repo = MockExerciseCatalogRepository()
        let catalog = try await repo.catalog()
        XCTAssertEqual(catalog.map(\.muscle),
                       ["Chest", "Back", "Legs", "Shoulders", "Triceps"])
        XCTAssertEqual(catalog.first?.items.count, 5)            // Chest = 5
    }

    func testCatalogMockFlagsPRsAndVariationCounts() async throws {
        let repo = MockExerciseCatalogRepository()
        let all = try await repo.catalog().flatMap(\.items)
        let pr = Set(all.filter(\.hasPR).map(\.id))
        XCTAssertEqual(pr, ["bench", "pulldown", "deadlift", "squat", "ohp"])
        let cablefly = all.first { $0.id == "cablefly" }
        XCTAssertEqual(cablefly?.variationCount, 2)
        let incline = all.first { $0.id == "incline" }
        XCTAssertEqual(incline?.variationCount, 0)
    }

    func testFailingMocksThrow() async {
        let lib = MockLibraryRepository(shouldFail: true)
        let cat = MockExerciseCatalogRepository(shouldFail: true)
        do { _ = try await lib.folders(); XCTFail("expected throw") }
        catch {}
        do { _ = try await cat.catalog(); XCTFail("expected throw") }
        catch {}
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `MockLibraryRepository` / `MockExerciseCatalogRepository` / protocols undefined.

- [ ] **Step 3: Write `Pulse/Core/Data/LibraryRepository.swift`**

```swift
import Foundation

/// Reads folders and recent workouts for the Library tab.
/// (BAK-6 contract; consumed here via an in-memory mock.)
protocol LibraryRepository: Sendable {
    func folders() async throws -> [LibraryFolder]
    func recentWorkouts() async throws -> [WorkoutSummary]
}
```

- [ ] **Step 4: Write `Pulse/Core/Data/ExerciseCatalogRepository.swift`**

```swift
import Foundation

/// Reads the exercise catalog grouped by muscle, with PR flags and
/// variation counts already resolved upstream. (BAK-6 contract.)
protocol ExerciseCatalogRepository: Sendable {
    func catalog() async throws -> [MuscleGroupCatalog]
}

/// Shared error for the in-memory mocks' failure path.
struct RepositoryError: Error, Equatable { let message: String }
```

- [ ] **Step 5: Write `Pulse/Core/Data/Mocks/MockLibraryRepository.swift`**

```swift
import Foundation

/// Deterministic in-memory Library data mirroring the design prototype.
struct MockLibraryRepository: LibraryRepository {
    var shouldFail = false

    func folders() async throws -> [LibraryFolder] {
        if shouldFail { throw RepositoryError(message: "folders failed") }
        return [
            LibraryFolder(id: "ppl", name: "Push / Pull / Legs",
                          sub: "6 workouts · active program",
                          color: .accent, isProgram: true),
            LibraryFolder(id: "cardio", name: "Cardio & Conditioning",
                          sub: "4 workouts", color: .accent2, isProgram: false),
            LibraryFolder(id: "oneoffs", name: "One-offs",
                          sub: "7 workouts", color: .inkFaint, isProgram: false),
        ]
    }

    func recentWorkouts() async throws -> [WorkoutSummary] {
        if shouldFail { throw RepositoryError(message: "recent failed") }
        return [
            WorkoutSummary(id: "chesttris", name: "Chest & Tris",
                           sub: "7 exercises · used today"),
            WorkoutSummary(id: "backbis", name: "Back & Bis",
                           sub: "6 exercises · 5d ago"),
            WorkoutSummary(id: "legday", name: "Leg day",
                           sub: "5 exercises · 7d ago"),
        ]
    }
}
```

- [ ] **Step 6: Write `Pulse/Core/Data/Mocks/MockExerciseCatalogRepository.swift`**

```swift
import Foundation

/// Deterministic in-memory catalog mirroring the prototype's EXERCISE_CATALOG.
/// `hasPR` reflects exercises with a derived est-1RM PR (per product decisions),
/// pre-resolved here for the UI-first build.
struct MockExerciseCatalogRepository: ExerciseCatalogRepository {
    var shouldFail = false

    func catalog() async throws -> [MuscleGroupCatalog] {
        if shouldFail { throw RepositoryError(message: "catalog failed") }
        return [
            MuscleGroupCatalog(muscle: "Chest", items: [
                CatalogExercise(id: "flat", name: "Flat Machine Chest Press",
                                equipment: "MACHINE", variationCount: 3, hasPR: false),
                CatalogExercise(id: "incline", name: "Incline DB Press",
                                equipment: "DUMBBELL", variationCount: 0, hasPR: false),
                CatalogExercise(id: "closegrip", name: "Close Grip DB Press",
                                equipment: "DUMBBELL", variationCount: 0, hasPR: false),
                CatalogExercise(id: "cablefly", name: "Cable Fly",
                                equipment: "CABLE", variationCount: 2, hasPR: false),
                CatalogExercise(id: "bench", name: "Barbell Bench Press",
                                equipment: "BARBELL", variationCount: 0, hasPR: true),
            ]),
            MuscleGroupCatalog(muscle: "Back", items: [
                CatalogExercise(id: "pulldown", name: "Lat Pulldown",
                                equipment: "CABLE", variationCount: 3, hasPR: true),
                CatalogExercise(id: "row", name: "Seated Cable Row",
                                equipment: "CABLE", variationCount: 0, hasPR: false),
                CatalogExercise(id: "deadlift", name: "Deadlift",
                                equipment: "BARBELL", variationCount: 0, hasPR: true),
            ]),
            MuscleGroupCatalog(muscle: "Legs", items: [
                CatalogExercise(id: "squat", name: "Back Squat",
                                equipment: "BARBELL", variationCount: 0, hasPR: true),
                CatalogExercise(id: "legpress", name: "Leg Press",
                                equipment: "MACHINE", variationCount: 0, hasPR: false),
                CatalogExercise(id: "legext", name: "Leg Extension",
                                equipment: "MACHINE", variationCount: 0, hasPR: false),
            ]),
            MuscleGroupCatalog(muscle: "Shoulders", items: [
                CatalogExercise(id: "ohp", name: "Overhead Press",
                                equipment: "BARBELL", variationCount: 0, hasPR: true),
                CatalogExercise(id: "shoulder", name: "Shoulder Press Machine",
                                equipment: "MACHINE", variationCount: 0, hasPR: false),
                CatalogExercise(id: "latraise", name: "Lateral Raise",
                                equipment: "CABLE", variationCount: 2, hasPR: false),
            ]),
            MuscleGroupCatalog(muscle: "Triceps", items: [
                CatalogExercise(id: "tricable", name: "Tricep Cable Ext.",
                                equipment: "CABLE", variationCount: 2, hasPR: false),
            ]),
        ]
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (MockRepositoryTests green).

- [ ] **Step 8: Commit**

```bash
git add Pulse/Core/Data PulseTests/MockRepositoryTests.swift
git commit -m "feat: Library + catalog repository protocols and in-memory mocks"
```

---

## Task 5: `LibraryModel` (`@Observable`) — load / retry / filter / sheet (TDD)

**Files:**
- Create: `Pulse/Features/Library/LibraryModel.swift`
- Create: `PulseTests/LibraryModelTests.swift`

- [ ] **Step 1: Write the failing test `PulseTests/LibraryModelTests.swift`**

```swift
import XCTest
@testable import Pulse

@MainActor
final class LibraryModelTests: XCTestCase {

    private func makeModel(fail: Bool = false) -> LibraryModel {
        LibraryModel(
            library: MockLibraryRepository(shouldFail: fail),
            catalog: MockExerciseCatalogRepository(shouldFail: fail))
    }

    func testDefaultFilterIsAll() {
        XCTAssertEqual(makeModel().selectedFilter, .all)
    }

    func testInitialStateIsLoading() {
        if case .loading = makeModel().loadState { } else { XCTFail() }
    }

    func testLoadPopulatesEverythingAndMarksLoaded() async {
        let model = makeModel()
        await model.load()
        if case .loaded = model.loadState { } else { XCTFail("expected loaded") }
        XCTAssertEqual(model.folders.count, 3)
        XCTAssertEqual(model.recentWorkouts.count, 3)
        XCTAssertEqual(model.catalog.map(\.muscle).first, "Chest")
    }

    func testLoadFailureSetsErrorState() async {
        let model = makeModel(fail: true)
        await model.load()
        if case .error = model.loadState { } else { XCTFail("expected error") }
        XCTAssertTrue(model.folders.isEmpty)
    }

    func testRetryRecoversWithSucceedingRepos() async {
        let model = makeModel(fail: true)
        await model.load()
        guard case .error = model.loadState else { return XCTFail() }
        // swap in succeeding repos and retry
        model.replaceRepositories(
            library: MockLibraryRepository(),
            catalog: MockExerciseCatalogRepository())
        await model.retry()
        if case .loaded = model.loadState { } else { XCTFail("expected loaded") }
        XCTAssertEqual(model.folders.count, 3)
    }

    func testSelectUpdatesFilter() {
        let model = makeModel()
        model.select(.exercises)
        XCTAssertEqual(model.selectedFilter, .exercises)
    }

    func testCatalogExposedInCatalogOrder() async {
        let model = makeModel()
        await model.load()
        model.select(.exercises)
        XCTAssertEqual(model.catalog.map(\.muscle),
                       ["Chest", "Back", "Legs", "Shoulders", "Triceps"])
    }

    func testPresentAndDismissCreate() {
        let model = makeModel()
        XCTAssertFalse(model.isCreateSheetPresented)
        model.presentCreate()
        XCTAssertTrue(model.isCreateSheetPresented)
        model.dismissCreate()
        XCTAssertFalse(model.isCreateSheetPresented)
    }

    func testIsAllEmptyOnlyWhenFoldersAndRecentEmpty() async {
        let model = LibraryModel(
            library: EmptyLibraryRepository(),
            catalog: MockExerciseCatalogRepository())
        await model.load()
        XCTAssertTrue(model.isAllEmpty)
    }
}

/// Local empty stub for the empty-state test.
private struct EmptyLibraryRepository: LibraryRepository {
    func folders() async throws -> [LibraryFolder] { [] }
    func recentWorkouts() async throws -> [WorkoutSummary] { [] }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: FAIL — `LibraryModel` undefined.

- [ ] **Step 3: Write `Pulse/Features/Library/LibraryModel.swift`**

```swift
import Foundation
import Observation

enum LoadState: Equatable {
    case loading, loaded
    case error(String)
}

@MainActor
@Observable
final class LibraryModel {
    var selectedFilter: LibraryFilter = .all
    var loadState: LoadState = .loading
    var folders: [LibraryFolder] = []
    var recentWorkouts: [WorkoutSummary] = []
    var catalog: [MuscleGroupCatalog] = []
    var isCreateSheetPresented = false

    private var library: LibraryRepository
    private var catalogRepo: ExerciseCatalogRepository

    init(library: LibraryRepository, catalog: ExerciseCatalogRepository) {
        self.library = library
        self.catalogRepo = catalog
    }

    /// True when, under the All view, there is nothing to show.
    var isAllEmpty: Bool { folders.isEmpty && recentWorkouts.isEmpty }

    func load() async {
        loadState = .loading
        do {
            async let f = library.folders()
            async let r = library.recentWorkouts()
            async let c = catalogRepo.catalog()
            let (folders, recent, catalog) = try await (f, r, c)
            self.folders = folders
            self.recentWorkouts = recent
            self.catalog = catalog
            self.loadState = .loaded
        } catch {
            self.folders = []
            self.recentWorkouts = []
            self.catalog = []
            self.loadState = .error(
                (error as? RepositoryError)?.message ?? "Couldn’t load your library.")
        }
    }

    func retry() async { await load() }

    func select(_ filter: LibraryFilter) { selectedFilter = filter }

    func presentCreate() { isCreateSheetPresented = true }
    func dismissCreate() { isCreateSheetPresented = false }

    /// Test seam for the retry-recovery path.
    func replaceRepositories(library: LibraryRepository,
                             catalog: ExerciseCatalogRepository) {
        self.library = library
        self.catalogRepo = catalog
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (LibraryModelTests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/Features/Library/LibraryModel.swift PulseTests/LibraryModelTests.swift
git commit -m "feat: LibraryModel (load/retry/filter/create-sheet) with parallel repo loads"
```

---

## Task 6: `LibraryView` + Create chooser sheet + routing (view assembly)

**Files:**
- Modify: `Pulse/Features/Library/LibraryView.swift` (replace placeholder)
- Create: `Pulse/Features/Library/LibraryRoute.swift`
- Create: `Pulse/Features/Library/CreateChooserSheet.swift`
- Create: `Pulse/Features/Library/LibraryRowViews.swift`

> Pure SwiftUI view assembly using `Theme` tokens + the Task 2/3 components. Validated by previews and the Task 7 UI tests. No line-by-line TDD.

- [ ] **Step 1: Write `Pulse/Features/Library/LibraryRoute.swift`**

```swift
import Foundation

/// Navigation destinations the Library pushes onto its NavigationStack.
/// The destination *screens* are separate features; here we only carry the
/// routing intent so UI tests can assert the right push happened.
enum LibraryRoute: Hashable {
    case exerciseDetail(id: String)
    case programDetail(folderID: String)
    case folderDetail(folderID: String)
    case workoutBuilder
    case routineBuilder
    case folderCreate
}
```

- [ ] **Step 2: Write `Pulse/Features/Library/LibraryRowViews.swift`**

```swift
import SwiftUI

/// One folder row. Program folder → programDetail; others → folderDetail.
struct FolderRow: View {
    let folder: LibraryFolder
    let onTap: () -> Void

    var body: some View {
        LibraryRow(
            onTap: onTap,
            leading: { FolderIcon(color: folder.color) },
            content: { RowNameBlock(name: folder.name, sub: folder.sub) })
        .accessibilityIdentifier("folder.\(folder.id)")
    }
}

/// One recent-workout row.
struct RecentRow: View {
    let workout: WorkoutSummary

    var body: some View {
        LibraryRow(
            content: { RowNameBlock(name: workout.name, sub: workout.sub) })
        .accessibilityIdentifier("recent.\(workout.id)")
    }
}

/// One catalog exercise row, with an optional PR tag.
struct CatalogRow: View {
    let exercise: CatalogExercise
    let onTap: () -> Void

    var body: some View {
        LibraryRow(
            onTap: onTap,
            content: { RowNameBlock(name: exercise.name, sub: exercise.subline) },
            trailing: exercise.hasPR ? AnyView(PrTag()) : nil)
        .accessibilityIdentifier("exercise.\(exercise.id)")
    }
}
```

- [ ] **Step 3: Write `Pulse/Features/Library/CreateChooserSheet.swift`**

```swift
import SwiftUI

/// The "What are you making?" chooser. Each pick dismisses (handled by the
/// host) and routes via `onPick`.
struct CreateChooserSheet: View {
    let onPick: (LibraryRoute) -> Void
    let onClose: () -> Void
    @Environment(Theme.self) private var theme

    var body: some View {
        PulseSheet(eyebrow: "CREATE NEW",
                   title: "What are you making?",
                   onClose: onClose) {
            VStack(spacing: 8) {
                option(icon: "bolt.fill", tile: theme.accent, glyph: theme.onAccent,
                       name: "Workout", sub: "A single session you can run",
                       id: "create.workout") { onPick(.workoutBuilder) }
                option(icon: "calendar", tile: theme.accent2, glyph: theme.onAccent,
                       name: "Routine", sub: "A multi-week program of workouts",
                       id: "create.routine") { onPick(.routineBuilder) }
                option(icon: "square.grid.2x2.fill", tile: theme.inkFaint, glyph: theme.ink,
                       name: "Folder", sub: "Group workouts together",
                       id: "create.folder") { onPick(.folderCreate) }
            }
        }
    }

    @ViewBuilder
    private func option(icon: String, tile: Color, glyph: Color,
                        name: String, sub: String, id: String,
                        action: @escaping () -> Void) -> some View {
        LibraryRow(
            onTap: action,
            leading: {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(tile)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(glyph)
                }
                .frame(width: 38, height: 38)
            },
            content: { RowNameBlock(name: name, sub: sub) })
        .accessibilityIdentifier(id)
    }
}

#Preview {
    let theme = Theme()
    return CreateChooserSheet(onPick: { _ in }, onClose: {})
        .environment(theme)
}
```

- [ ] **Step 4: Write the new `Pulse/Features/Library/LibraryView.swift`**

```swift
import SwiftUI

struct LibraryView: View {
    @Environment(Theme.self) private var theme
    @State private var model: LibraryModel
    @State private var path: [LibraryRoute] = []

    init(model: LibraryModel? = nil) {
        _model = State(initialValue: model ?? LibraryModel(
            library: MockLibraryRepository(),
            catalog: MockExerciseCatalogRepository()))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    Text("Library.")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(theme.ink)
                        .accessibilityIdentifier("library.h1")
                    searchField
                    filterRow
                    body
                        .padding(.top, 14)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationDestination(for: LibraryRoute.self) { route in
                RouteDestinationView(route: route)
            }
            .sheet(isPresented: Bindable(model).isCreateSheetPresented) {
                CreateChooserSheet(
                    onPick: { route in
                        model.dismissCreate()
                        path.append(route)
                    },
                    onClose: { model.dismissCreate() })
                    .presentationDetents([.height(340)])
                    .presentationDragIndicator(.hidden)
                    .environment(theme)
            }
            .task { if case .loading = model.loadState { await model.load() } }
        }
    }

    // MARK: top bar

    private var topBar: some View {
        HStack {
            EyebrowText(text: "LIBRARY")
            Spacer()
            Button { model.presentCreate() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(theme.inkFaint, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library.create")
        }
    }

    private var searchField: some View {
        HStack {
            Text("Search workouts, exercises…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.inkSoft)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(theme.inkFaint, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.top, 10)
        .accessibilityIdentifier("library.search")
    }

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LibraryFilter.allCases, id: \.self) { f in
                    FilterChip(label: f.label,
                               isOn: model.selectedFilter == f) {
                        model.select(f)
                    }
                    .accessibilityIdentifier("chip.\(f.rawValue)")
                }
            }
        }
        .padding(.top, 12)
    }

    // MARK: body switch

    @ViewBuilder private var body: some View {
        switch model.loadState {
        case .loading:
            loadingState
        case .error(let message):
            errorState(message)
        case .loaded:
            if model.selectedFilter == .exercises {
                exercisesBody
            } else {
                defaultBody
            }
        }
    }

    private var loadingState: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .accessibilityIdentifier("library.loading")
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(theme.inkSoft)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await model.retry() } }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(Capsule().strokeBorder(theme.ink, lineWidth: 1.5))
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("library.retry")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .accessibilityIdentifier("library.error")
    }

    // MARK: default (All / Workouts / Folders / Programs) body

    @ViewBuilder private var defaultBody: some View {
        if model.isAllEmpty {
            emptyState("Nothing here yet. Tap + to build your first workout.")
                .accessibilityIdentifier("library.empty")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                EyebrowText(text: "FOLDERS · \(model.folders.count)")
                ForEach(model.folders) { folder in
                    FolderRow(folder: folder) {
                        path.append(folder.isProgram
                            ? .programDetail(folderID: folder.id)
                            : .folderDetail(folderID: folder.id))
                    }
                }
                HStack {
                    EyebrowText(text: "RECENT")
                    Spacer()
                    EyebrowText(text: "BROWSE EXERCISES →")
                        .contentShape(Rectangle())
                        .onTapGesture { model.select(.exercises) }
                        .accessibilityIdentifier("library.browseExercises")
                }
                .padding(.top, 6)
                ForEach(model.recentWorkouts) { RecentRow(workout: $0) }
            }
        }
    }

    // MARK: exercises body

    @ViewBuilder private var exercisesBody: some View {
        if model.catalog.allSatisfy({ $0.items.isEmpty }) {
            emptyState("No exercises in your catalog yet.")
                .accessibilityIdentifier("catalog.empty")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.catalog) { group in
                    EyebrowText(text: "\(group.muscle.uppercased()) · \(group.items.count)")
                        .padding(.top, 8)
                    ForEach(group.items) { ex in
                        CatalogRow(exercise: ex) {
                            path.append(.exerciseDetail(id: ex.id))
                        }
                    }
                }
            }
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(theme.inkSoft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
    }
}

/// Lightweight stand-in for destination screens owned by other features.
/// Renders an identifiable marker so UI tests can assert the right push.
private struct RouteDestinationView: View {
    let route: LibraryRoute
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack {
            Text(marker)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.ink)
                .accessibilityIdentifier("route.\(marker)")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
    }

    private var marker: String {
        switch route {
        case .exerciseDetail(let id):   return "exdetail:\(id)"
        case .programDetail(let id):    return "program:\(id)"
        case .folderDetail(let id):     return "folder:\(id)"
        case .workoutBuilder:           return "builder:workout"
        case .routineBuilder:           return "builder:routine"
        case .folderCreate:             return "builder:folder"
        }
    }
}

#Preview("Library — Coastal") {
    let theme = Theme(); theme.palette = .coastal
    return LibraryView().environment(theme)
}

#Preview("Library — Mint") {
    let theme = Theme(); theme.palette = .mint
    return LibraryView().environment(theme)
}
```

- [ ] **Step 5: Ensure `Theme` is injected at the app root (so `LibraryView` resolves it)**

Open `Pulse/App/PulseApp.swift`. If it does not already inject a `Theme`, update it:

```swift
import SwiftUI

@main
struct PulseApp: App {
    @State private var theme = Theme()
    var body: some Scene {
        WindowGroup {
            AppShell().environment(theme)
        }
    }
}
```

(If `AppShell`/`PulseApp` already inject `Theme`, leave them unchanged.)

- [ ] **Step 6: Generate and build**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Run the full unit-test suite (confirm nothing regressed)**

Run: `xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=iOS Simulator,name=iPhone 17' test`
Expected: PASS (all model/mock/palette/workout tests green).

- [ ] **Step 8: Commit**

```bash
git add Pulse/Features/Library Pulse/App/PulseApp.swift
git commit -m "feat: Library tab screen, Create chooser sheet, and routing"
```

---

## Task 7: Acceptance / UI tests (XCUITest)

**Files:**
- Create: `PulseUITests/LibraryTabTests.swift`

> XCUITest exercising the acceptance criteria. Relies on the accessibility identifiers wired in Tasks 6. Launches into the Library tab.

- [ ] **Step 1: Write `PulseUITests/LibraryTabTests.swift`**

```swift
import XCTest

final class LibraryTabTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        // Navigate to the Library tab.
        app.tabBars.buttons["Library"].tap()
    }

    // AC1
    func testLibraryHeaderChromeAndChips() {
        XCTAssertTrue(app.staticTexts["library.h1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["LIBRARY"].exists)
        XCTAssertTrue(app.otherElements["library.search"].exists
                      || app.staticTexts["Search workouts, exercises…"].exists)
        for f in ["all", "workouts", "folders", "exercises", "programs"] {
            XCTAssertTrue(app.buttons["chip.\(f)"].exists, "missing chip \(f)")
        }
    }

    // AC2
    func testAllViewShowsFoldersAndRecent() {
        XCTAssertTrue(app.staticTexts["FOLDERS · 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["folder.ppl"].exists)
        XCTAssertTrue(app.otherElements["folder.cardio"].exists)
        XCTAssertTrue(app.staticTexts["RECENT"].exists)
        XCTAssertTrue(app.staticTexts["BROWSE EXERCISES →"].exists)
        XCTAssertTrue(app.otherElements["recent.chesttris"].exists)
    }

    // AC6 + AC3
    func testBrowseExercisesSwitchesToCatalog() {
        app.staticTexts["BROWSE EXERCISES →"].tap()
        XCTAssertTrue(app.staticTexts["CHEST · 5"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["BACK · 3"].exists)
        XCTAssertTrue(app.otherElements["exercise.bench"].exists)
    }

    // AC3 — variation sublines + PR badges
    func testExercisesViaChipShowGroupsAndPRs() {
        app.buttons["chip.exercises"].tap()
        XCTAssertTrue(app.staticTexts["CHEST · 5"].waitForExistence(timeout: 5))
        // PR tag is present somewhere in the catalog.
        XCTAssertTrue(app.staticTexts["PR"].firstMatch.exists)
    }

    // AC4
    func testTappingExerciseRoutesToExerciseDetail() {
        app.buttons["chip.exercises"].tap()
        app.otherElements["exercise.bench"].tap()
        XCTAssertTrue(app.staticTexts["route.exdetail:bench"].waitForExistence(timeout: 5))
    }

    // AC5
    func testTappingProgramFolderRoutesToProgramDetail() {
        app.otherElements["folder.ppl"].tap()
        XCTAssertTrue(app.staticTexts["route.program:ppl"].waitForExistence(timeout: 5))
    }

    // AC7 — create chooser presents; backdrop/✕ dismisses
    func testCreateChooserPresentsAndCloses() {
        app.buttons["library.create"].tap()
        XCTAssertTrue(app.staticTexts["What are you making?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["CREATE NEW"].exists)
        XCTAssertTrue(app.otherElements["create.workout"].exists)
        XCTAssertTrue(app.otherElements["create.routine"].exists)
        XCTAssertTrue(app.otherElements["create.folder"].exists)
        app.buttons["sheet.close"].tap()
        XCTAssertFalse(app.staticTexts["What are you making?"].waitForExistence(timeout: 2))
    }

    // AC8
    func testSelectingWorkoutRoutesToBuilder() {
        app.buttons["library.create"].tap()
        XCTAssertTrue(app.otherElements["create.workout"].waitForExistence(timeout: 5))
        app.otherElements["create.workout"].tap()
        XCTAssertTrue(app.staticTexts["route.builder:workout"].waitForExistence(timeout: 5))
    }
}
```

- [ ] **Step 2: Run the UI tests**

Run:
```bash
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseUITests/LibraryTabTests test
```
Expected: PASS (all `LibraryTabTests` green). If any element is not hittable because it's off-screen, add a `.swipeUp()` before the assertion in that test.

- [ ] **Step 3: Commit**

```bash
git add PulseUITests/LibraryTabTests.swift
git commit -m "test: Library tab acceptance/UI tests"
```

---

## Task 8: Empty / error state UI tests via launch arguments (TDD-supported view states)

**Files:**
- Modify: `Pulse/App/AppShell.swift` (read launch args to inject a state-fixture model — test-only)
- Modify: `Pulse/Features/Library/LibraryView.swift` (accept an injected model — already supported via `init(model:)`)
- Create/extend: `PulseUITests/LibraryStatesTests.swift`

> Loading/empty/error are easiest to assert deterministically by injecting a fixture model behind a launch argument. This keeps production defaults (mock data) intact.

- [ ] **Step 1: Add a test-only fixture hook. Edit `Pulse/App/AppShell.swift`**

Add a helper that builds the Library model from a launch argument, and pass it into `LibraryView`:

```swift
import SwiftUI

struct AppShell: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "bolt.fill") }
            LibraryView(model: Self.libraryModelForLaunch())
                .tabItem { Label("Library", systemImage: "square.stack.fill") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "calendar") }
            YouView()
                .tabItem { Label("You", systemImage: "person.fill") }
        }
    }

    /// Returns a Library model configured for UI-test fixtures, or nil for the
    /// production default (live mocks).
    @MainActor
    static func libraryModelForLaunch() -> LibraryModel? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-libraryState") {
            guard let i = args.firstIndex(of: "-libraryState"),
                  i + 1 < args.count else { return nil }
            switch args[i + 1] {
            case "error":
                return LibraryModel(library: MockLibraryRepository(shouldFail: true),
                                    catalog: MockExerciseCatalogRepository(shouldFail: true))
            case "empty":
                return LibraryModel(library: EmptyLibraryRepositoryFixture(),
                                    catalog: MockExerciseCatalogRepository())
            default:
                return nil
            }
        }
        return nil
    }
}

/// UI-test fixture: returns no folders/recent to drive the empty state.
struct EmptyLibraryRepositoryFixture: LibraryRepository {
    func folders() async throws -> [LibraryFolder] { [] }
    func recentWorkouts() async throws -> [WorkoutSummary] { [] }
}

#Preview { AppShell().environment(Theme()) }
```

- [ ] **Step 2: Confirm `LibraryView` uses the injected model when non-nil**

`LibraryView.init(model:)` already falls back to live mocks when `model == nil` (Task 6). When `AppShell` passes a fixture model, that state is used. No further change needed.

- [ ] **Step 3: Write `PulseUITests/LibraryStatesTests.swift`**

```swift
import XCTest

final class LibraryStatesTests: XCTestCase {
    // AC9 — error state + retry affordance
    func testErrorStateShowsRetry() {
        let app = XCUIApplication()
        app.launchArguments += ["-libraryState", "error"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.otherElements["library.error"].waitForExistence(timeout: 5)
                      || app.buttons["library.retry"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library.retry"].exists)
        // Create chooser still openable in error state.
        app.buttons["library.create"].tap()
        XCTAssertTrue(app.staticTexts["What are you making?"].waitForExistence(timeout: 5))
    }

    // AC9 — empty all-view shows an empty state, not bare headers
    func testEmptyStateShownWhenNoFoldersOrRecent() {
        let app = XCUIApplication()
        app.launchArguments += ["-libraryState", "empty"]
        app.launch()
        app.tabBars.buttons["Library"].tap()
        XCTAssertTrue(app.otherElements["library.empty"].waitForExistence(timeout: 5)
                      || app.staticTexts.matching(
                            NSPredicate(format: "label CONTAINS 'Nothing here yet'"))
                            .firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["FOLDERS · 0"].exists)
    }
}
```

- [ ] **Step 4: Build and run the state tests**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:PulseUITests/LibraryStatesTests test
```
Expected: PASS (both state tests green).

- [ ] **Step 5: Commit**

```bash
git add Pulse/App/AppShell.swift PulseUITests/LibraryStatesTests.swift
git commit -m "test: Library empty/error UI states via launch-argument fixtures"
```

---

## Task 9: Full verification + palette parity check

**Files:** none (verification only)

- [ ] **Step 1: Run the entire test suite**

Run:
```bash
xcodegen generate
xcodebuild -project Pulse.xcodeproj -scheme Pulse \
  -destination 'platform=iOS Simulator,name=iPhone 17' clean test
```
Expected: `TEST SUCCEEDED` — `PaletteTests`, `WorkoutModelsTests`, `LibraryModelsTests`, `MockRepositoryTests`, `LibraryModelTests`, `PulseUITests`, `LibraryTabTests`, `LibraryStatesTests` all green.

- [ ] **Step 2: Manual palette-parity check (AC10)**

Open `Pulse/Features/Library/LibraryView.swift` in Xcode, run both the "Library — Coastal" and "Library — Mint" previews. Confirm: folder icons (accent / accent-2 / ink-faint), chips, PR tags, and sheet tiles recolor with the palette; no hardcoded hex anywhere in the new files.

- [ ] **Step 3: Grep for hardcoded colors in the new files (AC10 guard)**

Run:
```bash
grep -REn "Color\(red:|Color\(\.sRGB|#[0-9A-Fa-f]{6}|\.blue|\.green|\.orange" \
  Pulse/Features/Library Pulse/Core/DesignSystem/LibraryComponents.swift \
  Pulse/Core/DesignSystem/PulseSheet.swift || echo "clean: no hardcoded colors"
```
Expected: `clean: no hardcoded colors` (the only hex literals live in `Palette.swift`, untouched here).

- [ ] **Step 4: Final commit (if Step 1–3 surfaced any fixes)**

```bash
git add -A
git commit -m "chore: Library tab verification fixes" || echo "nothing to commit"
```

---

## Self-Review notes

- **Acceptance-criteria coverage:**
  - AC1 → Task 6 (top bar, H1, search, chips) + `testLibraryHeaderChromeAndChips`.
  - AC2 → Task 6 default body + `testAllViewShowsFoldersAndRecent`.
  - AC3 → Task 6 exercises body + `testExercisesViaChipShowGroupsAndPRs`; `CatalogExercise.subline` unit test (Task 1).
  - AC4 → `testTappingExerciseRoutesToExerciseDetail`.
  - AC5 → `LibraryFolder.isProgram` routing + `testTappingProgramFolderRoutesToProgramDetail`; non-program folders route to `folderDetail`.
  - AC6 → `testBrowseExercisesSwitchesToCatalog`.
  - AC7 → Create chooser + `testCreateChooserPresentsAndCloses`.
  - AC8 → `testSelectingWorkoutRoutesToBuilder` (Routine/Folder analogous via the same `onPick`).
  - AC9 → Task 8 empty/error launch-arg tests; loading via `LibraryModel` initial state + `testInitialStateIsLoading`.
  - AC10 → previews + the hardcoded-color grep (Task 9).
- **Product decisions honored:** `hasPR` comes from the catalog repository (derived-PR source), not an `Exercise` flag; search field is decorative; sheets use native `.sheet` + detents with 26pt-radius custom content. No weights/dates computed here, so kg-only / Monday-start are n/a.
- **Prerequisite handling:** BAK-7 components and BAK-6 protocols are created inside this plan (Tasks 2–4) because they are not yet in the repo, with explicit "skip and reuse" notes if they have since landed — keeping the Library bound to protocols + mocks, never Supabase.
- **TDD policy:** logic (display models, mocks, `LibraryModel`) uses strict failing-test → impl → pass → commit (Tasks 1, 4, 5). Views (components, sheet, screen) are assembled with concrete `Theme`-token code, previews, and XCUITest acceptance coverage (Tasks 2, 3, 6, 7, 8).
- **Out of scope (per spec):** functional search, distinct Workouts/Folders/Programs filtered lists, the detail/builder destination screens (stubbed as route markers), folder/workout CRUD, real Supabase, widgets/Live Activity, the other tabs. None implemented here.
- **Open questions resolved by defaults:** non-program folders route to `folderDetail` (destination is a separate feature); search stays decorative; RECENT/folder-count copy is taken verbatim from the prototype/mock; "N variations" pluralization preserved as-is for parity (noted in `subline` doc comment).
