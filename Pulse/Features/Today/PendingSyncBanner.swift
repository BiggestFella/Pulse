import SwiftUI

/// Global "pending sync" indicator (BAK-32). Shown on the Today tab whenever the
/// offline buffer holds finished-but-unsynced sessions, so the state is visible
/// after the user leaves the summary. Tapping it retries the flush; the
/// connectivity monitor also flushes automatically on reconnect.
struct PendingSyncBanner: View {
    @Environment(Theme.self) private var theme
    let count: Int
    let onTap: () async -> Void
    @State private var isFlushing = false

    var body: some View {
        Button {
            guard !isFlushing else { return }
            Task { isFlushing = true; await onTap(); isFlushing = false }
        } label: {
            HStack(spacing: 8) {
                if isFlushing {
                    ProgressView().tint(theme.onAccent)
                } else {
                    Image(systemName: "icloud.and.arrow.up").foregroundStyle(theme.onAccent)
                }
                Text(label)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.onAccent)
                Spacer()
                Text(isFlushing ? "SYNCING…" : "RETRY")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .foregroundStyle(theme.onAccent.opacity(0.8))
            }
            .padding(theme.spacing[2])
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radiusCard))
        }
        .buttonStyle(PressableStyle())
        .accessibilityIdentifier("today.pendingSync")
    }

    private var label: String {
        count == 1 ? "1 workout pending sync" : "\(count) workouts pending sync"
    }
}
