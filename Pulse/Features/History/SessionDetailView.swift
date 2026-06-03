import SwiftUI

struct SessionDetailView: View {
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var model: SessionDetailModel

    init(model: SessionDetailModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            topBar
            content
        }
        .padding(.horizontal, theme.spacing[5])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .task { await model.load() }
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left").foregroundStyle(theme.ink)
            }
            .accessibilityIdentifier("session.back")
            Spacer()
            StatLabel(model.session?.dateEyebrow ?? "SESSION")
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("session.overflow")   // inert per product decision
        }
        .padding(.top, theme.spacing[3])
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().tint(theme.accent)
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityIdentifier("session.loading")
        case .error:
            errorState
        case .loaded:
            if let session = model.session { loaded(session) }
        }
    }

    @ViewBuilder private func loaded(_ session: SessionDetailModel.Detail) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("session.h1")
                Text(session.subLine)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.inkSoft)
                    .accessibilityIdentifier("session.subline")
            }

            statBoxes(session)

            StatLabel("LOG")

            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing[1]) {
                    ForEach(Array(session.log.enumerated()), id: \.element.id) { index, row in
                        LogRowView(index: index + 1, row: row)
                    }
                }
            }

            footer
        }
    }

    private func statBoxes(_ session: SessionDetailModel.Detail) -> some View {
        HStack(spacing: theme.spacing[1]) {
            StatBox(label: "VOLUME", value: session.volumeLabel,
                    unit: session.volumeUnit.isEmpty ? nil : session.volumeUnit,
                    sub: "kg", accent: false)
                .accessibilityIdentifier("session.volumeBox")
            StatBox(label: "PR", value: model.prValueLabel, unit: nil,
                    sub: model.prSubLabel, accent: model.prIsAccent)
                .accessibilityIdentifier("session.prBox")
        }
    }

    private var footer: some View {
        HStack(spacing: theme.spacing[2]) {
            Button("Duplicate") { model.duplicate() }
                .buttonStyle(PressableButtonStyle(variant: .secondary, size: .sm))
                .accessibilityIdentifier("session.duplicate")
            Button("Repeat workout →") { model.repeatWorkout() }
                .buttonStyle(PressableButtonStyle(variant: .primary, size: .sm))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("session.repeat")
        }
    }

    private var errorState: some View {
        VStack(spacing: theme.spacing[2]) {
            Text("Couldn't load this session.")
                .font(.system(size: 14))
                .foregroundStyle(theme.ink)
            Button("Retry") { Task { await model.retry() } }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.accent)
                .accessibilityIdentifier("session.retry")
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .accessibilityIdentifier("session.error")
    }
}

/// Two-line stat box. `accent == true` draws the accent-bordered PR variant.
struct StatBox: View {
    let label: String
    let value: String
    var unit: String?
    let sub: String
    var accent: Bool
    @Environment(Theme.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[0]) {
            StatLabel(label, color: accent ? theme.accent2 : nil)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(accent ? theme.accent : theme.ink)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(theme.ink.opacity(0.6))
                }
            }
            StatLabel(sub)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing[3])
        .background(
            RoundedRectangle(cornerRadius: theme.radiusCard)
                .fill(theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radiusCard)
                        .stroke(theme.accent, lineWidth: accent ? 2 : 0)))
    }
}

/// One numbered LOG row: index badge · name/detail · optional PR · volume figure.
private struct LogRowView: View {
    @Environment(Theme.self) private var theme
    let index: Int
    let row: SessionDetailModel.LogRow

    var body: some View {
        HStack(spacing: theme.spacing[2]) {
            Text("\(index)")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(theme.onAccent)
                .frame(width: 20, height: 20)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.ink)
                Text(row.detail.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(theme.inkSoft)
            }
            Spacer()
            if row.hasPR { PrBadge() }
            Text(row.volumeLabel)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.ink)
        }
        .padding(.vertical, theme.spacing[2])
        .padding(.horizontal, theme.spacing[3])
        .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusCard))
    }
}

#Preview("Loaded") {
    let store = MockStore()
    let id = store.sessions.sorted { $0.startedAt > $1.startedAt }.first!.id
    return NavigationStack {
        SessionDetailView(model: SessionDetailModel(
            sessionID: id,
            sessionRepo: InMemorySessionRepository(store: store),
            workoutRepo: InMemoryWorkoutRepository(store: store),
            programRepo: InMemoryProgramRepository(store: store),
            exerciseRepo: InMemoryExerciseRepository(store: store)))
    }
    .environment(Theme())
}
