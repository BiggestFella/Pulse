import XCTest
@testable import Pulse

final class WorkoutRowTargetsTests: XCTestCase {
    func testDecodeMapsTargetStringsToMuscleGroups() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Push","weekday":null,"order":0,
         "targets":["Chest","Triceps","Glutes"],"workoutExercises":[]}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(WorkoutRow.self, from: json)
        XCTAssertEqual(row.toModel().targets, [.chest, .triceps, .other])
    }

    func testDecodeMissingTargetsIsEmpty() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Push","weekday":null,"order":0,
         "workoutExercises":[]}
        """.data(using: .utf8)!
        let row = try JSONDecoder().decode(WorkoutRow.self, from: json)
        XCTAssertEqual(row.toModel().targets, [])
    }
}
