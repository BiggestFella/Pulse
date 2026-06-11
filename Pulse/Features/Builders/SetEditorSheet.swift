import SwiftUI

/// Per-set reps / RIR / type editor for one builder exercise. Binds to the
/// `WorkoutBuilderModel` and mutates the item in place via the model's intents.
/// kg-only v1: no weight field (weight is captured live during a session).
struct SetEditorSheet: View {
    @Bindable var model: WorkoutBuilderModel
    let itemID: BuilderExercise.ID
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    // Per-row focus identity (the set index currently being typed into), so only
    // the focused row shows its draft — a shared Bool would leak the draft to every row.
    @FocusState private var focusedReps: Int?
    @State private var repsDraft = ""
    // Shared column widths so the header labels line up with the data row.
    private let setColWidth: CGFloat = 28
    private let repsColWidth: CGFloat = 132   // stepper(−) + value + stepper(+)
    private let rirColWidth: CGFloat = 96

    private var item: BuilderExercise? { model.items.first { $0.id == itemID } }

    private let types: [SetType] = [.working, .warmup, .dropset, .failure, .amrap]
    private func typeLabel(_ t: SetType) -> String {
        switch t {
        case .working: return "Working"
        case .warmup:  return "Warm-up"
        case .dropset: return "Drop set"
        case .failure: return "To failure"
        case .amrap:   return "AMRAP"
        }
    }

    var body: some View {
        if let item {
            SheetChrome(
                eyebrow: "\(item.exercise.muscleGroup.uppercased()) · \(item.sets.count) SETS",
                title: "\(item.exercise.name).",
                onClose: { dismiss() }
            ) {
                content(item)
            }
        } else {
            EmptyView()
        }
    }

    private func content(_ item: BuilderExercise) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            HStack(spacing: theme.spacing[3]) {
                StatLabel("SET").frame(width: setColWidth, alignment: .leading)
                StatLabel("REPS").frame(width: repsColWidth, alignment: .center)
                StatLabel("RIR").frame(width: rirColWidth, alignment: .center)
                Spacer()
            }

            ForEach(Array(item.sets.enumerated()), id: \.element.id) { idx, set in
                setRow(item: item, idx: idx, set: set)
            }

            Button {
                model.addSet(itemID: item.id)
            } label: {
                Text("+ Add set")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(theme.spacing[3])
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [5])))
            }
            .accessibilityIdentifier("set-editor-add")

            Button { dismiss() } label: { Text("Done") }
                .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("set-editor-done")
        }
        .padding(.bottom, theme.spacing[6])
    }

    @ViewBuilder
    private func setRow(item: BuilderExercise, idx: Int, set: SetSpec) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            HStack(spacing: theme.spacing[3]) {
                BuilderBadge(text: "\(idx + 1)", tinted: set.type != .working)
                    .frame(width: setColWidth, alignment: .leading)

                HStack(spacing: theme.spacing[1]) {
                    Button("−") {
                        let next = max(0, set.reps - 1)
                        model.updateSet(itemID: item.id, index: idx, reps: next, rir: set.rir, type: set.type)
                        if focusedReps == idx { repsDraft = String(next) }
                    }
                    .accessibilityIdentifier("set-reps-dec-\(idx)")

                    TextField("0", text: Binding(
                        get: { focusedReps == idx ? repsDraft : String(set.reps) },
                        set: { newValue in
                            let digits = String(newValue.filter(\.isNumber).prefix(3))
                            repsDraft = digits
                            model.updateSet(itemID: item.id, index: idx,
                                            reps: digits.isEmpty ? 0 : (Int(digits) ?? set.reps),
                                            rir: set.rir, type: set.type)
                        }))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .focused($focusedReps, equals: idx)
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(theme.ink)
                        .frame(width: 56)
                        .accessibilityIdentifier("set-reps-\(idx)")
                        .onChange(of: focusedReps) { _, new in
                            if new == idx { repsDraft = String(set.reps) }   // seed on focus-in; commit happens live in `set`
                        }

                    Button("+") {
                        let next = set.reps + 1
                        model.updateSet(itemID: item.id, index: idx, reps: next, rir: set.rir, type: set.type)
                        if focusedReps == idx { repsDraft = String(next) }
                    }
                    .accessibilityIdentifier("set-reps-inc-\(idx)")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.ink)
                .frame(width: repsColWidth)

                HStack(spacing: theme.spacing[1]) {
                    Button("−") {
                        model.updateSet(itemID: item.id, index: idx, reps: set.reps, rir: set.rir - 1, type: set.type)
                    }
                    .accessibilityIdentifier("set-rir-dec-\(idx)")
                    Text("\(set.rir)").foregroundStyle(theme.accent)
                        .accessibilityIdentifier("set-rir-\(idx)")
                    Button("+") {
                        model.updateSet(itemID: item.id, index: idx, reps: set.reps, rir: set.rir + 1, type: set.type)
                    }
                    .accessibilityIdentifier("set-rir-inc-\(idx)")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.ink)
                .frame(width: rirColWidth)

                Spacer()

                Button {
                    model.removeSet(itemID: item.id, index: idx)
                } label: { Image(systemName: "xmark") }
                    .disabled(item.sets.count <= 1)
                    .opacity(item.sets.count <= 1 ? 0.3 : 1)
                    .foregroundStyle(theme.inkSoft)
                    .accessibilityIdentifier("set-remove-\(idx)")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing[1]) {
                    ForEach(types, id: \.self) { t in
                        PillChip(label: typeLabel(t), selected: set.type == t,
                                 fill: theme.accent, onFill: theme.onAccent) {
                            model.updateSet(itemID: item.id, index: idx, reps: set.reps, rir: set.rir, type: t)
                        }
                    }
                }
            }
        }
        .padding(.vertical, theme.spacing[1])
    }
}

#Preview {
    let theme = Theme()
    let model = WorkoutBuilderModel(
        catalog: InMemoryExerciseRepository(store: MockStore()),
        workouts: InMemoryWorkoutRepository(store: MockStore()))
    return SetEditorSheet(model: model, itemID: model.items[0].id)
        .environment(theme)
}
