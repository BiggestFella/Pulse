import SwiftUI

/// Read-only 1RM calculator / what-if. Two steppers (weight 2.5 kg, reps 1),
/// a large est-1RM numeral, and a %-of-1RM working-weight table (90→70%,
/// rounded to 2.5 kg). Present inside the shared `pulseSheet` chrome. No
/// persistence; the model recomputes everything live as the steppers change.
struct OneRepMaxCalculatorSheet: View {
    @Environment(Theme.self) private var theme
    @State private var model: OneRepMaxCalculatorModel

    init(weight: Double = 60, reps: Int = 5) {
        _model = State(initialValue: OneRepMaxCalculatorModel(weight: weight, reps: reps))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            steppers
            estimateCard
            percentTable
        }
        .padding(.bottom, theme.spacing[5])
    }

    // MARK: - Steppers

    private var steppers: some View {
        HStack(spacing: theme.spacing[2]) {
            CalcStepperField(label: "WEIGHT",
                             value: WeightFormat.kg(model.weight),
                             idBase: "calc.stepper.weight",
                             onDec: model.decrementWeight,
                             onInc: model.incrementWeight)
            CalcStepperField(label: "REPS",
                             value: "\(model.reps)",
                             accent: true,
                             idBase: "calc.stepper.reps",
                             onDec: model.decrementReps,
                             onInc: model.incrementReps)
        }
    }

    // MARK: - Estimate hero card (accent-filled → onAccent for highlight text)

    private var estimateCard: some View {
        VStack(alignment: .leading, spacing: theme.spacing[0]) {
            Text("EST. 1RM · EPLEY")
                .pulseStyle(.eyebrow)
                .foregroundStyle(theme.onAccent.opacity(0.85))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(WeightFormat.kgNumeral(model.estimatedOneRepMax))
                    .font(PulseFont.hero(size: 64))
                    .foregroundStyle(theme.onAccent)
                    .accessibilityIdentifier("calc.est1rm")
                Text("kg")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(theme.onAccent.opacity(0.85))
            }
            Text("Estimated from \(WeightFormat.eyebrow(weight: model.weight, reps: model.reps)).")
                .pulseStyle(.rowSub)
                .foregroundStyle(theme.onAccent.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing[5])
        .background(theme.accent, in: RoundedRectangle(cornerRadius: theme.radiusCard))
        .accessibilityIdentifier("calc.estimateCard")
    }

    // MARK: - %-of-1RM table

    private var percentTable: some View {
        VStack(alignment: .leading, spacing: theme.spacing[1]) {
            Text("WORKING WEIGHTS · % OF 1RM")
                .pulseStyle(.eyebrow)
                .foregroundStyle(theme.inkSoft)
            ForEach(model.percentRows) { row in
                HStack {
                    Text("\(row.percent)%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.ink)
                    Spacer()
                    Text(WeightFormat.kg(row.weight))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.ink)
                }
                .padding(.vertical, theme.spacing[1])
                .padding(.horizontal, theme.spacing[3])
                .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusChip))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("calc.row.\(row.percent)")
            }
        }
        .accessibilityIdentifier("calc.percentTable")
    }
}

/// Local stepper (the design system has no shared stepper component yet; this
/// mirrors the active-flow `StepperField`). Label + `−` / value / `+`.
private struct CalcStepperField: View {
    @Environment(Theme.self) private var theme
    let label: String
    let value: String
    var accent: Bool = false
    let idBase: String
    let onDec: () -> Void
    let onInc: () -> Void

    var body: some View {
        VStack(spacing: theme.spacing[0]) {
            Text(label)
                .pulseStyle(.eyebrow)
                .foregroundStyle(theme.inkSoft)
            HStack {
                Button(action: onDec) { Image(systemName: "minus").foregroundStyle(theme.ink) }
                    .accessibilityIdentifier("\(idBase).dec")
                Spacer()
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(accent ? theme.accent2 : theme.ink)
                Spacer()
                Button(action: onInc) { Image(systemName: "plus").foregroundStyle(theme.ink) }
                    .accessibilityIdentifier("\(idBase).inc")
            }
            .padding(theme.spacing[2])
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusChip))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Calculator") {
    let theme = Theme()
    return Color.clear
        .pulseSheetPreviewHost()
        .environment(theme)
}

// Lightweight preview host so the sheet renders standalone in canvas.
private extension View {
    func pulseSheetPreviewHost() -> some View {
        OneRepMaxCalculatorSheet(weight: 80, reps: 5)
            .padding(.horizontal, 18)
    }
}
