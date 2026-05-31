import SwiftUI

/// Shared design-system motion. Timing curves match the prototype.
enum PulseMotion {
    /// Screen mount fade+rise: cubic-bezier(.2,.7,.3,1), .28s.
    static let fadeIn = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.28)
    /// Sheet slide-up: same curve, .25s.
    static let sheetUp = Animation.timingCurve(0.2, 0.7, 0.3, 1, duration: 0.25)
}

/// AC11: opacity 0→1 + 6pt rise on mount; re-fires when `id` changes.
private struct FadeInOnMount<ID: Hashable>: ViewModifier {
    let id: ID
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear { withAnimation(PulseMotion.fadeIn) { shown = true } }
            .onChange(of: id) { _, _ in
                shown = false
                withAnimation(PulseMotion.fadeIn) { shown = true }
            }
    }
}

extension View {
    /// Fade+rise on mount, replaying whenever `id` changes (tab/overlay/phase).
    func fadeInOnMount<ID: Hashable>(id: ID) -> some View {
        modifier(FadeInOnMount(id: id))
    }
}

#Preview("FadeIn") {
    struct Demo: View {
        @State private var screen = 0
        let theme = Theme()
        var body: some View {
            VStack(spacing: 24) {
                Text("Screen \(screen)")
                    .pulseStyle(.h1)
                    .foregroundStyle(theme.ink)
                    .fadeInOnMount(id: screen)
                Button("Next") { screen += 1 }
                    .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.bg)
            .environment(theme)
        }
    }
    return Demo()
}
