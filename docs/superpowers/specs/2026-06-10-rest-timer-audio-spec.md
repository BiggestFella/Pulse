# Rest Timer Audio — Spec

**Date:** 2026-06-10
**Status:** Draft (awaiting approval)
**Sequence:** 1 of 5 (do first — small, fixes a daily annoyance)

## Problem

The rest timer (`RestView` + `ActiveWorkoutModel`) plays **no sound at all**. The
`UserSettings.soundOnRestEnd` flag (default `true`) and its You-tab toggle
(`you.toggle.sound`) exist but are wired to nothing — there is no `AVAudio*` /
`AudioToolbox` code anywhere in the project. So:

1. Rest end is silent — the user can't tell when rest is over without watching.
2. There is no warning before rest ends.
3. (Pre-emptive) Any naïve sound implementation would interrupt the user's
   background music (e.g. Spotify), which is unacceptable.

## Goals

- Play an **audible cue when rest ends**, gated by `soundOnRestEnd`.
- Play a **distinct cue 10 seconds before rest ends** (the "get ready" warning),
  gated by the same setting.
- **Never interrupt or pause background audio.** Spotify / Apple Music / podcasts
  keep playing; our cue mixes (or briefly ducks) over the top.
- Pair each cue with a **haptic** so it works even on silent/low volume.

## Non-goals

- Custom user-selectable sounds (v1 ships two fixed cues).
- Reading `defaultRestSeconds` into `restTotal` (currently hardcoded `90`) — see
  Open Questions; tracked separately if pursued.
- Reliable audio when the app is **backgrounded** and the screen is locked — the
  Live Activity already covers that surface visually. v1 targets the foreground
  rest screen. (Background delivery noted in Open Questions.)

## Current state (grounded)

- `Pulse/Features/ActiveWorkout/RestView.swift` — `TimelineView(.periodic … 0.2)`
  drives `model.remainingRest(now:)`; calls `model.afterRest()` when
  `remaining <= 0`. The "OF 1:30" label is hardcoded.
- `Pulse/Features/ActiveWorkout/ActiveWorkoutModel.swift` — `restTotal: TimeInterval = 90`,
  `restEndsAt: Date?`, `startRest`, `adjustRest`, `remainingRest`, `afterRest`.
- `Pulse/Core/Models/ProfileModels.swift:57` — `soundOnRestEnd: Bool`.

## Design

### New: `RestCueService` (`Pulse/Core/Workout/RestCueService.swift`)

A small `@Observable` (or plain) service owning audio + haptics, injected into
`ActiveWorkoutModel` (mock-friendly via a protocol, matching repo conventions).

```swift
protocol RestCuePlaying {
    func warn()   // T-10s "get ready" cue + light haptic
    func end()    // rest-over cue + success haptic
    func prepare()    // configure session, preload players
    func teardown()   // deactivate session when leaving rest
}
```

Real implementation `RestCueService`:

- **Audio session:** `AVAudioSession.sharedInstance()` category **`.playback`** with
  options **`[.mixWithOthers, .duckOthers]`** (DECIDED 2026-06-10). Background audio
  (Spotify/podcasts) keeps playing but is briefly ducked under the cue, and the cue
  is **audible even when the hardware silent switch is on** — chosen because the
  original complaint was inaudibility in the gym. Activate on `prepare()`, deactivate
  with `setActive(false, options: .notifyOthersOnDeactivation)` on `teardown()`.
- **Players:** two short bundled `.caf`/`.m4a` assets preloaded into
  `AVAudioPlayer`s — `warn` (single soft tick) and `end` (double chime).
- **Haptics:** `UINotificationFeedbackGenerator` (`.success` on end) and
  `UIImpactFeedbackGenerator` (`.light` on warn).

A `MockRestCueService` records `warn()`/`end()` calls for unit tests.

### Firing logic (in `ActiveWorkoutModel`)

The `TimelineView` ticks at 0.2s. Add edge-triggered firing in the model so cues
fire **once** per rest, independent of tick jitter:

- On `startRest`: `cue.prepare()`; reset `didWarn = false`.
- A `tick(now:)` (or extend `remainingRest`) computes `remaining`:
  - When `remaining <= 10` and `!didWarn` and `soundOnRestEnd`: `cue.warn()`; `didWarn = true`.
  - When `remaining <= 0`: `afterRest()` (existing) which calls
    `cue.end()` if `soundOnRestEnd`, then `cue.teardown()`.
- `adjustRest` that pushes remaining back above 10s **re-arms** `didWarn = false`
  so a later +30s adjustment still warns again.
- Skipping rest (`afterRest` early) calls `teardown()` and plays **no** end cue.

> Edge-triggering lives in the model (testable), not the View, so the 0.2s
> `TimelineView` cadence and any stray post-rest tick can't double-fire.

## Testing (acceptance criteria)

Unit (model + `MockRestCueService`):
1. Rest from 90s → exactly one `warn()` at ≤10s remaining, exactly one `end()` at 0.
2. `soundOnRestEnd == false` → zero `warn()`/`end()` calls; rest still advances.
3. `+30s` adjustment while in the warn window re-arms and warns again later.
4. "Skip rest" → `end()` not called; `teardown()` called.
5. A stray tick after `afterRest()` does not fire a second `end()`.

Manual (device — the audio-session behaviour can't be unit-tested):
6. With Spotify playing, run a rest: music keeps playing; cues are audible over it.
7. Silent switch on: cues are still audible (`.playback`) and haptics fire.

## Open questions

- **Session category:** ✅ RESOLVED 2026-06-10 → `.playback + [.mixWithOthers, .duckOthers]`
  (audible on silent, briefly ducks music) — chosen for audibility in the gym.
- **Background/locked delivery:** out of scope for v1; if wanted later, schedule a
  local notification with sound at `restEndsAt`. Ties into the Apple Watch spec
  (wrist haptic is the better answer).
- Adjacent bug: `restTotal` is hardcoded `90` and ignores
  `UserSettings.defaultRestSeconds`; "OF 1:30" is hardcoded in `RestView`. Fold
  into this issue or split? *Recommendation: small follow-up, not this spec.*
