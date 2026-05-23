import SwiftUI
import SwiftData

/// Create or edit a project (PRD §3.2). Presented as a system sheet,
/// which adopts Liquid Glass automatically on iOS 26.
struct ProjectEditorView: View {
    enum Mode: Equatable {
        case create
        case edit(Project)
        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.create, .create): return true
            case (.edit(let a), .edit(let b)): return a.id == b.id
            default: return false
            }
        }
    }

    let mode: Mode
    /// Called with the resulting project on save.
    let onSave: (Project) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var subjectType: SubjectType = .object
    @State private var cadence: Cadence = .weekly
    @State private var reminderEnabled: Bool = false
    @State private var reminderTime: Date = Calendar.current.date(
        bySettingHour: 9, minute: 0, second: 0, of: .now
    ) ?? .now
    @State private var reminderHabit: ReminderHabit = .custom
    @State private var accent: AccentToken = .default

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Left bicep", text: $name)
                        .bodyStyle(17, weight: .medium)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Subject") {
                    Picker("Subject type", selection: $subjectType) {
                        ForEach(SubjectType.allCases) { type in
                            Label(type.displayName, systemImage: type.systemImage)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Cadence") {
                    Picker("Capture cadence", selection: $cadence) {
                        ForEach(Cadence.allCases) { c in
                            Text(c.displayName).tag(c)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Reminder") {
                    Toggle("Daily reminder", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker(
                            "Time",
                            selection: $reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                        Picker("Habit stack", selection: $reminderHabit) {
                            ForEach(ReminderHabit.allCases) { habit in
                                Text(habit.displayName).tag(habit)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section("Accent color") {
                    AccentSwatchPicker(selection: $accent)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
            .scrollContentBackground(.hidden)
            .background(NeonPlayroom.midnightAbyss.ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save", action: save)
                        .bold()
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: loadIfEditing)
        }
        .tint(NeonPlayroom.limeSqueeze)
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "New project"
        case .edit: return "Edit project"
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadIfEditing() {
        if case .edit(let project) = mode {
            name = project.name
            subjectType = project.subjectType
            cadence = project.cadence
            if let t = project.reminderTime {
                reminderEnabled = true
                reminderTime = t
            } else {
                reminderEnabled = false
            }
            reminderHabit = project.reminderHabit
            accent = project.accentColor
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedReminder: Date? = reminderEnabled ? reminderTime : nil

        let project: Project
        switch mode {
        case .create:
            project = Project(
                name: trimmed,
                subjectType: subjectType,
                cadence: cadence,
                reminderTime: resolvedReminder,
                reminderHabit: reminderHabit,
                accentColor: accent
            )
            context.insert(project)
        case .edit(let existing):
            existing.name = trimmed
            existing.subjectType = subjectType
            existing.cadence = cadence
            existing.reminderTime = resolvedReminder
            existing.reminderHabit = reminderHabit
            existing.accentColor = accent
            project = existing
        }

        do {
            try context.save()
            // M8 — sync the local notification: schedule when reminders are
            // on, clear when they're off. Authorization is prompted in-context.
            Task {
                if let time = resolvedReminder {
                    await ReminderScheduler.shared.scheduleReminder(for: project, at: time)
                } else {
                    await ReminderScheduler.shared.removeReminders(for: project)
                }
            }
            // M9 — keep the widget snapshot fresh with the latest pinned /
            // most-recent project.
            let all = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            WidgetSnapshotPublisher.publish(from: all)
            onSave(project)
            dismiss()
        } catch {
            // Keep sheet open on save failure; production would surface an alert.
            assertionFailure("Failed to save project: \(error)")
        }
    }
}

/// Horizontal row of Neon Playroom accent swatches (PRD §3.2, §7.3).
private struct AccentSwatchPicker: View {
    @Binding var selection: AccentToken

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AccentToken.allCases) { token in
                    Button {
                        selection = token
                        Haptics.tap(style: .light)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(token.color)
                                .frame(width: 36, height: 36)
                            if selection == token {
                                Circle()
                                    .strokeBorder(NeonPlayroom.ghostWhite, lineWidth: 3)
                                    .frame(width: 44, height: 44)
                            }
                        }
                        .padding(4)
                    }
                    .accessibilityLabel(token.displayName)
                    .accessibilityAddTraits(selection == token ? .isSelected : [])
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
