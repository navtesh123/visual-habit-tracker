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
    @State private var reminderTime: Date = {
        let comps = AppSettings.globalReminderTime
        return Calendar.current.date(
            bySettingHour: comps.hour ?? 9,
            minute: comps.minute ?? 0,
            second: 0,
            of: .now
        ) ?? .now
    }()
    @State private var reminderHabit: ReminderHabit = .custom

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
                    Toggle(cadence.reminderToggleLabel, isOn: $reminderEnabled)
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
                reminderHabit: reminderHabit
            )
            context.insert(project)
        case .edit(let existing):
            existing.name = trimmed
            existing.subjectType = subjectType
            existing.cadence = cadence
            existing.reminderTime = resolvedReminder
            existing.reminderHabit = reminderHabit
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
            onSave(project)
            dismiss()
        } catch {
            // Keep sheet open on save failure; production would surface an alert.
            assertionFailure("Failed to save project: \(error)")
        }
    }
}
