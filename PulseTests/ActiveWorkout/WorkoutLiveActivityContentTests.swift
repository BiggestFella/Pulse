import XCTest
@testable import Pulse

final class WorkoutLiveActivityContentTests: XCTestCase {
    private func makeModel() -> ActiveWorkoutModel {
        let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                                   historyRepo: MockHistoryRepository(),
                                   sessionWriter: MockSessionWriter())
        m.startWorkout(ActiveWorkoutSample.workout)
        m.beginSets()           // phase = .active, stepIdx 0 (bench warmup)
        return m
    }

    // AC4/AC5: active working set
    func testActiveWorkingSetMapping() {
        let m = makeModel()
        m.logSet(reps: 15, weight: 60)   // log warmup → rest
        m.afterRest()                    // advance → step1 (bench working)
        let s = WorkoutLiveActivityContent.make(from: m, palette: .coastal)
        XCTAssertEqual(s.phase, .active)
        XCTAssertEqual(s.exerciseName, "Flat Machine Press")
        XCTAssertEqual(s.setIndex, 2)
        XCTAssertEqual(s.totalSets, 4)
        XCTAssertEqual(s.setTypeLabel, "WORKING")
        XCTAssertEqual(s.targetReps, 12)
        XCTAssertEqual(s.targetWeight, 60)
        XCTAssertEqual(s.completedSets, 1)
        XCTAssertEqual(s.totalStepCount, 11)
    }

    // AC4: failure set → nil reps (∞), no weight, last step has no UP NEXT
    func testFailureSetMapping() {
        let m = makeModel()
        m.jump(toExerciseIndex: 4)       // pushup failure (last step)
        let s = WorkoutLiveActivityContent.make(from: m, palette: .coastal)
        XCTAssertEqual(s.exerciseName, "Tricep Pushup")
        XCTAssertNil(s.targetReps)
        XCTAssertNil(s.targetWeight)
        XCTAssertEqual(s.setTypeLabel, "FAILURE")
        XCTAssertNil(s.nextExerciseName)
    }

    // AC5: dropset label non-empty + correct
    func testDropsetLabelMapping() {
        let m = makeModel()
        m.markDoneForTest(4)             // mark incline working done
        m.jump(toExerciseIndex: 1)       // → first undone of incline = step5 (dropset)
        let s = WorkoutLiveActivityContent.make(from: m, palette: .coastal)
        XCTAssertEqual(s.setTypeLabel, "DROP SET")
        XCTAssertEqual(s.targetReps, 10)
        XCTAssertEqual(s.targetWeight, 28)
    }

    // AC2: rest phase → restEndsAt + fraction from restTotal
    func testRestPhaseFraction() {
        let m = makeModel()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        m.logSet(reps: 15, weight: 60, now: t0)   // warmup rest:true → phase .rest, restEndsAt t0+90
        let s = WorkoutLiveActivityContent.make(from: m, palette: .coastal, now: t0.addingTimeInterval(45))
        XCTAssertEqual(s.phase, .rest)
        XCTAssertEqual(s.restEndsAt, t0.addingTimeInterval(90))
        XCTAssertEqual(s.totalRest, 90)
        XCTAssertEqual(s.restFraction(now: t0.addingTimeInterval(45)), 0.5, accuracy: 0.001)
    }

    // AC6/AC12: superset mid-pair → isMidPair, no rest, partner ssLabel in UP NEXT
    func testSupersetMidPairMapping() {
        let m = makeModel()
        m.jump(toExerciseIndex: 2)       // → step6 triCable set0 (rest:false, has partner)
        let s = WorkoutLiveActivityContent.make(from: m, palette: .coastal)
        XCTAssertTrue(s.isMidPair)
        XCTAssertNil(s.restEndsAt)
        XCTAssertEqual(s.ssLabel, "1A")
        XCTAssertEqual(s.nextExerciseName, "Single Arm Lateral Raise")
        XCTAssertEqual(s.nextSsLabel, "1B")
    }

    // counts + theme snapshot
    func testCountsAndPaletteSnapshot() {
        let m = makeModel()
        m.logSet(reps: 15, weight: 60); m.afterRest()   // 1 done → step1
        m.logSet(reps: 12, weight: 60); m.afterRest()   // 2 done → step2
        let s = WorkoutLiveActivityContent.make(from: m, palette: .mint)
        XCTAssertEqual(s.completedSets, 2)
        XCTAssertEqual(s.totalStepCount, 11)
        XCTAssertEqual(s.palette, .mint)
    }
}
