import SwiftUI

/// Guided multi-step create flow. Collects name/targets/schedule/folder, then
/// `Create` persists the draft and hands the new workout id to `onCreated` (the
/// caller routes to the editor). Reuses SP1 target chips, SP2 weekday chips, and
/// the shared FolderOptions tree.
struct CreateWizardView: View {
    @State private var model: CreateWizardModel
    private let onCreated: (Workout.ID) -> Void
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss

    init(model: CreateWizardModel, onCreated: @escaping (Workout.ID) -> Void = { _ in }) {
        _model = State(initialValue: model)
        self.onCreated = onCreated
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                stepBody
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.spacing[5])
                    .padding(.top, theme.spacing[4])
            }
            footer
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .task { await model.loadFolders() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("NEW WORKOUT · STEP \(model.stepNumber)/\(model.stepCount)")
                .accessibilityIdentifier("wizard.progress")
            HStack(spacing: 4) {
                ForEach(0..<model.stepCount, id: \.self) { i in
                    Capsule()
                        .fill(i < model.stepNumber ? theme.accent : theme.inkFaint)
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, theme.spacing[5]).padding(.top, theme.spacing[3])
    }

    @ViewBuilder private var stepBody: some View {
        switch model.step {
        case .name:     nameStep
        case .targets:  targetsStep
        case .schedule: scheduleStep
        case .folder:   folderStep
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("Name your workout")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(theme.ink)
            TextField("Workout name", text: $model.name)
                .font(.system(size: 28, weight: .bold)).foregroundStyle(theme.ink)
                .accessibilityIdentifier("wizard.name")
        }
    }

    private var targetsStep: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("What does it target?")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(theme.ink)
            Text("Optional — the muscle groups this workout hits.")
                .font(.system(size: 14)).foregroundStyle(theme.inkSoft)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing[1]) {
                    ForEach(MuscleGroup.allCases) { m in
                        PillChip(label: m.rawValue, selected: model.targets.contains(m),
                                 fill: theme.accent, onFill: theme.onAccent) { model.toggleTarget(m) }
                            .accessibilityIdentifier("wizard.target-\(m.rawValue)")
                    }
                }
            }
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("When do you train it?")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(theme.ink)
            Text("Optional — pick recurring weekdays. You can also schedule specific dates later.")
                .font(.system(size: 14)).foregroundStyle(theme.inkSoft)
            let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(zip(1...7, dayLabels)), id: \.0) { day, label in
                        PillChip(label: label, selected: model.weekdays.contains(day),
                                 fill: theme.accent, onFill: theme.onAccent) { model.toggleWeekday(day) }
                            .accessibilityIdentifier("wizard.repeat-day-\(day)")
                    }
                }
            }
        }
    }

    private var folderStep: some View {
        VStack(alignment: .leading, spacing: theme.spacing[3]) {
            Text("Where should it live?")
                .font(.system(size: 24, weight: .heavy)).foregroundStyle(theme.ink)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.folderOptions) { opt in
                    Button { model.folderID = opt.id } label: {
                        HStack(spacing: 8) {
                            Image(systemName: opt.id == nil ? "tray.full" : "folder")
                                .foregroundStyle(theme.inkSoft)
                            Text(opt.name).foregroundStyle(theme.ink)
                            Spacer()
                            if model.folderID == opt.id {
                                Image(systemName: "checkmark").foregroundStyle(theme.accent)
                            }
                        }
                        .padding(.leading, CGFloat(opt.depth) * 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("wizard.folder.\(opt.id?.uuidString ?? "root")")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: theme.spacing[2]) {
            Button(model.isFirstStep ? "Cancel" : "Back") {
                if model.isFirstStep { dismiss() } else { model.back() }
            }
            .buttonStyle(PressableButtonStyle(variant: .secondary, size: .md))
            .accessibilityIdentifier("wizard.back")

            Button {
                if model.isLastStep {
                    Task { if let id = await model.create() { onCreated(id) } }
                } else {
                    model.next()
                }
            } label: {
                Text(model.isLastStep ? "Create workout →" : "Continue")
            }
            .buttonStyle(PressableButtonStyle(variant: .primary, size: .md))
            .disabled(!model.canAdvance || model.creating)
            .accessibilityIdentifier("wizard.continue")
        }
        .padding(theme.spacing[5])
    }
}

#Preview {
    let store = MockStore(seeded: true)
    return NavigationStack {
        CreateWizardView(model: CreateWizardModel(
            workouts: InMemoryWorkoutRepository(store: store),
            folders: InMemoryFolderRepository(store: store)))
    }
    .environment(Theme())
}
