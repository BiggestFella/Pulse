import SwiftUI

struct ActiveWorkoutFlowView: View {
    @Bindable var model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme
    @State private var liveActivity: WorkoutLiveActivityController?
    /// Mirrors the active session to the paired Apple Watch (BAK-37). A
    /// projection like `liveActivity` — synced at the same engine-transition
    /// points and torn down implicitly when the session ends (idle snapshot).
    @State private var watchBridge: WatchSyncBridge?

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
        // The controller is a projection of engine state. Every field of the
        // pushed ContentState derives from one of the values observed below
        // (phase, stepIdx, restEndsAt, swaps, doneSteps) or the theme palette,
        // so re-pushing on each change covers all engine transitions — logSet,
        // afterRest, skipSet, jump, swap, rest-adjust — plus theme switching.
        .onAppear {
            if liveActivity == nil { liveActivity = WorkoutLiveActivityController(model: model) }
            if watchBridge == nil {
                watchBridge = WatchSyncBridge(
                    model: model,
                    channel: WCSessionWorkoutSyncChannel(),
                    soundOnRestEnd: { model.soundOnRestEnd })
            }
            liveActivity?.sync()
            watchBridge?.sync()
        }
        .onChange(of: model.phase) { liveActivity?.sync(); watchBridge?.sync() }
        .onChange(of: model.stepIdx) { liveActivity?.sync(); watchBridge?.sync() }
        .onChange(of: model.restEndsAt) { liveActivity?.sync(); watchBridge?.sync() }
        .onChange(of: model.swaps) { liveActivity?.sync(); watchBridge?.sync() }
        .onChange(of: model.doneSteps) { liveActivity?.sync(); watchBridge?.sync() }
        .onChange(of: theme.palette) { liveActivity?.sync() }
        // Session ended/abandoned: AppShell removes this takeover view while the
        // controller is still alive; isActive is false by now, so it ends the
        // Activity and pushes the idle snapshot to the watch.
        .onDisappear { liveActivity?.sync(); watchBridge?.sync() }
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
