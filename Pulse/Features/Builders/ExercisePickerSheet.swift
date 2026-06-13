import SwiftUI

struct ExercisePickerSheet: View {
    enum PickMode { case add, replace }

    let catalog: [BuilderCatalogGroup]
    let loading: Bool
    let errorText: String?
    let alreadyAdded: Set<Exercise.ID>
    var initialMuscles: [String] = []
    var mode: PickMode = .add
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onConfirm: ([PickedExercise]) -> Void

    @State private var selected: [Exercise.ID] = []                 // ordered by tap
    @State private var chosenVariation: [Exercise.ID: Variation.ID] = [:]
    @State private var active: Set<String> = []                     // active muscle filters; empty = All
    @State private var search: String = ""
    @State private var didSeed = false
    @Environment(Theme.self) private var theme

    private var catalogMuscles: [String] { catalog.map { $0.muscle } }
    private var pickerMode: ExercisePickerLogic.Mode {
        ExercisePickerLogic.mode(activeMuscles: active, search: search)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
            if mode == .add { footer }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet, topTrailingRadius: theme.radiusSheet)
                .stroke(theme.ink, lineWidth: 2).ignoresSafeArea(edges: .bottom)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet, topTrailingRadius: theme.radiusSheet))
        .onAppear {
            guard !didSeed else { return }
            active = Set(initialMuscles)
            didSeed = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Capsule().fill(theme.inkFaint).frame(width: 42, height: 4)
                .frame(maxWidth: .infinity).padding(.top, 12)
            StatLabel(mode == .replace ? "REPLACE EXERCISE" : "ADD EXERCISE")
                .accessibilityIdentifier("eyebrow-ADD EXERCISE")
            Text(mode == .replace ? "Pick a replacement." : "Pick exercises.")
                .pulseStyle(.h1).foregroundStyle(theme.ink)

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.inkFaint)
                TextField("Search", text: $search)
                    .foregroundStyle(theme.ink)
                    .accessibilityIdentifier("exercise-search")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .foregroundStyle(theme.inkFaint)
                }
            }
            .padding(theme.spacing[3])
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.inkFaint, lineWidth: 2))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing[1]) {
                    PillChip(label: "All", selected: active.isEmpty,
                             fill: theme.accent, onFill: theme.onAccent) { active.removeAll() }
                        .accessibilityIdentifier("picker-filter-All")
                    ForEach(catalogMuscles, id: \.self) { m in
                        PillChip(label: m, selected: active.contains(m),
                                 fill: theme.accent, onFill: theme.onAccent) { toggleMuscle(m) }
                            .accessibilityIdentifier("picker-filter-\(m)")
                    }
                }
            }
        }
        .padding(.horizontal, theme.spacing[5]).padding(.bottom, theme.spacing[3])
    }

    @ViewBuilder private var content: some View {
        if loading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                .accessibilityIdentifier("picker-loading")
        } else if let errorText {
            VStack(spacing: theme.spacing[3]) {
                Text(errorText).foregroundStyle(theme.inkSoft)
                Button("Retry", action: onRetry).accessibilityIdentifier("picker-retry")
            }.frame(maxWidth: .infinity, minHeight: 120)
        } else if pickerMode == .sectioned {
            sectionedList
        } else {
            alphabeticalList
        }
    }

    private var sectionedList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing[3]) {
                ForEach(ExercisePickerLogic.sectioned(catalog, activeMuscles: active)) { group in
                    StatLabel(group.muscle)
                    ForEach(group.exercises) { ex in row(ex) }
                }
            }
            .padding(.horizontal, theme.spacing[5]).padding(.bottom, theme.spacing[3])
        }
        .scrollIndicators(.hidden)
    }

    private var alphabeticalList: some View {
        let list = ExercisePickerLogic.alphabetical(catalog, activeMuscles: active, search: search)
        let letters = ExercisePickerLogic.letterIndex(list)
        return ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: theme.spacing[2]) {
                        ForEach(list) { ex in row(ex).id(ex.id) }
                    }
                    .padding(.horizontal, theme.spacing[5]).padding(.bottom, theme.spacing[3])
                }
                .scrollIndicators(.hidden)
                scrubber(letters: letters, list: list, proxy: proxy)
            }
        }
    }

    private func scrubber(letters: [String], list: [Exercise], proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 1) {
            ForEach(letters, id: \.self) { l in
                Button {
                    if let target = list.first(where: { String($0.name.prefix(1)).uppercased() == l })?.id {
                        withAnimation { proxy.scrollTo(target, anchor: .top) }
                    }
                } label: {
                    Text(l).font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.inkSoft)
                }
                .accessibilityIdentifier("scrubber-\(l)")
            }
        }
        .padding(.trailing, 4)
    }

    private var footer: some View {
        HStack(spacing: theme.spacing[2]) {
            Button("Cancel", action: onCancel)
                .buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
                .accessibilityIdentifier("picker-cancel")
            Button { onConfirm(picks()) } label: {
                Text(selected.isEmpty ? "Select exercises" : "Add \(selected.count) selected")
            }
            .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
            .disabled(selected.isEmpty)
            .accessibilityIdentifier("picker-confirm")
        }
        .padding(theme.spacing[5])
    }

    private func picks() -> [PickedExercise] {
        selected.map { PickedExercise(id: $0, variationID: chosenVariation[$0]) }
    }

    @ViewBuilder private func row(_ ex: Exercise) -> some View {
        let added = alreadyAdded.contains(ex.id)
        let isSel = selected.contains(ex.id)
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            Button {
                guard !added else { return }
                if mode == .replace {
                    onConfirm([PickedExercise(id: ex.id, variationID: ex.defaultVariationID)]); return
                }
                if let i = selected.firstIndex(of: ex.id) { selected.remove(at: i); chosenVariation[ex.id] = nil }
                else { selected.append(ex.id); chosenVariation[ex.id] = ex.defaultVariationID }
            } label: {
                HStack {
                    Text(ex.name).foregroundStyle(theme.ink).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Image(systemName: (added || isSel) ? "checkmark" : "plus")
                        .foregroundStyle(added ? theme.inkSoft : theme.accent)
                }
                .padding(theme.spacing[3])
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(isSel ? theme.accent : theme.inkFaint, lineWidth: isSel ? 2 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(added).opacity(added ? 0.4 : 1)
            .accessibilityIdentifier("picker-row-\(ex.name)")

            if mode == .add, isSel, ex.variations.count > 1 {
                variationPicker(ex)
            }
        }
    }

    private func variationPicker(_ ex: Exercise) -> some View {
        let current = ex.variations.first { $0.id == chosenVariation[ex.id] }
        return Menu {
            ForEach(ex.variations) { v in
                Button {
                    chosenVariation[ex.id] = v.id
                } label: {
                    if v.id == chosenVariation[ex.id] { Label(v.name, systemImage: "checkmark") }
                    else { Text(v.name) }
                }
            }
        } label: {
            HStack(spacing: theme.spacing[2]) {
                StatLabel("VARIATION")
                Text(current?.name ?? "Default").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.ink)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.inkSoft)
            }
            .padding(.horizontal, theme.spacing[3])
        }
        .accessibilityIdentifier("picker-variation-\(ex.name)")
    }

    private func toggleMuscle(_ m: String) {
        if active.contains(m) { active.remove(m) } else { active.insert(m) }
    }
}

#Preview {
    let theme = Theme()
    let groups = WorkoutBuilderModel.group(SampleData.exercises)
    return ExercisePickerSheet(catalog: groups, loading: false, errorText: nil,
                               alreadyAdded: [], onRetry: {}, onCancel: {}, onConfirm: { _ in })
        .environment(theme)
}
