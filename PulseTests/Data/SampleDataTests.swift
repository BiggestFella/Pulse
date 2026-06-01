import XCTest
@testable import Pulse

final class SampleDataTests: XCTestCase {
    func testExerciseCatalogSizeAndDefaults() {
        let catalog = SampleData.exercises
        XCTAssertTrue((18...24).contains(catalog.count), "catalog is \(catalog.count)")
        for ex in catalog {
            XCTAssertFalse(ex.variations.isEmpty)
            let def = try? XCTUnwrap(ex.defaultVariationID)
            XCTAssertTrue(ex.variations.contains { $0.id == def })
        }
    }

    func testAtLeastOneSingleVariationExercise() {
        XCTAssertTrue(SampleData.exercises.contains { $0.variations.count == 1 },
                      "need a single-variation exercise to exercise the hidden-switcher rule")
    }

    func testActiveProgramIsPPLPinnedToMonWedFri() {
        let program = SampleData.program
        XCTAssertTrue(program.isActive)
        XCTAssertEqual(program.weeks, 6)
        XCTAssertEqual(Set(program.workouts.compactMap(\.weekday)), [1, 3, 5])
    }

    func testEveryWorkoutExerciseReferencesACatalogExercise() {
        let catalogIDs = Set(SampleData.exercises.map(\.id))
        for w in SampleData.program.workouts {
            for we in w.exercises {
                XCTAssertTrue(catalogIDs.contains(we.exercise.id))
            }
        }
    }

    func testSessionsAreInLast30DaysAndReferenceRealWorkoutsAndExercises() {
        let workoutIDs = Set(SampleData.program.workouts.map(\.id))
        let exerciseIDs = Set(SampleData.exercises.map(\.id))
        let cutoff = Calendar.current.date(byAdding: .day, value: -31, to: Date())!
        XCTAssertTrue((8...12).contains(SampleData.sessions.count))
        for s in SampleData.sessions {
            XCTAssertTrue(workoutIDs.contains(s.workoutID))
            XCTAssertGreaterThan(s.startedAt, cutoff)
            for set in s.sets { XCTAssertTrue(exerciseIDs.contains(set.exerciseID)) }
        }
    }

    func testScheduleSpansAMonth() {
        XCTAssertGreaterThanOrEqual(SampleData.schedule.count, 28)
    }

    func testAtLeastOneSessionProducesAFreshPR() {
        let byExercise = Dictionary(grouping: SampleData.sessions.flatMap(\.sets),
                                    by: \.exerciseID)
        let recent = SampleData.sessions.max { $0.startedAt < $1.startedAt }!
        let producesFreshPR = recent.sets.contains { set in
            guard WorkoutAnalytics.counts(set.type) else { return false }
            let all = byExercise[set.exerciseID] ?? []
            let best = all.filter { WorkoutAnalytics.counts($0.type) }
                          .map(WorkoutAnalytics.estimatedOneRepMax).max() ?? 0
            return WorkoutAnalytics.estimatedOneRepMax(set) >= best - 0.001
        }
        XCTAssertTrue(producesFreshPR)
    }
}
