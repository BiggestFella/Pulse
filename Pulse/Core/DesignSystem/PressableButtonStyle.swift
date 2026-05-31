import SwiftUI

enum PulseButtonSize { case sm, md, lg }
enum PulseButtonVariant { case primary, secondary, ghost }

/// Pure configuration table for the button styles. Unit-tested so the spec's
/// size/variant rules can't drift.
enum PulseButtonConfig {
    static let disabledOpacity: Double = 0.45

    static func height(for size: PulseButtonSize) -> CGFloat {
        switch size { case .sm: 42; case .md: 52; case .lg: 60 }
    }
    static func fontSize(for size: PulseButtonSize) -> CGFloat {
        switch size { case .sm: 14; case .md: 16; case .lg: 18 }
    }
    static func hPadding(for size: PulseButtonSize) -> CGFloat {
        switch size { case .sm: 18; case .md: 24; case .lg: 30 }
    }
    static func hasShadow(_ v: PulseButtonVariant) -> Bool { v == .primary }
    static func pressTranslates(_ v: PulseButtonVariant) -> Bool { v == .primary }
    /// Hard zero-blur drop-shadow Y offset: rest 5 → pressed 1.
    static func shadowY(pressed: Bool) -> CGFloat { pressed ? 1 : 5 }
    /// Content offset on press for primary (matches the shadow collapse).
    static let pressContentOffset: CGFloat = 4
}

/// The signature pressable button. Apply with `.buttonStyle(PressableButtonStyle(...))`.
struct PressableButtonStyle: ButtonStyle {
    var variant: PulseButtonVariant = .primary
    var size: PulseButtonSize = .md
    @Environment(Theme.self) private var theme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let translate = PulseButtonConfig.pressTranslates(variant) && pressed
        let contentOffset = translate ? PulseButtonConfig.pressContentOffset : 0

        return label(configuration)
            .frame(height: PulseButtonConfig.height(for: size))
            .padding(.horizontal, variant == .ghost ? 0 : PulseButtonConfig.hPadding(for: size))
            .background(background(pressed: pressed))
            .offset(y: contentOffset)
            .opacity(isEnabled ? 1 : PulseButtonConfig.disabledOpacity)
            .animation(.timingCurve(0.2, 0.7, 0.3, 1.4, duration: 0.1), value: pressed)
    }

    @ViewBuilder
    private func label(_ configuration: Configuration) -> some View {
        configuration.label
            .font(PulseFont.hanken("HankenGrotesk-Bold", size: PulseButtonConfig.fontSize(for: size)))
            .tracking(-0.005 * PulseButtonConfig.fontSize(for: size))
            .foregroundStyle(variant == .primary ? theme.onAccent : theme.ink)
    }

    @ViewBuilder
    private func background(pressed: Bool) -> some View {
        switch variant {
        case .primary:
            ZStack {
                // Hard, zero-blur drop shadow capsule behind the fill.
                Capsule().fill(theme.ink)
                    .offset(y: (isEnabled ? PulseButtonConfig.shadowY(pressed: pressed) : 2))
                Capsule()
                    .fill(theme.accent)
                    .overlay(Capsule().stroke(theme.ink, lineWidth: 2))
                    // inner top highlight + bottom shade
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.28), lineWidth: 2)
                            .blur(radius: 0).mask(Capsule().fill(
                                LinearGradient(colors: [.white, .clear],
                                               startPoint: .top, endPoint: .center)))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.22), lineWidth: 3)
                            .mask(Capsule().fill(
                                LinearGradient(colors: [.clear, .black],
                                               startPoint: .center, endPoint: .bottom)))
                    )
            }
        case .secondary:
            Capsule().fill(Color.clear)
                .overlay(Capsule().stroke(theme.ink, lineWidth: 1.5))
        case .ghost:
            Color.clear
        }
    }
}

extension PressableButtonStyle {
    static var primary: PressableButtonStyle { .init(variant: .primary, size: .md) }
    static var secondary: PressableButtonStyle { .init(variant: .secondary, size: .md) }
    static var ghost: PressableButtonStyle { .init(variant: .ghost, size: .md) }
}

/// Plain glyph icon button (⋯, back ←): translates +1pt on press only.
struct IconButtonStyle: ButtonStyle {
    @Environment(Theme.self) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PulseFont.hanken("HankenGrotesk-Bold", size: 18))
            .foregroundStyle(theme.ink)
            .frame(width: 36, height: 36)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview("Buttons") {
    let theme = Theme()
    return VStack(spacing: 18) {
        Button("Start →") {}.buttonStyle(PressableButtonStyle(variant: .primary, size: .lg))
        Button("Log set →") {}.buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
        Button("Skip") {}.buttonStyle(PressableButtonStyle(variant: .primary, size: .sm))
        Button("Cancel") {}.buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
        Button("Clear") {}.buttonStyle(PressableButtonStyle(variant: .ghost, size: .md))
        Button("Disabled") {}.buttonStyle(PressableButtonStyle(variant: .primary, size: .md)).disabled(true)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.bg)
    .environment(theme)
}
