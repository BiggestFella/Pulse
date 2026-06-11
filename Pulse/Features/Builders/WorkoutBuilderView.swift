import SwiftUI

/// Identifiable wrapper so `.sheet(item:)` can drive the Set Editor by id.
private struct EditingItem: Identifiable { let id: BuilderExercise.ID }

struct WorkoutBuilderView: View {
    @State private var model: WorkoutBuilderModel
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric private var reorderRowHeight: CGFloat = 48

    init(model: WorkoutBuilderModel) { _model = State(initialValue: model) }

    var body: some View {
        BuilderScaffold(
            eyebrow: "NEW WORKOUT", primaryLabel: "Save workout →",
            saving: model.saveState == .saving,
            onCancel: { dismiss() },
            onPrimary: { Task { await model.save() } }
        ) {
            VStack(alignment: .leading, spacing: theme.spacing[4]) {
                TextField("Workout name", text: $model.name)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("workout-name")

                tagRow

                HStack {
                    StatLabel("EXERCISES · \(model.items.count)")
                        .accessibilityIdentifier("eyebrow-EXERCISES · \(model.items.count)")
                    Spacer()
                    if model.items.count > 1 {
                        Button { model.isReordering.toggle() } label: {
                            Text(model.isReordering ? "DONE" : "REORDER")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(theme.accent)
                        }
                        .accessibilityIdentifier("reorder-toggle")
                    }
                    StatLabel("\(model.totalSets) SETS")
                        .accessibilityIdentifier("eyebrow-\(model.totalSets) SETS")
                }

                if model.isReordering { reorderList } else { exerciseList }

                Button { model.pickerPresented = true } label: {
                    Text("+ ADD EXERCISE")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity).padding(theme.spacing[4])
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6])))
                }
                .accessibilityIdentifier("add-exercise")

                Text("Tap ⛓ on an exercise to superset it with the one below.")
                    .font(.system(size: 12)).foregroundStyle(theme.inkSoft)

                if case let .error(msg) = model.saveState {
                    Text(msg).foregroundStyle(theme.accent2).accessibilityIdentifier("save-error")
                }
            }
            .padding(.vertical, theme.spacing[3])
        }
        .sheet(item: Binding(get: { model.editingItemID.map { EditingItem(id: $0) } },
                             set: { model.editingItemID = $0?.id })) { box in
            SetEditorSheet(model: model, itemID: box.id)
                .environment(theme)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $model.pickerPresented) {
            ExercisePickerSheet(
                catalog: model.catalog, loading: model.catalogLoading, errorText: model.catalogError,
                alreadyAdded: model.addedExerciseIDs,
                onRetry: { Task { await model.loadCatalog() } },
                onCancel: { model.pickerPresented = false },
                onConfirm: { ids in model.addExercises(ids); model.isReordering = false; model.pickerPresented = false })
            .environment(theme)
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .task { if model.catalog.isEmpty { await model.loadCatalog() } }
        }
        .onChange(of: model.saveState) { _, new in if new == .saved { dismiss() } }
    }

    private var tagRow: some View {
        HStack(spacing: theme.spacing[1]) {
            ForEach(WorkoutTag.allCases, id: \.self) { tag in
                PillChip(label: tag.label, selected: model.tag == tag,
                         fill: theme.accent2, onFill: theme.onAccent) { model.tag = tag }
            }
            Text("+ TAG")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.inkFaint)
                .padding(.horizontal, theme.spacing[3]).padding(.vertical, theme.spacing[1])
                .overlay(Capsule().strokeBorder(theme.inkFaint, style: StrokeStyle(lineWidth: 2, dash: [4])))
                .accessibilityIdentifier("tag-add") // decorative per product decision
        }
    }

    // MARK: Exercise list — runs of linked rows render as one superset card.

    /// Flat, drag-to-reorder list shown only in edit mode. Uses a plain List so
    /// `.onMove` works; superset grouping is suspended here and recomputed from
    /// `items` when the user leaves edit mode.
    private var reorderList: some View {
        List {
            ForEach(model.items) { item in
                HStack(spacing: theme.spacing[2]) {
                    Image(systemName: "line.3.horizontal").foregroundStyle(theme.inkFaint)
                    Text(item.exercise.name)
                        .foregroundStyle(theme.ink)
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("reorder-row-\(item.exercise.name)")
            }
            .onMove { model.move(from: $0, to: $1) }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .frame(height: CGFloat(model.items.count) * reorderRowHeight)
        .environment(\.editMode, .constant(.active))
    }

    private var exerciseList: some View {
        VStack(spacing: theme.spacing[2]) {
            ForEach(supersetRuns, id: \.startIndex) { run in
                if run.isSuperset {
                    supersetCard(run)
                } else {
                    exerciseRow(idx: run.startIndex, item: model.items[run.startIndex])
                }
            }
        }
    }

    /// A maximal run of consecutive rows sharing one non-nil superset group, or a
    /// single ungrouped row.
    private struct Run {
        let startIndex: Int; let count: Int; let group: String?
        var isSuperset: Bool { group != nil && count >= 2 }
    }
    private var supersetRuns: [Run] {
        var runs: [Run] = []
        var i = 0
        let items = model.items
        while i < items.count {
            if let g = items[i].supersetGroup {
                var j = i
                while j < items.count, items[j].supersetGroup == g { j += 1 }
                runs.append(Run(startIndex: i, count: j - i, group: g))
                i = j
            } else {
                runs.append(Run(startIndex: i, count: 1, group: nil))
                i += 1
            }
        }
        return runs
    }

    private func supersetCard(_ run: Run) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            HStack {
                StatLabel("SUPERSET · \(run.count) MOVES", color: theme.accent2)
                Spacer()
                Button { model.toggleLink(at: run.startIndex) } label: {
                    Text("UNLINK")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(theme.accent2)
                }
                .accessibilityIdentifier("unlink-\(run.startIndex)")
            }
            ForEach(run.startIndex..<(run.startIndex + run.count), id: \.self) { idx in
                exerciseRow(idx: idx, item: model.items[idx])
            }
        }
        .padding(theme.spacing[3])
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.accent2, lineWidth: 2))
    }

    @ViewBuilder
    private func exerciseRow(idx: Int, item: BuilderExercise) -> some View {
        let inSuperset = item.supersetGroup != nil
        HStack(spacing: theme.spacing[2]) {
            Image(systemName: "line.3.horizontal").foregroundStyle(theme.inkFaint)
            BuilderBadge(text: badgeText(idx: idx, item: item), tinted: inSuperset)
            Button { model.editingItemID = item.id } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.exercise.name).foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                    Text(item.subLine).foregroundStyle(theme.inkSoft).font(.system(size: 13))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exercise-row-\(item.exercise.name)")
            Spacer()
            if idx < model.items.count - 1 {
                Button { model.toggleLink(at: idx) } label: { Image(systemName: "link") }
                    .foregroundStyle(inSuperset ? theme.accent2 : theme.inkSoft)
                    .accessibilityIdentifier("link-\(idx)")
            }
            Button { model.removeItem(id: item.id) } label: { Image(systemName: "xmark") }
                .foregroundStyle(theme.inkSoft)
                .accessibilityIdentifier("remove-\(item.exercise.name)")
        }
        .padding(.vertical, theme.spacing[1])
    }

    /// Index badge (1-based), or A/B/C/D position within its superset group.
    private func badgeText(idx: Int, item: BuilderExercise) -> String {
        guard let g = item.supersetGroup else { return "\(idx + 1)" }
        let members = model.items.filter { $0.supersetGroup == g }
        guard members.count >= 2, let pos = members.firstIndex(where: { $0.id == item.id }) else {
            return "\(idx + 1)"
        }
        return String(UnicodeScalar(65 + pos)!)
    }
}

#Preview {
    let theme = Theme()
    return NavigationStack {
        WorkoutBuilderView(model: WorkoutBuilderModel(
            catalog: InMemoryExerciseRepository(store: MockStore()),
            workouts: InMemoryWorkoutRepository(store: MockStore())))
    }
    .environment(theme)
}
