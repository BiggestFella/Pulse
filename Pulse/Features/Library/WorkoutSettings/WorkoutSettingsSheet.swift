import SwiftUI

/// Per-workout Settings — Schedule, Targets, Rest, Notes, Folder, Delete in one sheet.
/// Opened from the editor `⋯` and the Workout-Detail gear. Each edit persists live.
struct WorkoutSettingsSheet: View {
    @State private var model: WorkoutSettingsModel
    let title: String
    let onDeleted: () -> Void
    @Environment(Theme.self) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showScheduleSheet = false
    @State private var schedulePicked = Date()
    @State private var confirmDelete = false

    init(model: WorkoutSettingsModel, title: String, onDeleted: @escaping () -> Void = {}) {
        _model = State(initialValue: model)
        self.title = title
        self.onDeleted = onDeleted
    }

    var body: some View {
        SheetChrome(eyebrow: "WORKOUT", title: "\(title).", onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: theme.spacing[4]) {
                scheduleSection
                targetsSection
                restSection
                notesSection
                folderSection
                deleteSection
            }
            .padding(.bottom, theme.spacing[6])
            .task { await model.load() }
            .onDisappear { Task { await model.setNotes(model.notes) } }   // commit typed notes on dismiss
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("REPEATS ON")
            let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(zip(1...7, dayLabels)), id: \.0) { day, label in
                        PillChip(label: label, selected: model.weekdays.contains(day),
                                 fill: theme.accent, onFill: theme.onAccent) {
                            Task { await model.toggleWeekday(day) }
                        }
                        .accessibilityIdentifier("settings.repeat-day-\(day)")
                    }
                }
            }
            Button { schedulePicked = Date(); showScheduleSheet = true } label: {
                Text("Schedule on a date")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("settings.scheduleDate")
            .sheet(isPresented: $showScheduleSheet) {
                NavigationStack {
                    DatePicker("Pick a date", selection: $schedulePicked, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .navigationTitle("Schedule Workout").navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showScheduleSheet = false } }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Add") { showScheduleSheet = false; Task { await model.scheduleOnDate(schedulePicked) } }.fontWeight(.semibold)
                            }
                        }
                }
                .presentationDetents([.medium, .large]).environment(theme)
            }
        }
    }

    private var targetsSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("TARGETS")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: theme.spacing[1]) {
                    ForEach(MuscleGroup.allCases) { m in
                        PillChip(label: m.rawValue, selected: model.targets.contains(m),
                                 fill: theme.accent, onFill: theme.onAccent) {
                            Task { await model.toggleTarget(m) }
                        }
                        .accessibilityIdentifier("settings.target-\(m.rawValue)")
                    }
                }
            }
        }
    }

    private var restSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("REST TIMER")
            HStack(spacing: theme.spacing[3]) {
                Button { Task { await model.setRestSeconds((model.restSeconds ?? 90) - 15) } } label: {
                    Image(systemName: "minus.circle").font(.system(size: 22)).foregroundStyle(theme.accent)
                }.buttonStyle(.plain).accessibilityIdentifier("settings.rest.stepper.dec")
                Text(model.restSeconds.map { "\($0)s" } ?? "Default")
                    .font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundStyle(theme.ink)
                    .frame(minWidth: 80)
                    .accessibilityIdentifier("settings.rest.value")
                Button { Task { await model.setRestSeconds((model.restSeconds ?? 90) + 15) } } label: {
                    Image(systemName: "plus.circle").font(.system(size: 22)).foregroundStyle(theme.accent)
                }.buttonStyle(.plain).accessibilityIdentifier("settings.rest.stepper.inc")
                Spacer()
                if model.restSeconds != nil {
                    Button { Task { await model.useDefaultRest() } } label: {
                        Text("USE DEFAULT").font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(theme.inkSoft)
                    }.buttonStyle(.plain).accessibilityIdentifier("settings.rest.useDefault")
                }
            }
            Text(model.restSeconds == nil ? "Uses your global default rest timer." : "Overrides the global default for this workout.")
                .font(.system(size: 12)).foregroundStyle(theme.inkSoft)
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("NOTES")
            TextField("Type anything…", text: Binding(get: { model.notes }, set: { model.notes = $0 }), axis: .vertical)
                .lineLimit(2...6)
                .font(.system(size: 15)).foregroundStyle(theme.ink)
                .padding(theme.spacing[3])
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.inkFaint, lineWidth: 1.5))
                .accessibilityIdentifier("settings.notes")
            Button { Task { await model.setNotes(model.notes) } } label: {
                Text("Save notes").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.accent)
            }.buttonStyle(.plain).accessibilityIdentifier("settings.notes.save")
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing[2]) {
            StatLabel("FOLDER")
            ForEach(model.folderOptions) { opt in
                Button { Task { await model.setFolder(opt.id) } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: opt.id == nil ? "tray.full" : "folder").foregroundStyle(theme.inkSoft)
                        Text(opt.name).foregroundStyle(theme.ink)
                        Spacer()
                        if model.folderID == opt.id { Image(systemName: "checkmark").foregroundStyle(theme.accent) }
                    }
                    .padding(.leading, CGFloat(opt.depth) * 16).padding(.vertical, 8).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.folder.\(opt.id?.uuidString ?? "root")")
            }
        }
    }

    private var deleteSection: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            HStack(spacing: 8) { Image(systemName: "trash"); Text("Delete workout").font(.system(size: 15, weight: .semibold)) }
                .foregroundStyle(theme.accent2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.delete")
        .alert("Delete this workout?", isPresented: $confirmDelete) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await model.delete(); dismiss(); onDeleted() } }
        } message: { Text("This can't be undone.") }
    }
}
