#if DEBUG
import SwiftUI

/// DEBUG-only harness that renders the Live Activity's shared subviews in-app so
/// XCUITest can assert their content (the real Live Activity can't be driven on
/// the simulator lock screen). Selected via launch arguments from `AppShell`.
/// Renders the subviews directly rather than `LockScreenCard` so tests target the
/// content surfaces (ring / lockup / UP NEXT) without the card's interactive
/// `Button(intent:)`, which XCUITest can't meaningfully exercise here.
struct LiveActivityDebugScreen: View {
    let state: WorkoutActivityAttributes.ContentState
    private var theme: WidgetTheme { WidgetTheme(palette: state.palette) }

    var body: some View {
        VStack(spacing: 16) {
            if state.phase == .rest {
                RestRingView(state: state, theme: theme)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("la-rest-ring")
                UpNextView(state: state, theme: theme)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("la-up-next")
            } else {
                SetLockupView(state: state, theme: theme)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("la-set-lockup")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
    }

    static var restFixture: WorkoutActivityAttributes.ContentState {
        .init(phase: .rest, exerciseName: "Flat Machine Press", setIndex: 2, totalSets: 4,
              setTypeLabel: "WORKING", isFilledChip: true, targetReps: 12, targetWeight: 60,
              ssLabel: nil, isMidPair: false, restEndsAt: Date().addingTimeInterval(75),
              totalRest: 90, nextExerciseName: "Flat Machine Press", nextReps: 12, nextWeight: 60,
              nextSsLabel: nil, completedSets: 5, totalStepCount: 11, palette: .coastal)
    }
    static var failureFixture: WorkoutActivityAttributes.ContentState {
        .init(phase: .active, exerciseName: "Tricep Pushup", setIndex: 1, totalSets: 1,
              setTypeLabel: "FAILURE", isFilledChip: false, targetReps: nil, targetWeight: nil,
              ssLabel: nil, isMidPair: false, restEndsAt: nil, totalRest: 90,
              nextExerciseName: nil, nextReps: nil, nextWeight: nil, nextSsLabel: nil,
              completedSets: 10, totalStepCount: 11, palette: .coastal)
    }
}
#endif
