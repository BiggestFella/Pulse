import SwiftUI

/// The You tab: profile header + MiniStat strip, a YOUR DATA hub of NavRows that
/// push to Stats / Personal Records / Workout History, the live Palette swatch
/// picker, and a Preferences card. Logic lives in `YouModel`, bound to the
/// repositories resolved from the environment `RepositoryContainer`. Palette is
/// owned by the injected `Theme`; the swatch picker (`PaletteView`) writes it.
struct YouView: View {
    @Environment(Theme.self) private var theme
    @Environment(RepositoryContainer.self) private var repos
    @State private var model: YouModel?
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: theme.spacing[5]) {
                        topBar
                        profileHeader
                        miniStatStrip
                        if case .failed = model?.phase { errorBanner }
                        yourDataSection
                        PaletteView()
                        preferencesSection
                        buildStamp
                    }
                    .padding(theme.spacing[6])
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .redacted(reason: model?.phase == .loading || model == nil ? .placeholder : [])
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HistoryRoute.self) { route in
                switch route {
                case .history:
                    WorkoutHistoryView(
                        model: WorkoutHistoryModel(
                            sessionRepo: repos.sessions,
                            workoutRepo: repos.workouts,
                            programRepo: repos.programs),
                        onSelectSession: { id in path.append(HistoryRoute.sessionDetail(id)) })
                case .sessionDetail(let id):
                    SessionDetailView(
                        model: SessionDetailModel(
                            sessionID: id,
                            sessionRepo: repos.sessions,
                            workoutRepo: repos.workouts,
                            programRepo: repos.programs,
                            exerciseRepo: repos.exercises))
                }
            }
        }
        .task {
            if model == nil { model = Self.makeModel(repos: repos) }
            await model?.load()
        }
    }

    /// Builds the model from the environment repositories. A launch argument lets
    /// UI tests deterministically drive the non-fatal failure path (AC10–AC11).
    private static func makeModel(repos: RepositoryContainer) -> YouModel {
        if ProcessInfo.processInfo.arguments.contains("-uiTestYouError") {
            return YouModel(userRepo: InMemoryUserRepository(shouldFail: true),
                            settingsRepo: repos.settings)
        }
        return YouModel(userRepo: repos.user, settingsRepo: repos.settings)
    }

    private var settings: UserSettings { model?.settings ?? .default }

    // MARK: Sections

    private var topBar: some View {
        HStack {
            Text("YOU")
                .pulseStyle(.eyebrow)
                .foregroundStyle(theme.inkSoft)
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("you.overflow") // inert in v1 (product decision)
        }
    }

    private var profileHeader: some View {
        HStack(spacing: theme.spacing[3]) {
            Text(model?.profile?.avatarInitial ?? "?")
                .font(PulseFont.oswald("Oswald-Bold", size: 30))
                .foregroundStyle(theme.onAccent)
                .frame(width: 56, height: 56)
                .background(theme.accent, in: Circle())
                .overlay(Circle().stroke(theme.ink, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text((model?.profile?.displayName ?? "—") + ".")
                    .pulseStyle(.h1)
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)
                Text(model?.profile?.subtitle ?? "Member since — · —")
                    .pulseStyle(.rowSub)
                    .foregroundStyle(theme.inkSoft)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("you.profileHeader")
    }

    private var miniStatStrip: some View {
        let stats = model?.stats ?? .empty
        let vol = VolumeFormatter.compact(stats.totalVolumeKg)
        return HStack(spacing: theme.spacing[0]) {
            MiniStat(label: "STREAK", value: "\(stats.streakDays)", unit: "d", tint: .accent2)
            MiniStat(label: "SESSIONS", value: "\(stats.totalSessions)")
            MiniStat(label: "VOLUME", value: vol.value, unit: vol.unit, tint: .accent)
        }
    }

    private var errorBanner: some View {
        Text("Couldn't refresh your stats. Showing saved settings.")
            .pulseStyle(.rowSub)
            .foregroundStyle(theme.accent2)
            .accessibilityIdentifier("you.errorBanner")
    }

    private var yourDataSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Text("YOUR DATA").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
            NavigationLink {
                StatsView(repository: repos.stats)
            } label: {
                NavRow(glyph: .symbol("chart.bar.fill"), tileColor: theme.accent,
                       name: "Stats", sub: "Volume, PRs, charts")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("you.stats")

            NavigationLink {
                PersonalRecordsView(prRepo: repos.prs, exerciseRepo: repos.exercises)
            } label: {
                NavRow(glyph: .text("PR"), tileColor: theme.accent2,
                       name: "Personal records",
                       sub: "\(model?.stats?.liftsTracked ?? 0) lifts tracked")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("you.personalRecords")

            NavigationLink(value: HistoryRoute.history) {
                NavRow(glyph: .text("H"), tileColor: theme.inkFaint, glyphColor: theme.ink,
                       name: "Workout history",
                       sub: "\(model?.stats?.sessionsLogged ?? 0) sessions logged")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("you.workoutHistory")
        }
    }

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Text("PREFERENCES").pulseStyle(.eyebrow).foregroundStyle(theme.inkSoft)
            VStack(spacing: 0) {
                PreferenceValueRow(label: "Units", value: settings.units.displayLabel)
                PreferenceValueRow(label: "Default rest timer", value: settings.restTimerLabel)
                PreferenceToggleRow(label: "Auto-progress weight", isOn: Binding(
                    get: { settings.autoProgressWeight },
                    set: { v in Task { await model?.setAutoProgress(v) } }))
                    .accessibilityIdentifier("you.toggle.autoProgress")
                PreferenceToggleRow(label: "Sound on rest end", isOn: Binding(
                    get: { settings.soundOnRestEnd },
                    set: { v in Task { await model?.setSoundOnRest(v) } }))
                    .accessibilityIdentifier("you.toggle.sound")
            }
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: theme.radiusCard)
                .stroke(theme.inkFaint, lineWidth: 1.5))
        }
    }

    /// Build identity (version · commit · date) so a running build is identifiable.
    private var buildStamp: some View {
        Text(BuildInfo.fromBundle().footerLabel)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(theme.inkFaint)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, theme.spacing[2])
            .accessibilityIdentifier("you.buildStamp")
    }
}

#Preview {
    YouView()
        .environment(Theme())
        .environment(RepositoryContainer(useMock: true))
}
