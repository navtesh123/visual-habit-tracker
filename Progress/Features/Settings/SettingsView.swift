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
    @Bindable private var lock = AppLockController.shared
    @Bindable private var reminders = ReminderScheduler.shared
    @State private var exportCoordinator = ExportCoordinator()

    @State private var backupEnabled: Bool = AppSettings.cloudKitBackupEnabled
    @State private var lockEnabled: Bool = AppSettings.faceIDLockEnabled
    @State private var globalReminderTime: Date = SettingsView.componentsToDate(AppSettings.globalReminderTime)
    @State private var pinnedWidgetID: UUID? = AppSettings.pinnedWidgetProjectID
    @State private var lockAlert: String?

    var body: some View {
        NavigationStack {
            Form {
                backupSection
                privacySection
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
            .alert("Couldn't enable lock", isPresented: Binding(
                get: { lockAlert != nil },
                set: { if !$0 { lockAlert = nil } }
            )) {
                Button("OK") { lockAlert = nil }
            } message: {
                Text(lockAlert ?? "")
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

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            Toggle(isOn: $lockEnabled) {
                Label(
                    "\(lock.biometryDisplayName) app lock",
                    systemImage: "lock.shield"
                )
            }
            .disabled(!lock.biometricsAvailable)
            .onChange(of: lockEnabled) { _, isOn in
                Task {
                    if isOn {
                        let ok = await lock.enableFromSettings()
                        if !ok {
                            lockEnabled = false
                            lockAlert = "We couldn't verify \(lock.biometryDisplayName). Try again from Settings."
                        }
                    } else {
                        lock.disable()
                    }
                }
            }

            if !lock.biometricsAvailable {
                Text("Set up \(lock.biometryDisplayName) on this device to enable the app lock.")
                    .bodyStyle(12)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.65))
            }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Photos stay in this app — they're never added to your camera roll. Locations are stripped from every photo before it's saved.")
                .bodyStyle(12)
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
            ForEach(projects) { project in
                Menu {
                    Button {
                        Task { await exportCoordinator.run(.timelapse, project: project) }
                    } label: {
                        Label("Timelapse (.mp4)", systemImage: "play.rectangle")
                    }
                    .disabled(project.photos.count < 2)
                    Button {
                        Task { await exportCoordinator.run(.contactSheet, project: project) }
                    } label: {
                        Label("Contact sheet (.png)", systemImage: "square.grid.3x3")
                    }
                    .disabled(project.photos.isEmpty)
                    Button {
                        Task { await exportCoordinator.run(.originalsZIP, project: project) }
                    } label: {
                        Label("Originals (.zip)", systemImage: "doc.zipper")
                    }
                    .disabled(project.photos.isEmpty)
                } label: {
                    HStack {
                        Circle()
                            .fill(project.accentColor.color)
                            .frame(width: 12, height: 12)
                        Text(project.name)
                            .bodyStyle(15, weight: .medium)
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(NeonPlayroom.limeSqueeze)
                    }
                }
            }

            Button {
                Task { await exportCoordinator.runAllProjects(projects) }
            } label: {
                Label("Export all projects (.zip)", systemImage: "archivebox")
            }
            .disabled(projects.isEmpty)

            Picker("Pin to widget", selection: Binding(
                get: { pinnedWidgetID ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")! },
                set: { newValue in
                    let nilSentinel = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                    let resolved: UUID? = (newValue == nilSentinel) ? nil : newValue
                    pinnedWidgetID = resolved
                    AppSettings.pinnedWidgetProjectID = resolved
                    WidgetSnapshotPublisher.publish(from: projects)
                }
            )) {
                Text("Most recently captured")
                    .tag(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
                ForEach(projects) { project in
                    Text(project.name).tag(project.id)
                }
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Manual exports work whether iCloud backup is on or off. This is your safety net.")
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

    init(project: Project) {
        self.project = project
        _reminderEnabled = State(initialValue: project.reminderTime != nil)
        _reminderTime = State(initialValue: project.reminderTime ?? Calendar.current.date(
            bySettingHour: 9, minute: 0, second: 0, of: .now
        ) ?? .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(project.accentColor.color)
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
                Text(project.reminderHabit.notificationBody(for: project.name))
                    .bodyStyle(11)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
    }

    private func apply(isOn: Bool) {
        project.reminderTime = isOn ? reminderTime : nil
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
