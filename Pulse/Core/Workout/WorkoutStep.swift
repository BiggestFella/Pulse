import Foundation

/// One logged unit of work: a single set of one exercise (per round for supersets).
/// `rest == true` means a rest phase follows after logging; the final step is always false.
struct WorkoutStep: Equatable {
    let exIdx: Int
    let setIdx: Int
    let rest: Bool
    let supersetPartnerExIdx: Int?

    /// "1A"/"1B" style label: superset-group ordinal (1-based among groups) + member letter.
    /// Returns nil when the step's exercise is not part of a superset.
    func ssLabel(in workout: Workout) -> String? {
        let ex = workout.exercises
        guard let group = ex[exIdx].supersetGroup else { return nil }
        var seen: [String] = []
        for e in ex where e.supersetGroup != nil {
            if let g = e.supersetGroup, !seen.contains(g) { seen.append(g) }
        }
        guard let groupOrdinal = seen.firstIndex(of: group) else { return nil }
        let members = ex.indices.filter { ex[$0].supersetGroup == group }
        guard let memberPos = members.firstIndex(of: exIdx) else { return nil }
        let letter = String(UnicodeScalar(65 + memberPos)!)
        return "\(groupOrdinal + 1)\(letter)"
    }
}

/// Flatten a workout into an ordered step list.
/// - Non-superset exercise: one step per set, all `rest == true`.
/// - Superset group (consecutive members sharing `supersetGroup`): interleave
///   A1→B1→A2→B2; `rest == true` only on the last member of each round; a member
///   with fewer sets is skipped in later rounds.
/// - The very last emitted step's `rest` is forced `false`.
func buildSteps(_ workout: Workout) -> [WorkoutStep] {
    let ex = workout.exercises
    var steps: [WorkoutStep] = []
    var i = 0
    while i < ex.count {
        if let group = ex[i].supersetGroup {
            var members: [Int] = []
            var j = i
            while j < ex.count && ex[j].supersetGroup == group { members.append(j); j += 1 }
            let rounds = members.map { ex[$0].sets.count }.max() ?? 0
            for r in 0..<rounds {
                for (k, mIdx) in members.enumerated() where r < ex[mIdx].sets.count {
                    let isLastMemberOfRound = (k == members.count - 1)
                    let partner = members.first { $0 != mIdx }
                    steps.append(WorkoutStep(exIdx: mIdx, setIdx: r,
                                             rest: isLastMemberOfRound,
                                             supersetPartnerExIdx: partner))
                }
            }
            i = j
        } else {
            for s in ex[i].sets.indices {
                steps.append(WorkoutStep(exIdx: i, setIdx: s, rest: true, supersetPartnerExIdx: nil))
            }
            i += 1
        }
    }
    if !steps.isEmpty {
        let last = steps.count - 1
        steps[last] = WorkoutStep(exIdx: steps[last].exIdx, setIdx: steps[last].setIdx,
                                  rest: false, supersetPartnerExIdx: steps[last].supersetPartnerExIdx)
    }
    return steps
}

/// exIdx → ordered list of its step indices (for Jump + per-exercise done counts).
func exerciseSteps(_ steps: [WorkoutStep]) -> [Int: [Int]] {
    var map: [Int: [Int]] = [:]
    for (idx, step) in steps.enumerated() { map[step.exIdx, default: []].append(idx) }
    return map
}
