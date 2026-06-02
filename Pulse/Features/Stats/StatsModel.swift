import Foundation
import Observation

/// Read-only Stats screen model. Composes the screen from the merged BAK-6
/// `StatsRepository` (summary + volume series + volume-by-muscle) and derives the
/// display strings the design needs (abbreviated volume, trend, bar scaling).
@MainActor
@Observable
final class StatsModel {
    enum Phase: Equatable { case loading, loaded, empty, error }

    private(set) var phase: Phase = .loading
    private(set) var selectedRange: StatRange = .defaultRange

    private(set) var series: [VolumePoint] = []
    private(set) var base: StatsSummary?            // sessions / newPRs / avgDuration / streak
    private(set) var muscles: [MuscleVolume] = []

    /// kg-only in v1 (product decision); shown in the hero eyebrow.
    let unitsLabel = "KG"

    private let repository: any StatsRepository

    init(repository: any StatsRepository) { self.repository = repository }

    // MARK: - loading

    func load() async {
        phase = .loading
        do {
            let summary = try await repository.summary(range: selectedRange)
            let series = try await repository.volumeSeries(range: selectedRange)
            let muscles = try await repository.volumeByMuscle(range: selectedRange)
            self.base = summary
            self.series = series
            self.muscles = muscles
            phase = (series.isEmpty && summary.sessions == 0) ? .empty : .loaded
        } catch {
            phase = .error
        }
    }

    func select(_ range: StatRange) async {
        guard range != selectedRange else { return }
        selectedRange = range
        await load()
    }

    func retry() async { await load() }

    // MARK: - derived display

    var totalVolume: Double { series.reduce(0) { $0 + $1.volume } }
    var volumeDisplay: String { Self.abbreviate(totalVolume) }
    var chartValues: [Double] { series.map(\.volume) }

    /// Max for bar scaling, with a floor so a lone non-zero bar never collapses.
    var volumeChartMax: Double { max(chartValues.max() ?? 0, 1) }

    /// Trend vs the earlier half of the window (derived from the series — the
    /// merged repo exposes no prior-period query). `nil` when there's too little
    /// data to compare (renders "—").
    var trendPct: Int? { Self.trend(forVolumes: chartValues) }

    /// Pure, testable trend: % change of the later half vs the earlier half.
    static func trend(forVolumes v: [Double]) -> Int? {
        guard v.count >= 2 else { return nil }
        let mid = v.count / 2
        let first = v[..<mid].reduce(0, +)
        let second = v[mid...].reduce(0, +)
        guard first > 0 else { return nil }
        return Int((((second - first) / first) * 100).rounded())
    }

    var sessions: Int { base?.sessions ?? 0 }
    var newPRs: Int { base?.newPRs ?? 0 }
    var avgTimeMinutes: Int { Int((base?.averageDuration ?? 0) / 60) }
    var streakDays: Int { base?.streak ?? 0 }

    /// The single highest-volume muscle row (gets the `accent2` bar). The repo
    /// returns muscles volume-descending, so the first is the max.
    var maxVolumeMuscleID: String? { muscles.first?.id }

    func musclePct(_ m: MuscleVolume) -> Double {
        let maxVol = muscles.map(\.volume).max() ?? 0
        return maxVol > 0 ? m.volume / maxVol : 0
    }

    /// "184K" / "1.2M" / "920".
    static func abbreviate(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1_000 {
            let k = Int((v / 1_000).rounded())
            return k >= 1_000 ? String(format: "%.1fM", Double(k) / 1_000) : "\(k)K"
        }
        return "\(Int(v.rounded()))"
    }
}
