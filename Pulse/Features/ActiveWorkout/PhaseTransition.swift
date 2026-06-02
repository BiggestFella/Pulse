import SwiftUI

/// Fade + 6pt rise mount transition, 0.28s — re-triggered on every phase change.
extension AnyTransition {
    static var phaseMount: AnyTransition {
        .modifier(
            active: PhaseMountModifier(opacity: 0, offset: 6),
            identity: PhaseMountModifier(opacity: 1, offset: 0)
        )
    }
}

private struct PhaseMountModifier: ViewModifier {
    let opacity: Double
    let offset: CGFloat
    func body(content: Content) -> some View {
        content.opacity(opacity).offset(y: offset)
    }
}
