import Foundation

/// Centralized `UserDefaults` keys + a typed accessor.
///
/// The Settings, Onboarding, Lock, Backup, and Widget surfaces all read /
/// write these keys; collecting them in one file keeps copy/paste typos out
/// of the codebase and gives an obvious diff surface for migrations.
enum AppSettings {
    enum Key {
        static let hasCompletedOnboarding   = "progress.hasCompletedOnboarding"
        static let cloudKitBackupEnabled    = "progress.cloudKitBackupEnabled"
        static let faceIDLockEnabled        = "progress.faceIDLockEnabled"
        static let globalReminderHour       = "progress.globalReminderHour"
        static let globalReminderMinute     = "progress.globalReminderMinute"
        static let notificationsAuthorized  = "progress.notificationsAuthorized"
        /// Optional `Project.id.uuidString`; if absent, widget falls back to
        /// the most-recently-captured project.
        static let pinnedWidgetProjectID    = "progress.pinnedWidgetProjectID"
    }

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Key.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    static var cloudKitBackupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.cloudKitBackupEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.cloudKitBackupEnabled) }
    }

    static var faceIDLockEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.faceIDLockEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.faceIDLockEnabled) }
    }

    static var notificationsAuthorized: Bool {
        get { UserDefaults.standard.bool(forKey: Key.notificationsAuthorized) }
        set { UserDefaults.standard.set(newValue, forKey: Key.notificationsAuthorized) }
    }

    /// Default reminder time. Stored as hour+minute so daylight-savings
    /// shifts don't drift the cue.
    static var globalReminderTime: DateComponents {
        get {
            let defaults = UserDefaults.standard
            // Sensible default — 9:00 AM local time.
            let hour = (defaults.object(forKey: Key.globalReminderHour) as? Int) ?? 9
            let minute = (defaults.object(forKey: Key.globalReminderMinute) as? Int) ?? 0
            return DateComponents(hour: hour, minute: minute)
        }
        set {
            UserDefaults.standard.set(newValue.hour ?? 9, forKey: Key.globalReminderHour)
            UserDefaults.standard.set(newValue.minute ?? 0, forKey: Key.globalReminderMinute)
        }
    }

    static var pinnedWidgetProjectID: UUID? {
        get {
            guard let raw = UserDefaults.standard.string(forKey: Key.pinnedWidgetProjectID) else {
                return nil
            }
            return UUID(uuidString: raw)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value.uuidString, forKey: Key.pinnedWidgetProjectID)
            } else {
                UserDefaults.standard.removeObject(forKey: Key.pinnedWidgetProjectID)
            }
        }
    }
}

/// App Group container ID shared between the main app and `ProgressWidget`.
/// Declared in both targets' `.entitlements` files.
enum AppGroup {
    static let identifier = "group.app.bloomtracker.BloomTracker"
}
