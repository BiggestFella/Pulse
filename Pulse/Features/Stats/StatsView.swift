import SwiftUI

struct StatsView: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var model: StatsModel

    init(repository: any StatsRepository) {
        _model = State(initialValue: StatsModel(repository: repository))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing[3]) {
                StatsTopBar(onBack: { dismiss() })

                Text("Your numbers.")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("stats.h1")

                rangeChips
                content
            }
            .padding(theme.spacing[5])
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .task { await model.load() }
    }

    private var rangeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing[1]) {
                ForEach(StatRange.displayOrder, id: \.self) { range in
                    FilterChip(label: range.chipLabel, isOn: range == model.selectedRange) {
                        Task { await model.select(range) }
                    }
                    .accessibilityIdentifier("range.\(range.chipLabel)")
                }
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityIdentifier("stats.loading")
        case .error:
            errorState
        case .empty:
            emptyState
        case .loaded:
            heroCard
            grid
            StatLabel("VOLUME BY MUSCLE")
            ForEach(model.muscles) { m in
                MuscleBarRow(muscle: m.muscleGroup,
                             valueDisplay: StatsModel.abbreviate(m.volume),
                             pct: model.musclePct(m),
                             isMax: m.id == model.maxVolumeMuscleID)
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("\(model.selectedRange.eyebrowToken) VOLUME · \(model.unitsLabel)",
                      color: theme.onAccent.opacity(0.85))
            HStack(alignment: .firstTextBaseline) {
                Text(model.volumeDisplay)
                    .font(.system(size: 60, weight: .bold))
                    .foregroundStyle(theme.onAccent)
                    .accessibilityIdentifier("stats.volume")
                Spacer()
                Text(trendString(model.trendPct))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                    .accessibilityIdentifier("stats.trend")
            }
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(model.chartValues.enumerated()), id: \.offset) { _, h in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(theme.onAccent.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(CGFloat(h / model.volumeChartMax) * 50, 2))
                }
            }
            .frame(height: 50)
            .accessibilityIdentifier("stats.chart")
        }
        .padding(theme.spacing[4])
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radiusCard))
    }

    private var grid: some View {
        let cols = [GridItem(.flexible(), spacing: theme.spacing[1]),
                    GridItem(.flexible(), spacing: theme.spacing[1])]
        return LazyVGrid(columns: cols, spacing: theme.spacing[1]) {
            // "OF PLAN" denominator isn't available from the merged repo (a spec
            // open question) — show the completed-session count for now.
            SmallStatCard(label: "SESSIONS", value: "\(model.sessions)", sub: "COMPLETED")
            SmallStatCard(label: "NEW PRS", value: "\(model.newPRs)", sub: "THIS RANGE",
                          valueColor: theme.accent, labelColor: theme.accent2)
            SmallStatCard(label: "AVG TIME", value: "\(model.avgTimeMinutes)", unit: "m",
                          sub: "PER SESSION")
            SmallStatCard(label: "STREAK", value: "\(model.streakDays)", unit: "d",
                          sub: "CURRENT", valueColor: theme.accent2, labelColor: theme.accent2)
        }
    }

    private var emptyState: some View {
        VStack(spacing: theme.spacing[2]) {
            StatLabel("NO DATA YET")
            Text("Log a workout to see your numbers here.")
                .font(.system(size: 15))
                .foregroundStyle(theme.inkSoft)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityIdentifier("stats.empty")
    }

    private var errorState: some View {
        VStack(spacing: theme.spacing[2]) {
            Text("Couldn't load your stats.")
                .font(.system(size: 15))
                .foregroundStyle(theme.ink)
            Button("Retry") { Task { await model.retry() } }
                .foregroundStyle(theme.accent)
                .accessibilityIdentifier("stats.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityIdentifier("stats.error")
    }

    /// "+12% vs prev" / "-8% vs prev" / "—" when there's no comparison.
    private func trendString(_ pct: Int?) -> String {
        guard let pct else { return "—" }
        return "\(pct >= 0 ? "+" : "")\(pct)% vs prev"
    }
}

#Preview("Loaded") {
    NavigationStack { StatsView(repository: InMemoryStatsRepository(store: MockStore())) }
        .environment(Theme())
}

#Preview("Empty") {
    NavigationStack { StatsView(repository: InMemoryStatsRepository(store: MockStore(seeded: false))) }
        .environment(Theme())
}
