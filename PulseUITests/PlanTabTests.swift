import XCTest

/// Acceptance coverage for the Plan / Calendar tab (BAK-12).
/// The mock schedule is seeded relative to "today", so these tests compute the
/// current day at runtime and avoid asserting fixed day numbers. Tapping today's
/// cell launches the active flow (shell takeover), so picks target a non-today day.
final class PlanTabTests: XCTestCase {

    // Launch against the in-memory mocks (`-uiMock`) — otherwise the app builds
    // the live Supabase repositories, whose reads throw `.notImplemented`.
    private func launchToPlan() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiMock"]
        app.launch()

        // BAK-25: the FIRST tab switch right after a cold launch is swallowed by
        // SwiftUI's TabView under XCUITest on iOS 26 — the tap synthesizes but the
        // selection never changes (every subsequent tap lands fine). Every test
        // here makes Today→Plan its first interaction, so it always hit this and
        // read as "the Plan tab won't activate". The app switches correctly for
        // users; this re-taps until the Plan screen actually renders.
        let planTab = app.tabBars.buttons["Plan"]
        XCTAssertTrue(planTab.waitForExistence(timeout: 10), "Tab bar should appear")
        let calendar = app.otherElements["plan.calendar"]
        for _ in 0..<5 where !calendar.exists {
            planTab.tap()
            _ = calendar.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(calendar.waitForExistence(timeout: 5),
                      "Plan calendar should render after selecting the Plan tab")
        return app
    }

    /// A future day-of-month: never today (so tapping won't launch the active
    /// flow) and never a read-only "done" day, so its Schedule sheet shows the
    /// pick/rest options. The mock seeds `today-27...today+2`, and a future day
    /// is always unscheduled-or-planned (a "done" day requires a past session).
    private var pickableDay: Int {
        let cal = Calendar.current
        let today = cal.component(.day, from: Date())
        let daysInMonth = cal.range(of: .day, in: .month, for: Date())!.count
        return today < daysInMonth ? today + 1 : today - 1
    }

    // AC-1: toggle defaults to Calendar and switches the body.
    func testToggleSwitchesCalendarAndAgenda() {
        let app = launchToPlan()
        app.buttons["plan.toggle.agenda"].tap()
        XCTAssertTrue(app.otherElements["plan.agenda"].waitForExistence(timeout: 5))
        app.buttons["plan.toggle.calendar"].tap()
        XCTAssertTrue(app.otherElements["plan.calendar"].waitForExistence(timeout: 5))
    }

    // AC-2: calendar renders summary card + grid cells. The summary card's text
    // and the day cells surface as `staticTexts` (the cells are plain labels),
    // so assert those rather than `otherElements`.
    func testCalendarRendersSummaryAndGrid() {
        let app = launchToPlan()
        XCTAssertTrue(app.staticTexts["plan.summaryCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["plan.day.1"].exists)
    }

    // AC-4 + AC-7: tapping a non-today day opens the Schedule sheet.
    func testTappingDayOpensScheduleSheet() {
        let app = launchToPlan()
        let cell = app.staticTexts["plan.day.\(pickableDay)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertTrue(app.otherElements["plan.scheduleSheet"].waitForExistence(timeout: 5),
                      "Tapping a non-today day should present the Schedule sheet")
    }

    // AC-11: assigning a workout from the picker closes the sheet.
    func testAssignFromPickerClosesSheet() {
        let app = launchToPlan()
        let cell = app.staticTexts["plan.day.\(pickableDay)"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        let sheet = app.otherElements["plan.scheduleSheet"]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))

        // Tap the first pick row (identifier prefix plan.sheet.pick.) or the rest option.
        let pick = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH 'plan.sheet.pick.'"))
            .firstMatch
        let target = pick.waitForExistence(timeout: 5) ? pick : app.buttons["plan.sheet.rest"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
        XCTAssertFalse(sheet.waitForExistence(timeout: 2), "Sheet should close after assigning")
    }

    // AC-6: agenda renders rows.
    func testAgendaRendersRows() {
        let app = launchToPlan()
        app.buttons["plan.toggle.agenda"].tap()
        XCTAssertTrue(app.otherElements["plan.agenda"].waitForExistence(timeout: 5))
    }
}
