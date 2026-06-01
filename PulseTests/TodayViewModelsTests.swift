import XCTest
@testable import Pulse

final class TodayViewModelsTests: XCTestCase {
    func testWeekDayStateHasFourCases() {
        XCTAssertEqual(Set(WeekDayCell.State.allCases),
                       [.done, .today, .plan, .rest])
    }

    func testTodayWorkoutCardHoldsFields() {
        let card = TodayWorkoutCard(
            workoutID: UUID(),
            programLabel: "PPL", week: 4, day: 23,
            name: "Chest & Tris", exerciseCount: 7, est: "~60 min")
        XCTAssertEqual(card.programLabel, "PPL")
        XCTAssertEqual(card.day, 23)
        XCTAssertEqual(card.exerciseCount, 7)
    }

    func testTodayWorkoutCardComputesLabels() {
        let card = TodayWorkoutCard(
            workoutID: UUID(),
            programLabel: "PPL", week: 4, day: 23,
            name: "Chest & Tris", exerciseCount: 7, est: "~60 min")
        XCTAssertEqual(card.eyebrow, "TODAY · PPL · WEEK 4")
        XCTAssertEqual(card.dayLabel, "Day 23")
        XCTAssertEqual(card.footerEyebrow, "7 EXERCISES · ~60 MIN")
    }

    func testWeekCellsHaveDistinctIdentityEvenWhenContentRepeats() {
        // The all-rest week is seven cells with identical content; identity is
        // the position, so all seven ids must be distinct (else ForEach collides).
        let week = TodaySnapshot.allRest.week
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(Set(week.map(\.id)).count, 7)
    }

    func testSessionRecapHoldsNameAndSubline() {
        let r = SessionRecap(sessionID: UUID(), name: "Legs",
                             subline: "71M · 18.7K KG · +1 PR")
        XCTAssertEqual(r.name, "Legs")
        XCTAssertEqual(r.subline, "71M · 18.7K KG · +1 PR")
    }
}
