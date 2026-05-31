# Auth & Onboarding — Spec
**Linear:** BAK-8  |  **Date:** 2026-05-31  |  **Status:** Draft for review

> ⚠️ **No design source.** Auth and onboarding are explicitly listed as **"Not yet built"**
> in `docs/design/README.md` (line 100: *"persistence/sync, auth/onboarding, empty/loading/error
> states… to spec server-side"*). There is **no auth screen in the prototype** (`pulse-app.jsx`)
> and **no token, type, or component** specified for it. This spec therefore **derives a minimal
> Supabase-auth gate** from the existing design system, surfaces a large number of open questions,
> and proposes the smallest flow that lets the app gate its tabs behind a signed-in session. The
> visual treatment reuses existing design-system primitives only (no new tokens). Treat every
> product decision below as provisional pending the human gate.

## Overview
This feature adds an **authentication gate** in front of the four-tab app shell: an unauthenticated
user sees a sign-in / sign-up flow; an authenticated user sees the normal Today/Library/Plan/You
shell. It introduces an app-root **session state** that decides which branch renders, a minimal
**Welcome → Auth** screen pair built from existing design tokens, and a thin first-run **onboarding**
hand-off (display name capture) so the You tab has a name to show. Per the UI-first build strategy
(BAK-6), auth is implemented against an `AuthRepository` protocol backed by an **in-memory mock**;
real Supabase email/OTP/OAuth wiring is deferred to the data-layer feature.

## User story
As a lifter, I want to sign in (or create an account) when I open Pulse and stay signed in across
launches, so that my programs, sessions, and stats are tied to my account and I land straight in the
app on subsequent opens.

## Acceptance criteria
1. On launch, the app root resolves an **auth state** before showing UI: while resolving, a branded
   **splash/loading** state renders (no tab bar, no flash of the signed-in shell).
2. When **no session** exists, the root renders the **auth flow** (Welcome + Auth screen) and the
   four-tab `AppShell` is **not** mounted.
3. When a **valid session** exists (restored from persistence on launch, or just established), the
   root mounts the four-tab `AppShell` and the auth flow is dismissed.
4. The **Welcome** screen renders the app name/wordmark as an H1 lockup, a one-line value sub, and a
   primary **Get started →** pressable button plus a secondary **I already have an account** action,
   using only existing `Theme` tokens (`accent` fill / `onAccent` text / `2px solid ink` / hard
   bottom shadow).
5. The **Auth** screen accepts an **email** and **password** (provisional — see Open questions on
   method), with a mode toggle between **Sign in** and **Create account**, a primary submit button,
   and inline validation messaging.
6. Submitting valid credentials calls `AuthRepository.signIn`/`signUp`; on success the model sets the
   session and the root transitions to the signed-in shell (AC 3).
7. While a submit is in flight, the submit button shows a **loading/disabled** state and inputs are
   non-editable; a second submit cannot be issued concurrently.
8. On an **auth error** (bad credentials, email taken, network), the model surfaces a **non-fatal,
   inline error message** on the auth screen; inputs retain their values and remain editable for retry.
9. **Invalid input** (empty/malformed email, password below the minimum) is caught **client-side**
   before any repository call and shown inline; the submit button is disabled until input is valid.
10. On first successful **sign-up**, a minimal **onboarding step** captures a **display name** (used
    by the You tab profile) before entering the shell; on **sign-in** of an existing account this step
    is skipped.
11. A **Sign out** action (surfaced on the You tab — see Dependencies) calls
    `AuthRepository.signOut`, clears the session, and returns the root to the auth flow.
12. The session **persists across app launches** (mock persists in-memory + a launch flag; real
    persistence is BAK-6) so a returning user is not asked to sign in again until signed out or expired.
13. All colors, spacing, typography, and press feedback use **`Theme` tokens and existing
    design-system primitives** — no hardcoded hex, no new bespoke styling.

## Screen / UX behavior
There is no prototype reference; the following composes existing primitives (BAK-7) into the
minimal screens this gate needs.

- **Root branching (app shell):** the app root (`PulseApp` / `AppShell` host) observes an
  `@Observable AuthModel.state`:
  - `.resolving` → **Splash**: full-bleed `bg`, centered wordmark lockup (Oswald/Hanken), optional
    subtle activity indicator; tab bar hidden. This is the single source of "are we signed in yet".
  - `.signedOut` → **AuthFlow** (Welcome → Auth), tab bar hidden.
  - `.signedIn` → the existing four-tab `AppShell`.
  - Branch changes use the standard screen **fade+rise** mount (`.28s`, timing curve `0.2,0.7,0.3,1`).
- **Welcome screen:** top padding, an H1 wordmark lockup (giant Oswald numeral/word per the lockup
  pattern, or app name in Hanken 800 with trailing period), a Geist Mono eyebrow + a short Hanken sub
  line, then a primary **Get started →** button (`lg`, `accent` fill, `onAccent` text, hard bottom
  shadow that collapses 5pt→1pt on press) and a **ghost/secondary** "I already have an account" action.
- **Auth screen:** back/`←` icon button in a top bar; a Geist Mono eyebrow reflecting mode
  (`SIGN IN` / `CREATE ACCOUNT`); H1 title; **email** and **password** fields styled as `surface`
  rows with `inkFaint` borders, `ink` text, Geist Mono field labels; a primary submit button
  (label `Sign in →` / `Create account →`); a ghost mode-toggle ("New here? Create account" /
  "Have an account? Sign in"). Inline error text uses `accent2` for emphasis on a non-accent surface
  (error is a flag, per the color-usage rule). Loading state dims/disables the form and shows progress
  in the button.
- **Onboarding (post sign-up):** a single screen capturing **display name** (one `surface` text field
  + Geist Mono label), with a primary **Continue →** button that completes onboarding and enters the
  shell. Minimal by design; richer onboarding (program selection, units, palette) is out of scope.
- **Sheets:** none required for v1. (OAuth provider chooser, if added later, would be a bottom sheet.)
- **Navigation within auth:** Welcome → Auth is a push within an auth-local `NavigationStack`;
  it does **not** use the four tab `NavigationStack`s (those belong to the signed-in shell).
- **Press/motion:** all buttons use the standard pressable `ButtonStyle`; no implicit animation that
  could flash the wrong branch during the resolve→signedIn transition.

## Data & state
`@Observable` model `AuthModel` in `Pulse/Features/Auth/`:

```swift
enum AuthState: Equatable {
    case resolving                 // launch: restoring persisted session
    case signedOut                 // show Welcome/Auth
    case onboarding(UserSession)   // signed up, needs display name
    case signedIn(UserSession)     // show AppShell
}

enum AuthMode { case signIn, signUp }

@Observable final class AuthModel {
    private(set) var state: AuthState = .resolving
    var mode: AuthMode = .signIn
    var email: String = ""
    var password: String = ""
    var displayName: String = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?     // inline, non-fatal
    var isInputValid: Bool { /* email format + password length */ }

    func restoreSession() async { /* AuthRepository.currentSession → state */ }
    func submit() async { /* validate → signIn/signUp → set state or errorMessage */ }
    func completeOnboarding() async { /* persist displayName → .signedIn */ }
    func signOut() async { /* AuthRepository.signOut → .signedOut */ }
}
```

Repository protocol consumed (defined/owned by **BAK-6**; **mock implementation + sample session
assumed to exist**):

```swift
protocol AuthRepository {
    func currentSession() async throws -> UserSession?            // launch restore
    func signIn(email: String, password: String) async throws -> UserSession
    func signUp(email: String, password: String) async throws -> UserSession
    func updateDisplayName(_ name: String) async throws -> UserSession
    func signOut() async throws
}
```

Supporting domain type (lives in `Core/Models`, not the prototype): `UserSession(userID, email,
displayName?, isNewUser)`. **Mock data the flow renders against:** the in-memory `AuthRepository`
mock seeds **one signed-in user** (`Alex Mason`, the same identity the You spec renders against) so
that, in mock mode, the app can either (a) launch already signed-in for screen development, or
(b) launch signed-out via a launch arg to exercise the auth flow. Which is the default is an Open
question. The mock validates against a hard-coded credential set and simulates the error/loading
paths so all states are buildable without Supabase.

The active `Palette`/`Theme` is resolved at the app root and applies to the auth/splash screens too,
so the gate is themed identically to the rest of the app.

## Out of scope
- **Real Supabase auth wiring** (email magic-link/OTP, OAuth providers, JWT refresh, secure token
  storage in Keychain) — owned by **BAK-6**. This feature binds to the `AuthRepository` protocol only.
- **Password reset / forgot-password**, email verification, and account deletion flows.
- **Third-party / social sign-in** (Apple, Google) UI and provider plumbing.
- **Rich onboarding**: program selection, units/palette setup, goal questionnaires, permission primers
  (notifications, HealthKit) — only a single display-name step is in scope.
- **Profile editing / avatar upload** (the You tab profile is read-only per BAK-13).
- **Multi-account / account switching.**
- The **Sign out row UI** itself lives on the You tab (BAK-13); this feature provides only the
  `signOut()` behavior and the root transition it triggers.
- Any **Live Activity / Widget** session-identity concerns (BAK-14).

## Edge cases
- **Launch with valid persisted session** → straight to shell, no auth flash (splash must fully
  cover the resolve window).
- **Launch with no/expired session** → auth flow; expired-session restore must fail gracefully to
  `.signedOut`, not crash.
- **Repository throws on `currentSession()`** at launch → treat as signed-out (non-fatal), show auth.
- **Empty / malformed email, short password** → client-side validation blocks submit; inline message;
  button disabled.
- **Duplicate email on sign-up / wrong password on sign-in** → inline error, inputs preserved, retry
  allowed.
- **Network failure mid-submit** → inline error, button returns to enabled, no partial session set.
- **Double-submit** → guarded by `isSubmitting`; concurrent submits are ignored.
- **Sign out** → state returns to `.signedOut`; all signed-in tab `NavigationStack` paths are torn
  down with the shell (no stale stack when a different user signs in).
- **Empty display name at onboarding** → blocked or defaulted (see Open questions); must not produce a
  nameless profile that breaks the You avatar/initial.
- **Theme switching** while signed out → splash/auth screens re-skin instantly like the rest of the app;
  background must not animate/flash on palette change.

## Open questions
1. **Auth method.** This spec assumes **email + password** as the minimal derivable flow. Is the
   intended method actually **email magic-link / OTP** (common with Supabase), **password**, or
   **OAuth (Apple/Google)**? The screen layout and validation differ substantially. *Unspecified by design.*
2. **Wordmark / branding.** There is no logo or app-name treatment in the design bundle (README:
   "No raster images or logos"). What does the Welcome/Splash render as the brand lockup — the word
   "Pulse" in Hanken/Oswald, or an asset to be provided?
3. **Default launch state in mock mode.** Should the mock `AuthRepository` launch **already signed in**
   (so other UI-first features build without auth friction) or **signed out** (to exercise this flow),
   and what launch arg toggles it?
4. **Is onboarding in scope at all for v1**, or should sign-up drop the user straight into the shell
   with a default name? The design has no onboarding screens.
5. **Display name** — required or optional? If optional/empty, what is the fallback for the You-tab
   avatar initial and `displayName`?
6. **Password rules** — minimum length / complexity? Not specified.
7. **Session lifetime / "remember me"** — does the app stay signed in indefinitely until explicit
   sign-out, or expire? (Real expiry is BAK-6, but the mock's behavior and any UI affordance need a call.)
8. **Sign-out confirmation** — does signing out require a confirm dialog/sheet, and does it clear local
   cached data? (Data clearing semantics belong to BAK-6.)
9. **Error copy** — exact wording/tone for invalid-credential, taken-email, and network errors is
   undefined; placeholder copy used pending product input.
10. **Should the splash double as the existing launch screen / `LaunchScreen`**, or is it a separate
    SwiftUI view shown after launch? Interaction with the iOS launch storyboard is unspecified.
11. **Accessibility** — Dynamic Type / VoiceOver expectations for the auth fields and buttons are not
    specified anywhere in the design; assume standard support pending confirmation.

## Tests required
**Unit (`AuthModel`):**
- `restoreSession()` sets `.signedIn` when the mock returns a valid session, `.signedOut` when it
  returns `nil`, and `.signedOut` (non-fatal) when the repo throws.
- `isInputValid` is `false` for empty/malformed email and short password, `true` for valid input.
- `submit()` in `.signIn` mode with valid mock credentials sets `.signedIn`; with bad credentials sets
  `errorMessage` and leaves `state == .signedOut` (inputs preserved).
- `submit()` in `.signUp` mode with a fresh email transitions to `.onboarding`; duplicate email sets
  `errorMessage`.
- `submit()` sets `isSubmitting` true during the call and false after; a second `submit()` while
  in-flight is ignored.
- `completeOnboarding()` persists the display name and transitions `.onboarding` → `.signedIn`.
- `signOut()` transitions to `.signedOut`.

**Acceptance / UI (map to ACs):**
- AC1–AC3: launching with a seeded session lands in the shell; launching signed-out shows the auth
  flow and no tab bar; the splash covers the resolve window (no shell flash).
- AC4–AC5: Welcome renders brand + both actions; Auth renders email/password, mode toggle, submit.
- AC6: submitting valid credentials transitions to the shell.
- AC7: in-flight submit disables the form/button and blocks a second submit.
- AC8: a forced repo error shows inline error text and preserves inputs for retry.
- AC9: invalid input keeps submit disabled and shows inline validation.
- AC10: sign-up routes through the onboarding display-name step; sign-in skips it.
- AC11: invoking sign-out (via the model) returns the root to the auth flow and tears down the shell.
- AC12: a seeded session survives a simulated relaunch (no re-prompt).
- AC13: snapshot/lint check that the auth/splash screens use only `Theme` tokens (no hardcoded hex/spacing).

## Files that will change
- `Pulse/Features/Auth/AuthRootView.swift` — root branch view (splash / auth flow / shell) driven by `AuthModel`.
- `Pulse/Features/Auth/WelcomeView.swift` — Welcome screen.
- `Pulse/Features/Auth/AuthView.swift` — sign-in / sign-up screen.
- `Pulse/Features/Auth/OnboardingView.swift` — minimal display-name step.
- `Pulse/Features/Auth/AuthModel.swift` — the `@Observable` model.
- `Pulse/Features/Auth/Components/AuthTextField.swift` — themed email/password field (if not shared).
- `Pulse/App/PulseApp.swift` / `Pulse/App/AppShell.swift` — host `AuthRootView` at the root; mount the
  four-tab shell only in `.signedIn`; inject the auth environment.
- `Pulse/Core/Models/UserSession.swift` — domain struct (if not already present from BAK-6).
- `Pulse/Core/Data/AuthRepository.swift` — repository protocol + in-memory mock conformance + seeded
  session/credentials (protocol owned by BAK-6; this feature consumes/extends it).
- `PulseTests/AuthModelTests.swift` — unit tests for the model.
- `PulseUITests/AuthFlowTests.swift` — acceptance/UI tests mapping to the ACs.
- `project.yml` — only if new files require target/group updates (regenerate via `xcodegen generate`;
  never hand-edit `.xcodeproj`).

## Dependencies
- **BAK-7 (Design System):** `Theme` tokens, typography (Hanken/Oswald/Geist Mono), the pressable
  `ButtonStyle` (hard bottom shadow + press collapse), `Eyebrow`/H1/lockup and row/field primitives,
  and the palette/`@AppStorage("pulse-pal")` plumbing applied to splash/auth screens.
- **BAK-6 (Data layer):** the `AuthRepository` protocol + in-memory mock + seeded `UserSession`. This
  UI-first feature binds to that protocol backed by mocks; real Supabase email/OTP/OAuth, token
  storage, and refresh are implemented there.
- **BAK-13 (You / Settings):** consumes the session — the **Sign out** row lives on the You tab and
  invokes `AuthModel.signOut()`; the captured `displayName` feeds the You profile header/avatar.
- **BAK-14 (active flow / session engine):** unaffected by auth, but any Live Activity/Widget that
  needs user identity depends on the session established here.
