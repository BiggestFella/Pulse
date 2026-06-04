import SwiftUI

/// Read-only Exercise Detail screen (`exdetail:<id>`). Header + variation pills,
/// a Personal Best accent card, a 4-bar volume mini-chart, and the last-4
/// session rows. All color/spacing/radii/type from `Theme`/`PulseFont`.
struct ExerciseDetailView: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var model: ExerciseDetailModel

    init(exerciseID: Exercise.ID,
         exerciseRepo: any ExerciseRepository,
         sessionRepo: any SessionRepository,
         prRepo: any PRRepository) {
        _model = State(initialValue: ExerciseDetailModel(
            exerciseID: exerciseID,
            exerciseRepo: exerciseRepo,
            sessionRepo: sessionRepo,
            prRepo: prRepo))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing[3]) {
                header
                if model.showsVariationPills { variationPills }
                content
            }
            .padding(.horizontal, theme.spacing[5])
            .padding(.top, theme.spacing[2])
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").foregroundStyle(theme.ink)
                }
                .accessibilityIdentifier("exdetail.back")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: "ellipsis")          // inert per product decision
                    .foregroundStyle(theme.inkSoft)
                    .accessibilityIdentifier("exdetail.overflow")
            }
        }
        .task { await model.load() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing[0]) {
            Text(model.eyebrowText)
                .pulseStyle(.eyebrow)
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("exdetail.eyebrow")
            Text("\(model.exercise?.name ?? "Exercise").")
                .pulseStyle(.h1)
                .foregroundStyle(theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("exdetail.title")
        }
    }

    // MARK: - Variation pills

    private var variationPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: theme.spacing[1]) {
                ForEach(Array(model.variations.enumerated()), id: \.element.id) { index, option in
                    let selected = index == model.selectedVariationIndex
                    Button { model.selectVariation(index) } label: {
                        Text(option.label)
                            .pulseStyle(.rowSub)
                            .foregroundStyle(selected ? theme.onAccent : theme.inkSoft)
                            .padding(.horizontal, theme.spacing[3])
                            .padding(.vertical, theme.spacing[1])
                            .background(selected ? theme.accent : .clear,
                                        in: RoundedRectangle(cornerRadius: theme.radiusPill))
                            .overlay(
                                RoundedRectangle(cornerRadius: theme.radiusPill)
                                    .strokeBorder(selected ? .clear : theme.inkFaint, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("exdetail.pill.\(option.label)")
                }
            }
        }
        .accessibilityIdentifier("exdetail.variationPills")
    }

    // MARK: - Content (phase switch)

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().tint(theme.accent)
                .frame(maxWidth: .infinity, minHeight: 160)
                .accessibilityIdentifier("exdetail.loading")
        case .error(let message):
            VStack(spacing: theme.spacing[2]) {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await model.retry() } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .accessibilityIdentifier("exdetail.retry")
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .accessibilityIdentifier("exdetail.error")
        case .empty:
            if model.showsPersonalBest { personalBestCard }
            emptyState
        case .loaded:
            if model.showsPersonalBest { personalBestCard }
            volumeChart
            sessionsList
        }
    }

    private var emptyState: some View {
        Text("No sessions logged yet")
            .font(.system(size: 14))
            .foregroundStyle(theme.inkSoft)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, theme.spacing[6])
            .accessibilityIdentifier("exdetail.empty")
    }

    // MARK: - Personal Best card

    @ViewBuilder private var personalBestCard: some View {
        if let pb = model.personalBest {
            // On the accent-filled card all small highlight text uses `onAccent`,
            // never `accent2` (design rule).
            Lockup(value: WeightFormat.kgNumeral(pb.topWeight),
                   top: "PERSONAL BEST",
                   bottom: "kg ·\ntop set.",
                   size: 72,
                   topColor: theme.onAccent.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing[5])
                .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radiusCard))
                .overlay(alignment: .topTrailing) {
                    Text(SessionDateLabel.weekday(pb.date))
                        .pulseStyle(.rowSub)
                        .foregroundStyle(theme.onAccent)
                        .padding(theme.spacing[4])
                }
                .accessibilityIdentifier("exdetail.pbCard")
        }
    }

    // MARK: - Volume chart

    private var volumeChart: some View {
        VStack(alignment: .leading, spacing: theme.spacing[1]) {
            Text("VOLUME · LAST 4").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
            HStack(alignment: .bottom, spacing: theme.spacing[1]) {
                let ordered = Array(model.sessions.reversed())   // oldest → newest
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, session in
                    let isLast = index == ordered.count - 1
                    let height = max(8, session.volume / model.maxVolume * 48)
                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                        .fill(isLast ? theme.accent2 : theme.accent.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                }
            }
            .frame(height: 56, alignment: .bottom)
            .accessibilityIdentifier("exdetail.volumeChart")
        }
    }

    // MARK: - Sessions list

    private var sessionsList: some View {
        VStack(alignment: .leading, spacing: theme.spacing[1]) {
            Text("LAST 4 SESSIONS").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
            ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
                sessionRow(session, first: index == 0)
            }
        }
        .accessibilityIdentifier("exdetail.sessionsList")
    }

    private func sessionRow(_ session: ExerciseSessionSummary, first: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(SessionDateLabel.row(session.date))
                    .pulseStyle(.rowName)
                    .foregroundStyle(theme.ink)
                Text(session.repLine.isEmpty ? "—" : "\(session.repLine) REPS")
                    .pulseStyle(.rowSub)
                    .foregroundStyle(theme.inkSoft)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(session.topWeight > 0 ? WeightFormat.kgNumeral(session.topWeight) : "BW")
                    .font(PulseFont.oswald("Oswald-Bold", size: 20))
                    .foregroundStyle(first ? theme.accent : theme.ink)
                Text("\(WeightFormat.volume(session.volume)) VOL")
                    .pulseStyle(.rowSub)
                    .foregroundStyle(theme.inkSoft)
            }
        }
        .padding(theme.spacing[3])
        .overlay(
            RoundedRectangle(cornerRadius: theme.radiusCard)
                .strokeBorder(first ? theme.accent : theme.inkFaint, lineWidth: first ? 2 : 1.5))
    }
}

#Preview("Loaded — Bench") {
    let store = MockStore()
    let bench = store.exercises.first { $0.name == "Bench Press" }!
    return NavigationStack {
        ExerciseDetailView(exerciseID: bench.id,
                           exerciseRepo: InMemoryExerciseRepository(store: store),
                           sessionRepo: InMemorySessionRepository(store: store),
                           prRepo: InMemoryPRRepository(store: store))
    }
    .environment(Theme())
}

#Preview("Empty history") {
    let store = MockStore()
    let lonely = Exercise(name: "Incline DB Press", muscleGroup: "Chest",
                          variations: [], defaultVariationID: nil)
    store.exercises.append(lonely)
    return NavigationStack {
        ExerciseDetailView(exerciseID: lonely.id,
                           exerciseRepo: InMemoryExerciseRepository(store: store),
                           sessionRepo: InMemorySessionRepository(store: store),
                           prRepo: InMemoryPRRepository(store: store))
    }
    .environment(Theme())
}
