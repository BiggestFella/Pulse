import Foundation
import Observation

/// Read-only Session Detail model. Loads one logged session and projects it into
/// a receipt: date eyebrow, name, program sub-line, volume + PR stat boxes, and a
/// numbered per-exercise LOG (supersets combined, bodyweight → "BW", failure →
/// "To failure · N"). Footer `duplicate()` / `repeatWorkout()` are hooks only —
/// real behaviour is BAK-14 / builders (out of scope).
@MainActor
@Observable
final class SessionDetailModel {
    enum Phase: Equatable { case loading, loaded, error }

    /// One numbered LOG line.
    struct LogRow: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let detail: String       // "15·12·10·8 @ 140kg", "3 rounds", "To failure · 18"
        let volumeLabel: String  // "5.7k", "BW"
        let hasPR: Bool
    }

    /// Full read-only projection of one completed session.
    struct Detail: Equatable {
        let dateEyebrow: String  // "WED · MAY 21 · 58M"
        let name: String         // "Legs"
        let subLine: String      // "PPL · Week 3 · Day 18 · completed"
        let volumeLabel: String  // "12.4"
        let volumeUnit: String   // "K"
        let prCount: Int
        let prSource: String?    // "Back Squat"; nil when prCount == 0
        let log: [LogRow]
    }

    private(set) var phase: Phase = .loading
    private(set) var session: Detail?

    private let sessionID: WorkoutSession.ID
    private let sessionRepo: any SessionRepository
    private let workoutRepo: any WorkoutRepository
    private let programRepo: any ProgramRepository
    private let exerciseRepo: any ExerciseRepository
    private let calendar: Calendar
    private let onDuplicate: (WorkoutSession.ID) -> Void
    private let onRepeat: (WorkoutSession.ID) -> Void

    init(sessionID: WorkoutSession.ID,
         sessionRepo: any SessionRepository,
         workoutRepo: any WorkoutRepository,
         programRepo: any ProgramRepository,
         exerciseRepo: any ExerciseRepository,
         calendar: Calendar = .current,
         onDuplicate: @escaping (WorkoutSession.ID) -> Void = { _ in },
         onRepeat: @escaping (WorkoutSession.ID) -> Void = { _ in }) {
        self.sessionID = sessionID
        self.sessionRepo = sessionRepo
        self.workoutRepo = workoutRepo
        self.programRepo = programRepo
        self.exerciseRepo = exerciseRepo
        self.calendar = calendar
        self.onDuplicate = onDuplicate
        self.onRepeat = onRepeat
    }

    // MARK: - loading

    func load() async {
        phase = .loading
        do {
            guard let session = try await sessionRepo.fetchSession(id: sessionID) else {
                self.session = nil
                phase = .error
                return
            }
            let workout = try await workoutRepo.fetchWorkout(id: session.workoutID)
            let activeProgram = try await programRepo.activeProgram()
            let catalog = try await exerciseRepo.fetchCatalog()
            let allSessions = try await sessionRepo.fetchSessions(limit: nil)

            self.session = Self.detail(from: session, workout: workout,
                                       activeProgram: activeProgram, catalog: catalog,
                                       allSessions: allSessions, calendar: calendar)
            phase = .loaded
        } catch {
            session = nil
            phase = .error
        }
    }

    func retry() async { await load() }

    // MARK: - PR stat box

    /// "+N"; "+0" when no PR (box still renders, plain style).
    var prValueLabel: String { "+\(session?.prCount ?? 0)" }
    /// PR source name, or em-dash when there's no PR.
    var prSubLabel: String { session?.prSource ?? "—" }
    /// Whether the PR box uses the accent-bordered variant.
    var prIsAccent: Bool { (session?.prCount ?? 0) > 0 }

    // MARK: - footer hooks (real behaviour: BAK-14 / builders)

    func duplicate() { onDuplicate(sessionID) }
    func repeatWorkout() { onRepeat(sessionID) }

    // MARK: - projection

    static func detail(from session: WorkoutSession,
                       workout: Workout?,
                       activeProgram: Program?,
                       catalog: [Exercise],
                       allSessions: [WorkoutSession],
                       calendar: Calendar) -> Detail {
        let nameByExercise = Dictionary(catalog.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let totalVolume = WorkoutAnalytics.sessionVolume(session)
        let (volumeLabel, volumeUnit) = splitAbbreviated(totalVolume)

        let prIDs = Set(SessionPRs.prExerciseIDs(in: session, allSessions: allSessions))
        let prSource = prIDs.first.flatMap { nameByExercise[$0] }

        let log = logRows(for: session, workout: workout,
                          nameByExercise: nameByExercise, prIDs: prIDs)

        return Detail(
            dateEyebrow: HistoryFormat.detailEyebrow(session.startedAt, end: session.endedAt, calendar: calendar),
            name: workout?.name ?? "Workout",
            subLine: subLine(workout: workout, activeProgram: activeProgram),
            volumeLabel: volumeLabel,
            volumeUnit: volumeUnit,
            prCount: prIDs.count,
            prSource: prSource,
            log: log)
    }

    /// "PPL · Week N · Day N · completed" when the session's workout is in the
    /// active program; "One-off · completed" otherwise.
    private static func subLine(workout: Workout?, activeProgram: Program?) -> String {
        guard let workout, let program = activeProgram,
              let index = program.workouts.firstIndex(where: { $0.id == workout.id }) else {
            return "One-off · completed"
        }
        let label = programAbbreviation(program.name)
        // Map the workout's position to a Week/Day for the receipt.
        let day = index + 1
        let week = min(program.weeks, max(1, (index / max(program.workouts.count, 1)) + 1))
        return "\(label) · Week \(week) · Day \(day) · completed"
    }

    /// "Push / Pull / Legs" → "PPL"; otherwise the program name itself.
    private static func programAbbreviation(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == "/" || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard words.count >= 2 else { return name }
        return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
    }

    /// One row per logged exercise (in first-appearance order). Superset members
    /// (shared `supersetGroup`) roll into a single combined row.
    static func logRows(for session: WorkoutSession,
                        workout: Workout?,
                        nameByExercise: [Exercise.ID: String],
                        prIDs: Set<Exercise.ID>) -> [LogRow] {
        // Group session sets by exercise, preserving first-seen order.
        var order: [Exercise.ID] = []
        var setsByExercise: [Exercise.ID: [SessionSet]] = [:]
        for set in session.sets.sorted(by: { $0.order < $1.order }) {
            if setsByExercise[set.exerciseID] == nil { order.append(set.exerciseID) }
            setsByExercise[set.exerciseID, default: []].append(set)
        }

        // Superset membership from the workout template.
        let supersetByExercise: [Exercise.ID: String] = {
            guard let workout else { return [:] }
            var map: [Exercise.ID: String] = [:]
            for we in workout.exercises {
                if let group = we.supersetGroup { map[we.exercise.id] = group }
            }
            return map
        }()

        var rows: [LogRow] = []
        var handledGroups: Set<String> = []

        for exID in order {
            if let group = supersetByExercise[exID] {
                guard !handledGroups.contains(group) else { continue }
                handledGroups.insert(group)
                // All exercises in this superset group, in appearance order.
                let memberIDs = order.filter { supersetByExercise[$0] == group }
                let memberSets = memberIDs.flatMap { setsByExercise[$0] ?? [] }
                let rounds = memberSets.filter { WorkoutAnalytics.counts($0.type) }
                    .count / max(memberIDs.count, 1)
                let names = memberIDs.compactMap { nameByExercise[$0] }
                let title = names.joined(separator: " / ") + " superset"
                let volume = memberSets.reduce(0.0) { $0 + WorkoutAnalytics.setVolume($1) }
                rows.append(LogRow(
                    name: title,
                    detail: "\(max(rounds, 1)) rounds",
                    volumeLabel: volumeLabel(for: memberSets, volume: volume),
                    hasPR: memberIDs.contains { prIDs.contains($0) }))
            } else {
                let sets = setsByExercise[exID] ?? []
                let name = nameByExercise[exID] ?? "Exercise"
                let volume = sets.reduce(0.0) { $0 + WorkoutAnalytics.setVolume($1) }
                rows.append(LogRow(
                    name: name,
                    detail: detailString(for: sets),
                    volumeLabel: volumeLabel(for: sets, volume: volume),
                    hasPR: prIDs.contains(exID)))
            }
        }
        return rows
    }

    /// "15·12·10·8 @ 140kg", or "To failure · N" when the set is to-failure,
    /// or "N reps" when there's no weight.
    private static func detailString(for sets: [SessionSet]) -> String {
        if let failure = sets.first(where: { $0.type == .failure }) {
            return "To failure · \(failure.reps)"
        }
        let counting = sets.filter { WorkoutAnalytics.counts($0.type) }
        guard !counting.isEmpty else {
            // Only warmups/etc — show the first set's reps.
            if let first = sets.first { return "\(first.reps) reps" }
            return "—"
        }
        let reps = counting.map { String($0.reps) }.joined(separator: "·")
        let weight = counting.map(\.weight).max() ?? 0
        if weight == 0 { return "\(reps) reps" }
        return "\(reps) @ \(trimmed(weight))kg"
    }

    /// Per-exercise volume figure: "5.7k", "800", or "BW" when all weight is zero.
    private static func volumeLabel(for sets: [SessionSet], volume: Double) -> String {
        let counting = sets.filter { WorkoutAnalytics.counts($0.type) }
        let allBodyweight = !sets.isEmpty && sets.allSatisfy { $0.weight == 0 }
        if allBodyweight || (volume == 0 && counting.allSatisfy { $0.weight == 0 }) {
            return "BW"
        }
        return HistoryFormat.abbreviate(volume)
    }

    /// Split "12.4k"/"800" into (value, unit) for the two-line VOLUME stat box.
    private static func splitAbbreviated(_ v: Double) -> (String, String) {
        let s = HistoryFormat.abbreviate(v)
        if let last = s.last, last == "k" || last == "m" {
            return (String(s.dropLast()), String(last).uppercased())
        }
        return (s, "")
    }

    private static func trimmed(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(w)) : String(w)
    }
}
