import SwiftUI

/// Resolves the palette snapshot embedded in ContentState into Colors, mirroring
/// `Theme`'s resolution so the widget renders the active Coastal/Mint palette
/// without an App Group (the widget process can't read the environment Theme).
struct WidgetTheme {
    let palette: Palette
    private var t: PaletteTokens { palette.tokens }
    var bg: Color { Color(hex: t.bg) }
    var surface: Color { Color(hex: t.surface) }
    var ink: Color { Color(hex: t.ink) }
    var inkSoft: Color { Color(hex: t.ink).opacity(palette.inkSoftOpacity) }
    var inkFaint: Color { Color(hex: t.ink).opacity(palette.inkFaintOpacity) }
    var accent: Color { Color(hex: t.accent) }
    var accent2: Color { Color(hex: t.accent2) }
    var onAccent: Color { Color(hex: t.onAccent) }
}

/// Fonts: the in-app Rest/Active screens render with system fonts (condensed-bold
/// numerals, monospaced labels); the Live Activity mirrors them. Custom-font
/// bundling into the widget extension is out of scope for v1.
extension Font {
    static func laNumeral(_ size: CGFloat) -> Font { .system(size: size, weight: .bold).width(.condensed) }
    static func laLabel(_ size: CGFloat) -> Font { .system(size: size, design: .monospaced) }
    static func laName(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
}

/// Self-ticking mm:ss countdown to `end`. Renders "0:00" once elapsed —
/// `Text(timerInterval:)` traps on an inverted range, and `end` can be in the
/// past (clock skew, or rest elapsing before the next state push arrives).
struct CountdownText: View {
    let end: Date
    let font: Font

    var body: some View {
        let now = Date()
        if end > now {
            Text(timerInterval: now...end, countsDown: true)
                .font(font).monospacedDigit()
        } else {
            Text("0:00").font(font).monospacedDigit()
        }
    }
}

/// mm:ss rest countdown numeral + accent2 ring over an inkFaint track.
struct RestRingView: View {
    let state: WorkoutActivityAttributes.ContentState
    let theme: WidgetTheme

    var body: some View {
        ZStack {
            Circle().stroke(theme.inkFaint, lineWidth: 6)
            Circle()
                .trim(from: 0, to: state.restFraction())
                .stroke(theme.accent2, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let end = state.restEndsAt {
                CountdownText(end: end, font: .laNumeral(26))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: 64, height: 64)
    }
}

/// Active-phase set lockup: type pill + SET n/N + target reps numeral + weight.
struct SetLockupView: View {
    let state: WorkoutActivityAttributes.ContentState
    let theme: WidgetTheme

    private var isFailure: Bool { state.targetReps == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            setTypePill
            Text("SET \(state.setIndex)/\(state.totalSets)")
                .font(.laLabel(11))
                .foregroundStyle(theme.inkSoft)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isFailure ? "∞" : "\(state.targetReps ?? 0)")
                    .font(.laNumeral(30))
                    .foregroundStyle(theme.ink)
                if !isFailure, let w = state.targetWeight, w > 0 {
                    Text("\(Int(w)) KG")
                        .font(.laLabel(11))
                        .foregroundStyle(theme.inkSoft)
                } else if isFailure {
                    Text("TO FAILURE")
                        .font(.laLabel(11))
                        .foregroundStyle(theme.inkSoft)
                }
            }
        }
    }

    @ViewBuilder private var setTypePill: some View {
        let label = state.setTypeLabel
        let filled = (label == "WORKING")
        Text(label)
            .font(.laLabel(10))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(theme.onAccent)
            .background(Capsule().fill(filled ? theme.accent : .clear))
            .overlay(Capsule().stroke(filled ? .clear : theme.inkFaint, lineWidth: 1))
    }
}

/// UP NEXT preview (rest phase) — next exercise + reps/weight (or ∞), superset ssLabel.
struct UpNextView: View {
    let state: WorkoutActivityAttributes.ContentState
    let theme: WidgetTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(state.isMidPair ? "NEXT IN PAIR" : "UP NEXT")
                    .font(.laLabel(10))
                    .foregroundStyle(theme.inkSoft)
                if let ss = state.nextSsLabel {
                    Text("· \(ss)")
                        .font(.laLabel(10))
                        .foregroundStyle(theme.accent)
                }
            }
            if let name = state.nextExerciseName {
                Text(name)
                    .font(.laName(14))
                    .foregroundStyle(theme.ink)
            }
            Text(nextDetail)
                .font(.laLabel(11))
                .foregroundStyle(theme.inkSoft)
        }
    }

    private var nextDetail: String {
        let reps = state.nextReps.map(String.init) ?? "∞"
        if let w = state.nextWeight, w > 0 { return "\(reps) × \(Int(w)) KG" }
        return reps
    }
}
