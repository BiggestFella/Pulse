import SwiftUI

struct ActiveSetView: View {
    let model: ActiveWorkoutModel
    @Environment(Theme.self) private var theme

    @State private var reps: Int = 0
    @State private var weight: Double = 0

    private var step: WorkoutStep { model.currentStep }
    private var exIdx: Int { step.exIdx }
    private var exercise: WorkoutExercise { model.workout.exercises[exIdx] }
    private var setSpec: SetSpec { exercise.sets[step.setIdx] }
    private var isFailure: Bool { setSpec.type == .failure }
    private var failureBottom: String { weight > 0 ? "Max reps @ \(WeightFormat.kg(weight))." : "Max reps." }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            topBar
            progressSegments
            exerciseHeader
            actionChips
            heroCard
            // BAK-30: failure/AMRAP sets also show the entry controls so you can
            // record the weight you used and the reps you actually hit.
            steppers
            if exercise.supersetGroup != nil { partnerPeek }
            Spacer()
            footer
        }
        .padding(theme.spacing[5])
        .onChange(of: model.stepIdx, initial: true) { _, _ in
            reps = model.seedReps
            weight = model.seedWeight
        }
    }

    private var topBar: some View {
        HStack {
            Button { model.endWorkout() } label: { Image(systemName: "chevron.left").foregroundStyle(theme.ink) }
                .accessibilityIdentifier("active.back")
            Spacer()
            Text("EX \(exIdx + 1) / \(model.workout.exercises.count)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.inkSoft)
            Spacer()
            Image(systemName: "ellipsis").foregroundStyle(theme.inkSoft)   // inert per product decisions
        }
    }

    private var progressSegments: some View {
        HStack(spacing: 4) {
            ForEach(exercise.sets.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 6)
                    .fill(i < step.setIdx ? theme.accent
                          : i == step.setIdx ? theme.accent2 : theme.inkFaint)
                    .frame(height: 6)
            }
        }
        .accessibilityIdentifier("active.progress")
    }

    private var exerciseHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrowText)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.inkSoft)
                    .accessibilityIdentifier("active.eyebrow")
                Text(model.displayName(forExercise: exIdx) + ".")
                    .font(.title2.bold())
                    .foregroundStyle(theme.ink)
            }
            Spacer()
            if !model.isSwapped(exIdx), let v = exercise.exercise.variations.first {
                Button { model.activeSheet = .swap } label: {
                    Text("\(v.name) ⇆").font(.system(.caption2, design: .monospaced)).foregroundStyle(theme.ink)
                }
                .accessibilityIdentifier("active.variationChip")
            }
        }
    }

    private var eyebrowText: String {
        var s = exercise.exercise.muscleGroup.uppercased()
        if let label = step.ssLabel(in: model.workout) { s += " · \(label)" }
        if model.isSwapped(exIdx) { s += " · SWAPPED" }
        return s
    }

    private var actionChips: some View {
        HStack(spacing: 6) {
            chip("⇆ Swap", .swap, id: "active.chip.swap")
            chip("↻ History", .history, id: "active.chip.history")
            chip("☰ Jump", .jump, id: "active.chip.jump")
        }
    }
    private func chip(_ label: String, _ sheet: ActiveWorkoutModel.ActiveSheet, id: String) -> some View {
        Button(label) { model.activeSheet = sheet }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(theme.ink)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .overlay(Capsule().strokeBorder(theme.inkFaint, lineWidth: 1))
            .accessibilityIdentifier(id)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            HStack(alignment: .top) {
                SetTypePill(label: model.setTypeLabel(setSpec.type), isWorking: setSpec.type == .working)
                Spacer()
                Text("SET \(step.setIdx + 1) / \(exercise.sets.count)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.onAccent.opacity(0.85))
            }
            Lockup(value: isFailure ? "" : "\(reps)",
                   top: isFailure ? "To failure" : "Set \(step.setIdx + 1)",
                   bottom: isFailure ? failureBottom : "Reps @ \(WeightFormat.kg(weight)).",
                   failure: isFailure)

            HStack {
                Text(isFailure && weight == 0 ? "BODYWEIGHT" : WeightFormat.eyebrow(weight: weight, reps: reps))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.onAccent.opacity(0.85))
                    .accessibilityIdentifier("active.hero.footer")
                Spacer()
                repSchedule
            }
        }
        .padding(.init(top: 16, leading: 18, bottom: 20, trailing: 18))
        .background(theme.accent, in: RoundedRectangle(cornerRadius: 20))
    }

    private var repSchedule: some View {
        let working = exercise.sets.enumerated().filter { $0.element.type != .warmup }
        return HStack(spacing: 0) {
            ForEach(Array(working.enumerated()), id: \.offset) { k, pair in
                let (i, spec) = pair
                Text("\(spec.reps)")
                    .underline(i == step.setIdx, color: theme.accent2)
                    .foregroundStyle(theme.onAccent)
                if k < working.count - 1 {
                    Text(" → ").foregroundStyle(theme.onAccent.opacity(0.5))
                }
            }
        }
        .font(.system(.caption2, design: .monospaced)).fontWeight(.semibold)
        .accessibilityIdentifier("active.repSchedule")
    }

    private var steppers: some View {
        HStack(spacing: 8) {
            StepperField(label: "WEIGHT", value: WeightFormat.kg(weight),
                         allowsDecimal: true, idBase: "active.stepper.weight",
                         onDec: { weight = max(0, weight - 2.5) }, onInc: { weight += 2.5 },
                         onManualSet: { weight = max(0, $0) })
            StepperField(label: "REPS", value: "\(reps)", accent: true,
                         allowsDecimal: false, idBase: "active.stepper.reps",
                         onDec: { reps = max(0, reps - 1) }, onInc: { reps += 1 },
                         onManualSet: { reps = max(0, Int($0.rounded())) })
        }
    }

    private var partnerPeek: some View {
        Group {
            if let partnerIdx = step.supersetPartnerExIdx {
                let partner = model.workout.exercises[partnerIdx]
                let pSet = partner.sets.indices.contains(step.setIdx) ? partner.sets[step.setIdx] : partner.sets.first
                let goesToPartner = !step.rest
                HStack(spacing: 10) {
                    Text(WorkoutStep(exIdx: partnerIdx, setIdx: step.setIdx, rest: false,
                                     supersetPartnerExIdx: exIdx).ssLabel(in: model.workout) ?? "")
                        .font(.title2.bold()).foregroundStyle(theme.accent2)
                    VStack(alignment: .leading) {
                        Text(model.displayName(forExercise: partnerIdx))
                            .font(.subheadline.bold()).foregroundStyle(theme.ink)
                        Text("\(goesToPartner ? "NEXT IN PAIR" : "PAIRED") · \(pSet?.reps ?? 0) REPS")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.inkSoft)
                    }
                    Spacer()
                }
                .padding(theme.spacing[2])
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.accent2, lineWidth: 2))
                .opacity(0.85)
                .accessibilityIdentifier("active.partnerPeek")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Skip") { model.skipSet() }
                .buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
                .accessibilityIdentifier("active.skip")
            Button(model.logButtonLabel) { model.logSet(reps: reps, weight: weight) }
                .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("active.log")
        }
    }
}

/// Local stepper field (the design system has no shared stepper yet). Label +
/// `−` / value / `+`. The `−`/`+` buttons carry full 44pt hit targets (BAK-29:
/// the old image-sized targets felt slow/unresponsive), and the value is tappable
/// to type an exact figure (BAK-28) while the steppers stay for nudging.
private struct StepperField: View {
    @Environment(Theme.self) private var theme
    let label: String
    let value: String
    var accent: Bool = false
    let allowsDecimal: Bool
    let idBase: String
    let onDec: () -> Void
    let onInc: () -> Void
    let onManualSet: (Double) -> Void

    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var valueColor: Color { accent ? theme.accent2 : theme.ink }

    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.system(.caption2, design: .monospaced)).foregroundStyle(theme.inkSoft)
            HStack(spacing: 0) {
                stepButton("minus", id: "\(idBase).dec", action: onDec)
                Spacer(minLength: 0)
                valueSlot
                Spacer(minLength: 0)
                stepButton("plus", id: "\(idBase).inc", action: onInc)
            }
            .padding(.vertical, 2).padding(.horizontal, theme.spacing[2])
            .background(theme.surface, in: RoundedRectangle(cornerRadius: theme.radiusChip))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var valueSlot: some View {
        if editing {
            TextField(value, text: $draft)   // current value shown as a placeholder hint
                .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.center)
                .font(.title3.bold())
                .foregroundStyle(valueColor)
                .focused($focused)
                .frame(maxWidth: 110)
                .accessibilityIdentifier("\(idBase).field")
                .onSubmit(commit)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { commit() }.accessibilityIdentifier("\(idBase).done")
                    }
                }
        } else {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .padding(.vertical, 11).padding(.horizontal, 8)
                .contentShape(Rectangle())
                .onTapGesture { beginEdit() }
                .accessibilityIdentifier("\(idBase).value")
        }
    }

    private func stepButton(_ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(theme.ink)
                .frame(width: 44, height: 44)        // HIG-min hit target
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func beginEdit() {
        draft = ""          // start fresh; the current value remains as the placeholder
        editing = true
        focused = true
    }

    private func commit() {
        if let v = Double(draft.replacingOccurrences(of: ",", with: ".")) { onManualSet(v) }
        editing = false
        focused = false
    }
}

#Preview {
    let m = ActiveWorkoutModel(exerciseRepo: MockSwapAlternativesRepository(),
                               historyRepo: MockHistoryRepository(),
                               sessionWriter: MockSessionWriter())
    m.startWorkout(ActiveWorkoutSample.workout); m.beginSets()
    return ActiveSetView(model: m).environment(Theme())
}
