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

    // BAK-53: every catalog muscle string must be a canonical `MuscleGroup` raw
    // value — a non-canonical string (e.g. "Arms"/"Delts") falls back to `.other`
    // and leaves the real exercise-picker sections empty under -uiMock.
    func testCatalogMuscleStringsAreCanonicalMuscleGroups() {
        for ex in SampleData.exercises {
            XCTAssertNotNil(MuscleGroup(rawValue: ex.muscleGroup),
                            "\(ex.name): non-canonical muscle '\(ex.muscleGroup)'")
        }
    }

    func testActiveProgramIsPPLPinnedToMonWedFri() {
        let program = SampleData.program
        XCTAssertTrue(program.isActive)
        XCTAssertEqual(program.weeks, 6)
        XCTAssertEqual(Set(program.workouts.flatMap(\.weekdays)), [1, 3, 5])
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

    /// BAK-38: every planned training day must name the same workout the
    /// weekday-based hero (`todaysWorkout(on:)`) would — otherwise the Today
    /// hero and the week-strip cell disagree on the same day.
    @MainActor
    func testScheduledWorkoutsAgreeWithWeekdayHero() async throws {
        let repo = InMemoryWorkoutRepository(store: MockStore())
        var checked = 0
        for (day, plan) in SampleData.schedule {
            guard case let .workout(id) = plan else { continue }
            let hero = try await repo.todaysWorkout(on: day)
            XCTAssertEqual(hero?.id, id,
                "schedule and weekday hero disagree on \(day)")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, "expected some planned training days")
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
