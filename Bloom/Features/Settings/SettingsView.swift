// PRD §3.8 — Settings. Five sections (Backup, Privacy, Reminders, Export,
// About) that together expose every milestone toggle in one calm surface.
//
// Layering rule (PRD §7.1): the screen lives inside a system Form, which
// adopts iOS 26 Liquid Glass automatically. Content within rows stays in
// the Neon Playroom palette.

import SwiftUI
import SwiftData
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    @Bindable private var backup = CloudKitBackupController.shared
    @Bindable private var reminders = ReminderScheduler.shared
    @State private var exportCoordinator = ExportCoordinator()

    @State private var backupEnabled: Bool = AppSettings.cloudKitBackupEnabled
    @State private var globalReminderTime: Date = SettingsView.componentsToDate(AppSettings.globalReminderTime)

    var body: some View {
        NavigationStack {
            Form {
                backupSection
                remindersSection
                exportSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(NeonPlayroom.midnightAbyss.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .bold()
                }
            }
            .sheet(item: $exportCoordinator.pendingShare) { artifact in
                ExportShareSheet(url: artifact.url)
                    .presentationDetents([.medium, .large])
            }
            .task {
                await reminders.refreshAuthorizationState()
                backup.refresh()
            }
        }
        .tint(NeonPlayroom.limeSqueeze)
    }

    // MARK: - Backup

    private var backupSection: some View {
        Section {
            Toggle("Back up to iCloud", isOn: $backupEnabled)
                .onChange(of: backupEnabled) { _, isOn in
                    Task {
                        if isOn {
                            await backup.enable()
                        } else {
                            backup.disable()
                        }
                    }
                }

            statusRow(
                icon: iconForBackup,
                title: backup.status.headline,
                subtitle: backup.status.subtitle
            )

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Manage iCloud Storage…", systemImage: "externaldrive.connected.to.line.below")
            }
        } header: {
            Text("Backup")
        } footer: {
            Text("iCloud backup is optional. Your photos stay on this device either way — and you can always export them yourself from below.")
                .bodyStyle(12)
        }
    }

    private var iconForBackup: String {
        switch backup.status {
        case .active, .syncing: return "checkmark.icloud"
        case .paused: return "exclamationmark.icloud"
        case .error: return "exclamationmark.icloud"
        case .disabled: return "icloud.slash"
        }
    }

    // MARK: - Reminders

    private var remindersSection: some View {
        Section {
            DatePicker(
                "Default reminder time",
                selection: $globalReminderTime,
                displayedComponents: .hourAndMinute
            )
            .onChange(of: globalReminderTime) { _, newValue in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                AppSettings.globalReminderTime = comps
            }

            switch reminders.authorization {
            case .denied:
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Enable in System Settings", systemImage: "bell.slash")
                }
            case .notRequestedYet, .unknown:
                Button {
                    Task { await reminders.requestAuthorizationIfNeeded() }
                } label: {
                    Label("Turn on notifications", systemImage: "bell")
                }
            case .granted:
                EmptyView()
            }

            NavigationLink {
                PerProjectRemindersView(projects: projects)
            } label: {
                Label("Manage per-project schedules", systemImage: "calendar.badge.clock")
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Habit-stacked phrasing — like \"After your coffee\" — keeps reminders gentle. Missed days are paused, never broken.")
                .bodyStyle(12)
        }
    }

    // MARK: - Export

    private var exportSection: some View {
        Section {
            Button {
                Task { await exportCoordinator.runAllProjects(projects) }
            } label: {
                Label("Export all projects (.zip)", systemImage: "archivebox")
            }
            .disabled(projects.isEmpty)
        } header: {
            Text("Export")
        } footer: {
            Text("Export a zip of all your projects any time, whether or not iCloud backup is on.")
                .bodyStyle(12)
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.6))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Your photos stay on this device.")
                    .bodyStyle(14, weight: .semibold)
                Text("Locations are stripped before save. Notifications are optional. iCloud backup is opt-in. You can export everything any time.")
                    .bodyStyle(12)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.65))
            }
            .padding(.vertical, 6)
        } header: {
            Text("About")
        }
    }

    // MARK: - Helpers

    private func statusRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(NeonPlayroom.limeSqueeze)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .bodyStyle(14, weight: .semibold)
                Text(subtitle)
                    .bodyStyle(12)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.65))
            }
        }
        .padding(.vertical, 4)
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private static func componentsToDate(_ components: DateComponents) -> Date {
        Calendar.current.date(
            bySettingHour: components.hour ?? 9,
            minute: components.minute ?? 0,
            second: 0,
            of: .now
        ) ?? .now
    }
}

// MARK: - Per-project reminders sub-screen

private struct PerProjectRemindersView: View {
    let projects: [Project]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            ForEach(projects) { project in
                PerProjectRow(project: project)
            }
        }
        .scrollContentBackground(.hidden)
        .background(NeonPlayroom.midnightAbyss.ignoresSafeArea())
        .navigationTitle("Project reminders")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PerProjectRow: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context

    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date
    @State private var reminderHabit: ReminderHabit

    init(project: Project) {
        self.project = project
        _reminderEnabled = State(initialValue: project.reminderTime != nil)
        let globalComps = AppSettings.globalReminderTime
        let globalDefault = Calendar.current.date(
            bySettingHour: globalComps.hour ?? 9,
            minute: globalComps.minute ?? 0,
            second: 0,
            of: .now
        ) ?? .now
        _reminderTime = State(initialValue: project.reminderTime ?? globalDefault)
        _reminderHabit = State(initialValue: project.reminderHabit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(NeonPlayroom.limeSqueeze)
                    .frame(width: 10, height: 10)
                Text(project.name)
                    .bodyStyle(15, weight: .semibold)
                Spacer()
                Toggle("", isOn: $reminderEnabled)
                    .labelsHidden()
                    .onChange(of: reminderEnabled) { _, isOn in apply(isOn: isOn) }
            }
            if reminderEnabled {
                DatePicker(
                    "Time",
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )
                .onChange(of: reminderTime) { _, _ in apply(isOn: true) }
                Picker("Habit stack", selection: $reminderHabit) {
                    ForEach(ReminderHabit.allCases) { habit in
                        Text(habit.displayName).tag(habit)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: reminderHabit) { _, _ in apply(isOn: true) }
                Text(reminderHabit.notificationBody(for: project.name))
                    .bodyStyle(11)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
    }

    private func apply(isOn: Bool) {
        project.reminderTime = isOn ? reminderTime : nil
        project.reminderHabit = reminderHabit
        try? context.save()
        Task {
            if isOn {
                await ReminderScheduler.shared.scheduleReminder(for: project, at: reminderTime)
            } else {
                await ReminderScheduler.shared.removeReminders(for: project)
            }
        }
    }
}
