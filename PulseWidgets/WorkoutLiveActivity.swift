import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenCard(state: context.state)
                .activityBackgroundTint(Color(hex: context.state.palette.tokens.bg))
        } dynamicIsland: { context in
            let theme = WidgetTheme(palette: context.state.palette)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if context.state.phase == .rest {
                        RestRingView(state: context.state, theme: theme)
                    } else {
                        SetLockupView(state: context.state, theme: theme)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    UpNextView(state: context.state, theme: theme)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.phase == .rest {
                        Button(intent: SkipRestIntent()) {
                            Text("SKIP REST").font(.laLabel(11))
                        }
                        .tint(theme.accent)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.phase == .rest ? "timer" : "dumbbell.fill")
                    .foregroundStyle(theme.accent)
            } compactTrailing: {
                compactValue(context.state, theme: theme)
            } minimal: {
                compactValue(context.state, theme: theme)
            }
            .keylineTint(theme.accent)
        }
    }

    @ViewBuilder
    private func compactValue(_ state: WorkoutActivityAttributes.ContentState,
                              theme: WidgetTheme) -> some View {
        if state.phase == .rest, let end = state.restEndsAt {
            CountdownText(end: end, font: .laNumeral(14))
                .foregroundStyle(theme.ink)
                .frame(maxWidth: 44)
        } else {
            Text("\(state.setIndex)/\(state.totalSets)")
                .font(.laNumeral(14))
                .foregroundStyle(theme.ink)
        }
    }
}

/// Lock-screen / banner presentation: rest or active card.
struct LockScreenCard: View {
    let state: WorkoutActivityAttributes.ContentState
    private var theme: WidgetTheme { WidgetTheme(palette: state.palette) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if state.phase == .rest {
                RestRingView(state: state, theme: theme)
                UpNextView(state: state, theme: theme)
                Spacer(minLength: 0)
                Button(intent: SkipRestIntent()) {
                    Text("SKIP")
                        .font(.laLabel(11))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(theme.accent))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("la-skip-rest")
            } else {
                SetLockupView(state: state, theme: theme)
                Spacer(minLength: 0)
                exerciseEyebrow
            }
        }
        .padding(16)
        .background(theme.bg)
    }

    private var exerciseEyebrow: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(state.exerciseName)
                .font(.laName(15))
                .foregroundStyle(theme.ink)
            if let ss = state.ssLabel {
                Text(ss)
                    .font(.laLabel(10))
                    .foregroundStyle(theme.accent)
            }
        }
    }
}

#if DEBUG
extension WorkoutActivityAttributes {
    static var preview: WorkoutActivityAttributes { .init(workoutName: "Chest & Tris") }
}
extension WorkoutActivityAttributes.ContentState {
    static var restPreview: Self {
        .init(phase: .rest, exerciseName: "Flat Machine Press", setIndex: 2, totalSets: 4,
              setTypeLabel: "WORKING", isFilledChip: true, targetReps: 12, targetWeight: 60,
              ssLabel: nil, isMidPair: false, restEndsAt: Date().addingTimeInterval(75),
              totalRest: 90, nextExerciseName: "Flat Machine Press", nextReps: 12, nextWeight: 60,
              nextSsLabel: nil, completedSets: 5, totalStepCount: 11, palette: .coastal)
    }
    static var failurePreview: Self {
        .init(phase: .active, exerciseName: "Tricep Pushup", setIndex: 1, totalSets: 1,
              setTypeLabel: "FAILURE", isFilledChip: false, targetReps: nil, targetWeight: nil,
              ssLabel: nil, isMidPair: false, restEndsAt: nil, totalRest: 90,
              nextExerciseName: nil, nextReps: nil, nextWeight: nil, nextSsLabel: nil,
              completedSets: 10, totalStepCount: 11, palette: .coastal)
    }
}

#Preview("Lock — Rest", as: .content, using: WorkoutActivityAttributes.preview) {
    WorkoutLiveActivity()
} contentStates: {
    WorkoutActivityAttributes.ContentState.restPreview
    WorkoutActivityAttributes.ContentState.failurePreview
}
#endif
