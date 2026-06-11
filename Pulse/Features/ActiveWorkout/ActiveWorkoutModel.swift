import Foundation
import Observation

@Observable
final class ActiveWorkoutModel {
    enum Phase { case pre, active, rest, summary }
    enum ActiveSheet: Identifiable { case swap, history, jump; var id: Self { self } }

    /// Persisting the finished session (BAK-31). The summary drives the Done
    /// button off this so a failed save is *visible* and *retryable* instead of
    /// silently dropping the workout. `.pendingSync` (BAK-32) is the calm offline
    /// outcome: the session is safely buffered on-device and will sync later, so
    /// the flow finishes normally rather than blocking on `.failed`.
    enum SaveState: Equatable { case idle, saving, saved, pendingSync, failed(String) }

    // dependencies (flow-local repository protocols only — never Supabase)
    private let exerciseRepo: SwapAlternativesProviding
    private let historyRepo: HistoryRepository
    private let sessionWriter: SessionWriter
    private let restCue: RestCuePlaying

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

    /// Save lifecycle for the finished session, and the session held pending so a
    /// failed save can be retried without losing the logged work (BAK-31).
    private(set) var saveState: SaveState = .idle
    private var pendingSession: WorkoutSession?

    // rest state (absolute end is Live-Activity-friendly)
    let restTotal: TimeInterval = 90
    private(set) var restEndsAt: Date?
    /// Mirrors `UserSettings.soundOnRestEnd`. When false, no cues fire (rest still
    /// advances normally). Settable so the app shell can sync it from settings.
    var soundOnRestEnd: Bool
    /// Edge-trigger guard: true once `warn()` has fired for the current rest.
    /// Re-armed to false on `startRest` and on any `adjustRest` that pushes
    /// remaining back above the 10s warn threshold.
    private(set) var didWarn = false

    // baseline est-1RM per exercise for PR detection (loaded from history)
    private var prBaseline: [Exercise.ID: Double] = [:]

    // progression
    /// Mirrors `UserSettings.autoProgressWeight`. Default true so existing call
    /// sites compile; `AppShell` passes the persisted value (Task 4).
    private let autoProgress: Bool
    /// Default kg increment for v1 (single value; per-movement is an Open Question).
    private let progressionIncrement: Double = 2.5
    /// Suggestion for the current step, loaded async from history. `nil` until
    /// loaded or when no suggestion applies (no history / non-working set).
    private(set) var currentSuggestion: ProgressionSuggestion?

    init(exerciseRepo: SwapAlternativesProviding,
         historyRepo: HistoryRepository,
         sessionWriter: SessionWriter,
         restCue: RestCuePlaying = NoopRestCueService(),
         soundOnRestEnd: Bool = true,
         autoProgress: Bool = true) {
        self.exerciseRepo = exerciseRepo
        self.historyRepo = historyRepo
        self.sessionWriter = sessionWriter
        self.restCue = restCue
        self.soundOnRestEnd = soundOnRestEnd
        self.autoProgress = autoProgress
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
        saveState = .idle
        pendingSession = nil
        currentSuggestion = nil
    }

    func beginSets() { phase = .active }

    func endWorkout() {
        isActive = false
        phase = .pre
        activeSheet = nil
    }

    /// Persists the finished session (sets stamped with their variation). On
    /// success it tears down the takeover; on failure it surfaces `.failed` and
    /// keeps the session pending so the summary can offer a retry — the workout
    /// is never silently dropped (BAK-31). Called from the summary's Done button.
    func finishAndSave(now: Date = .now) async {
        let sets = loggedSets.values.sorted { $0.order < $1.order }
        pendingSession = WorkoutSession(workoutID: workout.id, startedAt: startedAt,
                                        endedAt: now, sets: sets)
        await attemptSave()
    }

    /// Re-attempt a previously failed save, reusing the held session so the
    /// original end time and logged sets are preserved.
    func retrySave() async { await attemptSave() }

    private func attemptSave() async {
        guard let session = pendingSession else { return }
        saveState = .saving
        do {
            try await sessionWriter.save(session)
            saveState = .saved
            pendingSession = nil
            endWorkout()
        } catch {
            // BAK-32: an offline failure means the writer has buffered the session
            // on-device (it will sync when connectivity returns), so we surface a
            // calm "saved on device" note and let the summary's Done button tear
            // the takeover down. Any other error keeps the blocking BAK-31 retry UI.
            if SaveClassification.isOffline(error) {
                saveState = .pendingSync
                pendingSession = nil
            } else {
                print("[Pulse] session save failed: \(error)")
                saveState = .failed("Couldn’t save your workout. Check your connection and try again.")
            }
        }
    }

    // MARK: - logging / transitions

    func logSet(reps: Int, weight: Double, rir: Int? = nil, now: Date = .now) {
        guard !steps.isEmpty else { return }
        let step = steps[stepIdx]
        let type = currentSet?.type ?? .working
        let exID = workout.exercises[step.exIdx].exercise.id
        let varID = workout.exercises[step.exIdx].variationID
        loggedSets[stepIdx] = SessionSet(exerciseID: exID, variationID: varID, order: stepIdx,
                                         reps: reps, weight: weight, type: type, rir: rir)
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
    /// Plays the end cue only on a natural finish (remaining <= 0); Skip is silent.
    func afterRest(now: Date = .now) {
        guard phase == .rest else { return }
        let ended = remainingRest(now: now) <= 0
        if ended, soundOnRestEnd { restCue.end() }
        restCue.teardown()
        stepIdx = min(stepIdx + 1, steps.count - 1)
        restEndsAt = nil
        phase = .active
    }

    /// Skip the current set without logging it. Same advance/clamp as afterRest.
    func skipSet() {
        stepIdx = min(stepIdx + 1, steps.count - 1)
        phase = .active
    }

    private func startRest(now: Date) {
        restEndsAt = now.addingTimeInterval(restTotal)
        didWarn = false
        restCue.prepare()
    }

    /// Called every `TimelineView` tick while resting. Computes remaining time,
    /// fires the warn cue once at <= 10s and the end transition at <= 0, and
    /// returns the remaining seconds for the view. Edge-triggering lives here
    /// (not the view) so the 0.2s cadence and stray ticks can't double-fire.
    @discardableResult
    func tick(now: Date = .now) -> TimeInterval {
        let remaining = remainingRest(now: now)
        guard phase == .rest else { return remaining }
        if remaining <= 10, !didWarn {
            didWarn = true
            if soundOnRestEnd { restCue.warn() }
        }
        if remaining <= 0 {
            afterRest(now: now)
        }
        return remaining
    }

    func adjustRest(_ delta: TimeInterval, now: Date = .now) {
        guard let end = restEndsAt else { return }
        let newRemaining = max(0, end.timeIntervalSince(now) + delta)
        restEndsAt = now.addingTimeInterval(newRemaining)
        // Re-arm the warn if the adjustment pushed us back above the warn window,
        // so a later descent through 10s warns again.
        if newRemaining > 10 { didWarn = false }
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

    // MARK: - progression

    /// Pick the prior `SessionSet` that best represents "last time" for a given
    /// planned set index: prefer the working set logged at the same `order`,
    /// else fall back to the heaviest working set in the slice. Returns the
    /// chosen set in a single-element array shaped for `ProgressionInput`.
    /// Pure + internal so it can be unit-tested without async/history.
    func matchingLastSets(_ history: [SessionSet], setIndex: Int) -> [SessionSet] {
        let working = history.filter { $0.type == .working }
        guard !working.isEmpty else { return [] }
        if let atIndex = working.first(where: { $0.order == setIndex }) {
            return [atIndex]
        }
        if let top = working.max(by: { $0.weight < $1.weight }) {
            return [top]
        }
        return []
    }

    /// Compute the suggestion for a step without touching state — pure given the
    /// fetched history. Returns `nil` for non-working sets or when the engine
    /// declines (no history).
    func suggestion(forStep step: WorkoutStep, history: [SessionSet]) -> ProgressionSuggestion? {
        let ex = workout.exercises[step.exIdx]
        guard step.setIdx < ex.sets.count else { return nil }
        let spec = ex.sets[step.setIdx]
        guard spec.type == .working else { return nil }  // suggestions are working-set only
        let last = matchingLastSets(history, setIndex: step.setIdx)
        return suggestProgression(ProgressionInput(target: spec,
                                                   lastSets: last,
                                                   increment: progressionIncrement,
                                                   autoProgress: autoProgress))
    }

    /// Fetch history for the step's exercise and cache the resulting suggestion.
    /// Call this when the active set appears / the step changes.
    func loadSuggestion(forStepIndex i: Int) async {
        guard steps.indices.contains(i) else { currentSuggestion = nil; return }
        let step = steps[i]
        let exID = workout.exercises[step.exIdx].exercise.id
        let history = (try? await historyRepo.recentSets(exerciseID: exID)) ?? []
        currentSuggestion = suggestion(forStep: step, history: history)
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

    /// Delegates to the shared `SetTypeLabel` so the in-app hero and the Live
    /// Activity render identical labels from one source of truth.
    func setTypeLabel(_ type: SetType) -> String { SetTypeLabel.text(for: type) }

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

    /// Stepper seeds (kg) — prefer the loaded progression suggestion, else the
    /// planned `SetSpec` / sample weight as before.
    var seedReps: Int { currentSuggestion?.reps ?? (currentSet?.reps ?? 0) }
    var seedWeight: Double {
        currentSuggestion?.weight
            ?? ActiveWorkoutSample.plannedWeight(exIdx: currentStep.exIdx, setIdx: currentStep.setIdx)
    }

    /// Planned weight (kg) for an arbitrary step index — generalises `seedWeight`
    /// (current step only) so the Live Activity projection can read the next step too.
    func plannedWeight(forStepIndex i: Int) -> Double {
        guard steps.indices.contains(i) else { return 0 }
        let s = steps[i]
        return ActiveWorkoutSample.plannedWeight(exIdx: s.exIdx, setIdx: s.setIdx)
    }

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
            // BAK-30: failure/AMRAP sets still record the reps & weight you hit.
            // Show "To failure" only when nothing was logged; otherwise surface
            // the actual work (prefixed so the set type is still legible).
            let line: String
            let hasFailure = sets.contains { $0.type == .failure }
            if hasFailure && !sets.contains(where: { $0.reps > 0 }) {
                line = "To failure"
            } else {
                let reps = sets.map { String($0.reps) }.joined(separator: "·")
                let topWeight = sets.map(\.weight).max() ?? 0
                let weightPart = topWeight > 0 ? " @ \(WeightFormat.kg(topWeight))" : ""
                line = (hasFailure ? "To failure · " : "") + "\(reps)\(weightPart)"
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
