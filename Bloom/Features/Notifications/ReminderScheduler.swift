// PRD §6 — Reminders. One repeating local notification per project, at the
// project's chosen time, with cadence-appropriate trigger semantics.
//
// Authorization is requested *in context* — the moment the user enables a
// reminder, never on first launch. PRD §6.

import Foundation
import UserNotifications

@MainActor
@Observable
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    enum AuthorizationState: Equatable {
        case unknown
        case granted
        case denied
        case notRequestedYet
    }

    private(set) var authorization: AuthorizationState = .unknown

    private let center = UNUserNotificationCenter.current()

    // MARK: - Authorization

    /// Read current settings from the system. Idempotent; safe to call
    /// from `.onAppear`.
    func refreshAuthorizationState() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorization = .granted
            AppSettings.notificationsAuthorized = true
        case .denied:
            authorization = .denied
            AppSettings.notificationsAuthorized = false
        case .notDetermined:
            authorization = .notRequestedYet
            AppSettings.notificationsAuthorized = false
        @unknown default:
            authorization = .unknown
        }
    }

    /// Prompt for permission, in context. Returns `true` if the user
    /// granted notifications (or had granted them previously).
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorizationState()
        switch authorization {
        case .granted: return true
        case .denied:  return false
        default:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                authorization = granted ? .granted : .denied
                AppSettings.notificationsAuthorized = granted
                return granted
            } catch {
                authorization = .denied
                return false
            }
        }
    }

    // MARK: - Per-project scheduling

    /// Schedule (or re-schedule) the repeating reminder for a project.
    ///
    /// The trigger schedule respects `Project.cadence`:
    ///   • `.daily` — daily at the user's chosen time.
    ///   • `.fewDays` — daily at the chosen time (notifications need a
    ///     concrete trigger; the user's pacing handles the every-few-days
    ///     part).
    ///   • `.weekly` — weekly on the project's anniversary weekday.
    ///   • `.custom` — no automatic reminder (user opts in manually).
    func scheduleReminder(for project: Project, at time: Date) async {
        guard await requestAuthorizationIfNeeded() else { return }
        await removeReminders(for: project)

        let content = UNMutableNotificationContent()
        content.title = project.name
        content.body = project.reminderHabit.notificationBody(for: project.name)
        content.sound = .default
        content.threadIdentifier = "progress.project.\(project.id.uuidString)"

        let calendar = Calendar.current
        var components = calendar.dateComponents([.hour, .minute], from: time)

        let trigger: UNCalendarNotificationTrigger
        switch project.cadence {
        case .daily, .fewDays:
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .weekly:
            components.weekday = calendar.component(.weekday, from: project.createdAt)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .custom:
            // No automatic schedule — leave the reminder cleared.
            return
        }

        let request = UNNotificationRequest(
            identifier: identifier(for: project),
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
        } catch {
            // Silently swallow: a failed reminder is not a blocking error.
        }
    }

    /// Remove the project's reminder. Use when the user turns off the
    /// reminder, deletes the project, or switches to `.custom` cadence.
    func removeReminders(for project: Project) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier(for: project)])
    }

    func removeReminders(forProjectID projectID: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(forProjectID: projectID)])
    }

    /// Sync all reminders against the current project list. Call from
    /// app-launch after the store loads so deleted projects don't keep
    /// firing stale notifications.
    ///
    /// Performance: the underlying `UNUserNotificationCenter` calls are
    /// system roundtrips that, in aggregate, can stall the launch path.
    /// We:
    ///   • Hash the relevant project shape and skip the whole resync if it
    ///     matches the last run's fingerprint (the common case on every
    ///     launch where reminders haven't changed).
    ///   • Check authorization once at the top instead of per project.
    ///   • Diff against pending requests and only add what's actually
    ///     missing or stale.
    func resync(allProjects projects: [Project]) async {
        let fingerprint = Self.fingerprint(for: projects)
        if AppSettings.lastReminderSyncFingerprint == fingerprint
            && AppSettings.notificationsAuthorized {
            return
        }

        await refreshAuthorizationState()
        guard authorization == .granted || authorization == .notRequestedYet else {
            // No authorization yet — nothing to schedule. Don't spam the
            // user with a permission prompt at launch; that's done in the
            // onboarding flow / settings screen.
            AppSettings.lastReminderSyncFingerprint = fingerprint
            return
        }

        let validIDs = Set(projects.compactMap { project -> String? in
            project.reminderTime != nil ? identifier(for: project) : nil
        })
        let pending = await center.pendingNotificationRequests()
        let pendingIDs = Set(pending.map(\.identifier))

        let stale = pendingIDs.filter { id in
            id.hasPrefix("progress.reminder.") && !validIDs.contains(id)
        }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(stale))
        }

        for project in projects {
            guard let time = project.reminderTime else { continue }
            let id = identifier(for: project)
            if pendingIDs.contains(id) { continue }
            await scheduleReminderUnchecked(for: project, at: time)
        }

        AppSettings.lastReminderSyncFingerprint = fingerprint
    }

    /// Same as `scheduleReminder` but skips the per-call authorization check
    /// — used by the launch resync after a single batch auth check.
    private func scheduleReminderUnchecked(for project: Project, at time: Date) async {
        await removeReminders(for: project)

        let content = UNMutableNotificationContent()
        content.title = project.name
        content.body = project.reminderHabit.notificationBody(for: project.name)
        content.sound = .default
        content.threadIdentifier = "progress.project.\(project.id.uuidString)"

        let calendar = Calendar.current
        var components = calendar.dateComponents([.hour, .minute], from: time)

        let trigger: UNCalendarNotificationTrigger
        switch project.cadence {
        case .daily, .fewDays:
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .weekly:
            components.weekday = calendar.component(.weekday, from: project.createdAt)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        case .custom:
            return
        }

        let request = UNNotificationRequest(
            identifier: identifier(for: project),
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    private static func fingerprint(for projects: [Project]) -> String {
        let calendar = Calendar.current
        let parts: [String] = projects
            .compactMap { project -> String? in
                guard let time = project.reminderTime else { return nil }
                let comps = calendar.dateComponents([.hour, .minute], from: time)
                let h = comps.hour ?? 0
                let m = comps.minute ?? 0
                return "\(project.id.uuidString):\(project.cadenceRaw):\(h)-\(m):\(project.reminderHabitRaw ?? "")"
            }
            .sorted()
        return parts.joined(separator: "|")
    }

    // MARK: - Identifier convention

    nonisolated static func identifier(for project: Project) -> String {
        identifier(forProjectID: project.id)
    }

    nonisolated static func identifier(forProjectID projectID: UUID) -> String {
        "progress.reminder.\(projectID.uuidString)"
    }

    nonisolated func identifier(for project: Project) -> String {
        Self.identifier(for: project)
    }
}
