import SwiftUI

struct ActiveWorkoutFlowView: View {
    @Bindable var model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            Group {
                switch model.phase {
                case .pre:     PreWorkoutView(model: model)
                case .active:  ActiveSetView(model: model)
                case .rest:    RestView(model: model)
                case .summary: SummaryView(model: model)
                }
            }
            .id(model.phase)
            .transition(.phaseMount)
            .accessibilityElement(children: .contain)   // surface phase id; keep child ids queryable
            .accessibilityIdentifier("activeFlow.phase.\(phaseID)")
        }
        .animation(.easeOut(duration: 0.28), value: model.phase)
        .task { await model.loadPRBaselines() }
        .sheet(item: Binding(get: { model.activeSheet }, set: { model.activeSheet = $0 })) { sheet in
            Group {
                switch sheet {
                case .swap:    SwapSheet(model: model)
                case .history: HistorySheet(model: model)
                case .jump:    JumpSheet(model: model)
                }
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(26)
        }
    }

    private var phaseID: String {
        switch model.phase {
        case .pre: return "pre"; case .active: return "active"
        case .rest: return "rest"; case .summary: return "summary"
        }
    }
}

#Preview {
    let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                               historyRepo: MockHistoryRepository(),
                               sessionWriter: MockSessionWriter())
    m.startWorkout(ActiveWorkoutSample.workout)
    return ActiveWorkoutFlowView(model: m).environment(Theme())
}
