import Foundation

/// Pure filtering/sorting helpers for the exercise picker, kept out of the View
/// so they can be unit-tested. `activeMuscles` are `muscle_group` strings; an
/// empty set means "All".
enum ExercisePickerLogic {
    enum Mode: Equatable { case sectioned, alphabetical }

    /// Sectioned (muscle groups) when ≥1 muscle is active and not searching;
    /// otherwise a flat alphabetical list (browsing All or searching).
    static func mode(activeMuscles: Set<String>, search: String) -> Mode {
        let searching = !search.trimmingCharacters(in: .whitespaces).isEmpty
        return (!activeMuscles.isEmpty && !searching) ? .sectioned : .alphabetical
    }

    /// Catalog groups limited to the active muscles, preserving catalog order.
    static func sectioned(_ catalog: [BuilderCatalogGroup], activeMuscles: Set<String>) -> [BuilderCatalogGroup] {
        activeMuscles.isEmpty ? catalog : catalog.filter { activeMuscles.contains($0.muscle) }
    }

    /// Flat list sorted by name, filtered by active muscles (if any) and search.
    static func alphabetical(_ catalog: [BuilderCatalogGroup], activeMuscles: Set<String>, search: String) -> [Exercise] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return catalog
            .filter { activeMuscles.isEmpty || activeMuscles.contains($0.muscle) }
            .flatMap { $0.exercises }
            .filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Distinct uppercase first letters present in `list`, ascending — drives the
    /// A–Z scrubber.
    static func letterIndex(_ list: [Exercise]) -> [String] {
        var seen = Set<String>(); var out: [String] = []
        for ex in list.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let l = String(ex.name.prefix(1)).uppercased()
            if !l.isEmpty, !seen.contains(l) { seen.insert(l); out.append(l) }
        }
        return out
    }
}
