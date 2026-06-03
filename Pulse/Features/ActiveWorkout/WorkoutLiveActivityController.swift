import ActivityKit
import Foundation

/// Wraps ActivityKit so the controller is testable; tests inject a mock.
@MainActor
protocol LiveActivityHandle: AnyObject {
    var isRunning: Bool { get }
    func start(_ state: WorkoutActivityAttributes.ContentState, name: String)
    func update(_ state: WorkoutActivityAttributes.ContentState)
    func end()
}

/// Projects the session engine onto the Live Activity and owns its lifecycle.
/// A projection — it reads the engine and routes Skip-rest back through the
/// engine's `afterRest`; it never holds canonical session state. Not `@Observable`:
/// it surfaces no state to views — the flow view owns it and drives `sync()`.
@MainActor
final class WorkoutLiveActivityController: SkipRestTarget {
    private let model: ActiveWorkoutModel
    private let handle: LiveActivityHandle
    private let paletteProvider: () -> Palette

    /// Designated initialiser — tests inject a mock handle and palette provider.
    init(model: ActiveWorkoutModel,
         handle: LiveActivityHandle,
         paletteProvider: @escaping () -> Palette) {
        self.model = model
        self.handle = handle
        self.paletteProvider = paletteProvider
        SkipRestIntent.target = self
    }

    /// Production convenience init: uses the real ActivityKit handle and reads
    /// the persisted palette from UserDefaults (so the widget snapshot matches
    /// the active Coastal/Mint theme even in the widget process).
    convenience init(model: ActiveWorkoutModel) {
        self.init(
            model: model,
            handle: ActivityKitHandle(),
            paletteProvider: {
                UserDefaults.standard.string(forKey: Theme.paletteDefaultsKey)
                    .flatMap(Palette.init(rawValue:)) ?? .default
            }
        )
    }
    // No deinit needed to clear SkipRestIntent.target: it's a `weak` slot, so it
    // auto-nils when this controller deallocates (and can't be touched from a
    // nonisolated deinit anyway).

    /// Call after every engine transition. Starts the Activity on the first
    /// `.active`, updates it on every push, and ends it when the session ends
    /// (`endWorkout` → not active) or finishes (`.summary`).
    func sync() {
        guard model.isActive else {
            if handle.isRunning { handle.end() }
            return
        }
        switch model.phase {
        case .pre:
            break // pre-workout plan screen — no Activity yet
        case .active, .rest:
            let state = WorkoutLiveActivityContent.make(from: model, palette: paletteProvider())
            if handle.isRunning { handle.update(state) } else { handle.start(state, name: model.workout.name) }
        case .summary:
            if handle.isRunning { handle.end() }
        }
    }

    /// Rest adjust delegates to the engine (which clamps remaining ≥ 0, no upper
    /// clamp) then re-pushes the new end timestamp.
    func adjustRest(by delta: TimeInterval, now: Date = .now) {
        model.adjustRest(delta, now: now)
        sync()
    }

    /// SkipRestTarget — the Live Activity "Skip rest" button routes here.
    func afterRest() {
        model.afterRest()
        sync()
    }
}

/// Production ActivityKit handle. Graceful no-op when Live Activities are
/// disabled or unsupported, so the in-app workout is unaffected.
@MainActor
final class ActivityKitHandle: LiveActivityHandle {
    private var activity: Activity<WorkoutActivityAttributes>?
    var isRunning: Bool { activity != nil }

    func start(_ state: WorkoutActivityAttributes.ContentState, name: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutActivityAttributes(workoutName: name)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil))
    }

    // update/end are fire-and-forget: ActivityKit serialises its own state
    // (last write wins), and `end()` nils `activity` synchronously so a
    // subsequent sync() can't double-end. The push-ordering race is benign.
    func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activity else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end() {
        let finishing = activity
        activity = nil
        Task { await finishing?.end(nil, dismissalPolicy: .immediate) }
    }
}
