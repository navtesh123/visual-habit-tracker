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
    var suggestedName: String? = nil
    var submitLabel: String = "Save"
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
    @State private var errorMessage: String?

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
                    Button(submitLabel, action: save)
                        .bold()
                        .disabled(!isValid)
                }
            }
            .onAppear(perform: loadIfEditing)
            .alert("Bloom could not save this project", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
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
        } else if name.isEmpty, let suggestedName {
            name = suggestedName
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedReminder: Date? = reminderEnabled ? reminderTime : nil

        do {
            let repository = ProjectRepository(context: context)
            let project: Project
            switch mode {
            case .create:
                project = try repository.createProject(
                    name: trimmed,
                    subjectType: subjectType,
                    cadence: cadence,
                    reminderTime: resolvedReminder,
                    reminderHabit: reminderHabit
                )
            case .edit(let existing):
                try repository.updateProject(
                    existing,
                    name: trimmed,
                    subjectType: subjectType,
                    cadence: cadence,
                    reminderTime: resolvedReminder,
                    reminderHabit: reminderHabit
                )
                project = existing
            }
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
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented { errorMessage = nil }
            }
        )
    }
}
