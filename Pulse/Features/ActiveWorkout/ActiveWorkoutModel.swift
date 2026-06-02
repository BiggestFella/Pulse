import Foundation
import Observation

@Observable
final class ActiveWorkoutModel {
    enum Phase { case pre, active, rest, summary }
    enum ActiveSheet: Identifiable { case swap, history, jump; var id: Self { self } }

    // dependencies (flow-local repository protocols only — never Supabase)
    private let exerciseRepo: SwapAlternativesProviding
    private let historyRepo: HistoryRepository
    private let sessionWriter: SessionWriter

    // session state
    private(set) var workout: Workout = ActiveWorkoutSample.workout
    private(set) var steps: [WorkoutStep] = []
    private(set) var phase: Phase = .pre
    private(set) var stepIdx: Int = 0
    private(set) var doneSteps: Set<Int> = []
    private(set) var swaps: [Int: Exercise] = [:]
    private(set) var loggedSets: [Int: SessionSet] = [:]
    private(set) var startedAt: Date = .now
    var activeSheet: ActiveSheet?
    /// false when no session is running (drives the app-shell takeover branch).
    private(set) var isActive: Bool = false

    // rest state (absolute end is Live-Activity-friendly)
    let restTotal: TimeInterval = 90
    private(set) var restEndsAt: Date?

    // baseline est-1RM per exercise for PR detection (loaded from history)
    private var prBaseline: [Exercise.ID: Double] = [:]

    init(exerciseRepo: SwapAlternativesProviding,
         historyRepo: HistoryRepository,
         sessionWriter: SessionWriter) {
        self.exerciseRepo = exerciseRepo
        self.historyRepo = historyRepo
        self.sessionWriter = sessionWriter
    }

    // MARK: - lifecycle

    func startWorkout(_ w: Workout) {
        workout = w
        steps = buildSteps(w)
        phase = .pre
        stepIdx = 0
        doneSteps = []
        swaps = [:]
        loggedSets = [:]
        startedAt = .now
        restEndsAt = nil
        isActive = true
        activeSheet = nil
    }

    func beginSets() { phase = .active }

    func endWorkout() {
        isActive = false
        phase = .pre
        activeSheet = nil
    }

    // MARK: - logging / transitions

    func logSet(reps: Int, weight: Double, now: Date = .now) {
        guard !steps.isEmpty else { return }
        let step = steps[stepIdx]
        let type = currentSet?.type ?? .working
        let exID = workout.exercises[step.exIdx].exercise.id
        loggedSets[stepIdx] = SessionSet(exerciseID: exID, order: stepIdx,
                                         reps: reps, weight: weight, type: type)
        doneSteps.insert(stepIdx)

        if stepIdx == steps.count - 1 {
            phase = .summary
        } else if step.rest {
            startRest(now: now)
            phase = .rest
        } else {
            stepIdx += 1
            phase = .active
        }
    }

    /// Rest finished (auto at 0) or "Skip rest" — advance, clamp, back to active.
    /// Guarded so a stray `TimelineView` tick after we've left rest is a no-op.
    func afterRest() {
        guard phase == .rest else { return }
        stepIdx = min(stepIdx + 1, steps.count - 1)
        restEndsAt = nil
        phase = .active
    }

    /// Skip the current set without logging it. Same advance/clamp as afterRest.
    func skipSet() {
        stepIdx = min(stepIdx + 1, steps.count - 1)
        phase = .active
    }

    private func startRest(now: Date) { restEndsAt = now.addingTimeInterval(restTotal) }

    func adjustRest(_ delta: TimeInterval, now: Date = .now) {
        guard let end = restEndsAt else { return }
        let newRemaining = max(0, end.timeIntervalSince(now) + delta)
        restEndsAt = now.addingTimeInterval(newRemaining)
    }

    func remainingRest(now: Date = .now) -> TimeInterval {
        guard let end = restEndsAt else { return 0 }
        return max(0, end.timeIntervalSince(now))
    }

    // MARK: - jump / swap

    func jump(toExerciseIndex exIdx: Int) {
        let idxs = exerciseSteps(steps)[exIdx] ?? []
        let target = idxs.first { !doneSteps.contains($0) } ?? idxs.first ?? stepIdx
        stepIdx = target
        phase = .active
        activeSheet = nil
    }

    func swap(exerciseIndex exIdx: Int, to alt: Exercise) {
        swaps[exIdx] = alt
        activeSheet = nil
    }

    func alternatives(for exIdx: Int) async -> [Exercise] {
        (try? await exerciseRepo.alternatives(
            muscleGroup: workout.exercises[exIdx].exercise.muscleGroup)) ?? []
    }

    func history(for exIdx: Int) async -> [SessionSet] {
        (try? await historyRepo.recentSets(
            exerciseID: workout.exercises[exIdx].exercise.id)) ?? []
    }

    /// Seed per-exercise PR baselines (best prior est-1RM) from history so the
    /// summary's PR count reflects real bests, not "everything is a PR". Called
    /// when the flow appears.
    func loadPRBaselines() async {
        var base: [Exercise.ID: Double] = [:]
        for we in workout.exercises {
            let id = we.exercise.id
            let prior = (try? await historyRepo.recentSets(exerciseID: id)) ?? []
            if let best = bestEpley(in: prior) { base[id] = best }
        }
        prBaseline = base
    }

    // MARK: - derived UI state

    var currentStep: WorkoutStep { steps[stepIdx] }
    var nextStep: WorkoutStep? { stepIdx + 1 < steps.count ? steps[stepIdx + 1] : nil }
    private var currentExercise: WorkoutExercise { workout.exercises[currentStep.exIdx] }
    private var currentSet: SetSpec? {
        let ex = currentExercise
        return currentStep.setIdx < ex.sets.count ? ex.sets[currentStep.setIdx] : nil
    }

    func displayName(forExercise exIdx: Int) -> String {
        swaps[exIdx]?.name ?? workout.exercises[exIdx].exercise.name
    }

    func isSwapped(_ exIdx: Int) -> Bool { swaps[exIdx] != nil }

    func setTypeLabel(_ type: SetType) -> String {
        switch type {
        case .working: return "WORKING"
        case .warmup:  return "WARMUP"
        case .dropset: return "DROP SET"   // prototype omitted this — never blank
        case .failure: return "FAILURE"
        case .amrap:   return "AMRAP"
        }
    }

    var logButtonLabel: String {
        if stepIdx == steps.count - 1 { return "Finish workout" }
        let step = currentStep
        if !step.rest, let partner = step.supersetPartnerExIdx {
            let partnerStep = WorkoutStep(exIdx: partner, setIdx: step.setIdx,
                                          rest: false, supersetPartnerExIdx: step.exIdx)
            if let label = partnerStep.ssLabel(in: workout) { return "Log → \(label)" }
        }
        return "Log set"
    }

    /// Planned stepper seeds for the current step (kg).
    var seedReps: Int { currentSet?.reps ?? 0 }
    var seedWeight: Double { ActiveWorkoutSample.plannedWeight(exIdx: currentStep.exIdx, setIdx: currentStep.setIdx) }

    // MARK: - summary

    var summary: SessionSummary {
        let logged = Array(loggedSets.values)
        // Canonical volume (working/amrap only — warmup & dropset & failure excluded),
        // matching Stats/History so totals agree app-wide.
        let volume = logged.reduce(0) { $0 + WorkoutAnalytics.setVolume($1) }
        let elapsed = Int(Date.now.timeIntervalSince(startedAt) / 60)
        var byExercise: [Exercise.ID: [SessionSet]] = [:]
        for (idx, set) in loggedSets {
            let exID = workout.exercises[steps[idx].exIdx].exercise.id
            byExercise[exID, default: []].append(set)
        }
        let prs = byExercise.reduce(into: 0) { count, pair in
            guard let best = bestEpley(in: pair.value) else { return }
            let baseline = prBaseline[pair.key] ?? 0
            if best > baseline { count += 1 }
        }
        return SessionSummary(totalVolume: volume,
                              elapsedMinutes: elapsed,
                              completedSets: doneSteps.count,
                              totalSets: steps.count,
                              prCount: prs)
    }

    /// One LOG-row per exercise for the receipt.
    struct LogRow: Identifiable {
        let id: Int; let name: String; let summaryLine: String; let volume: Double; let isPR: Bool
    }

    var logRows: [LogRow] {
        let stepMap = exerciseSteps(steps)
        return workout.exercises.indices.compactMap { exIdx in
            let stepIdxs = stepMap[exIdx] ?? []
            let sets = stepIdxs.compactMap { loggedSets[$0] }
            guard !sets.isEmpty else { return nil }
            let vol = sets.reduce(0) { $0 + WorkoutAnalytics.setVolume($1) }
            let line: String
            if sets.contains(where: { $0.type == .failure }) {
                line = "To failure"
            } else {
                let reps = sets.map { String($0.reps) }.joined(separator: "·")
                let topWeight = sets.map(\.weight).max() ?? 0
                line = "\(reps) @ \(WeightFormat.kg(topWeight))"
            }
            let baseline = prBaseline[workout.exercises[exIdx].exercise.id] ?? 0
            let isPR = (bestEpley(in: sets) ?? 0) > baseline
            return LogRow(id: exIdx, name: displayName(forExercise: exIdx),
                          summaryLine: line, volume: vol, isPR: isPR)
        }
    }

    #if DEBUG
    func markDoneForTest(_ idx: Int) { doneSteps.insert(idx) }
    #endif
}
