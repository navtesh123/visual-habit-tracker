// PRD §3.8 — Settings. Local-first v1 exposes privacy, reminders, and about
// in one calm surface.
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

    @Bindable private var reminders = ReminderScheduler.shared

    @State private var globalReminderTime: Date = SettingsView.componentsToDate(AppSettings.globalReminderTime)

    var body: some View {
        NavigationStack {
            Form {
                privacySection
                remindersSection
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
            .task {
                await reminders.refreshAuthorizationState()
            }
        }
        .tint(NeonPlayroom.limeSqueeze)
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            statusRow(
                icon: "lock.doc",
                title: "Local-only photo library",
                subtitle: "Originals and thumbnails stay in Bloom's private app folder."
            )
            statusRow(
                icon: "location.slash",
                title: "Location metadata stripped",
                subtitle: "Captured photos are re-encoded before save so GPS data is not kept."
            )
        } header: {
            Text("Privacy")
        } footer: {
            Text("iCloud backup is not part of this local build.")
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
                Text("Locations are stripped before save. Notifications are optional.")
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
