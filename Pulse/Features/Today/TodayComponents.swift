import SwiftUI

/// Uppercase mono eyebrow/label (Geist Mono per design; system monospaced until
/// BAK-7 vendors the font). Tracking + soft ink per the handoff.
struct Eyebrow: View {
    @Environment(Theme.self) private var theme
    let text: String
    var emphasis: Double = 1.0
    init(_ text: String, emphasis: Double = 1.0) { self.text = text; self.emphasis = emphasis }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(theme.inkSoft.opacity(emphasis))
    }
}

/// Giant condensed poster numeral (Oswald per design; fixed point-size, no
/// Dynamic Type scaling per product decision). System until BAK-7 vendors Oswald.
struct PosterNumeral: View {
    let value: Int
    var size: CGFloat = 72
    var color: Color
    var body: some View {
        Text("\(value)")
            .font(.system(size: size, weight: .bold, design: .default))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// Press feedback: nudges down 1pt while pressed (design's icon/button behavior).
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

#Preview {
    @Previewable @State var theme = Theme()
    return VStack(alignment: .leading, spacing: 16) {
        Eyebrow("TODAY · PPL · WEEK 4")
        PosterNumeral(value: 7, color: theme.accent)
        Button("Start") {}.buttonStyle(PressableStyle())
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(theme.bg)
    .environment(theme)
}
