import Foundation

/// Centralized `UserDefaults` keys + a typed accessor.
///
/// Settings, onboarding, and reminders all read/write these keys; collecting
/// them in one file keeps copy/paste typos out of the codebase and gives an
/// obvious diff surface for migrations.
enum AppSettings {
    enum Key {
        static let hasCompletedOnboarding   = "progress.hasCompletedOnboarding"
        static let cloudKitBackupEnabled    = "progress.cloudKitBackupEnabled"
        static let globalReminderHour       = "progress.globalReminderHour"
        static let globalReminderMinute     = "progress.globalReminderMinute"
        static let notificationsAuthorized  = "progress.notificationsAuthorized"
        static let lastReminderSyncFingerprint = "progress.lastReminderSyncFingerprint"
    }

    static var hasCompletedOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: Key.hasCompletedOnboarding) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hasCompletedOnboarding) }
    }

    static var cloudKitBackupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.cloudKitBackupEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Key.cloudKitBackupEnabled) }
    }

    static var notificationsAuthorized: Bool {
        get { UserDefaults.standard.bool(forKey: Key.notificationsAuthorized) }
        set { UserDefaults.standard.set(newValue, forKey: Key.notificationsAuthorized) }
    }

    /// Hash of the project list shape that drove the last reminder resync.
    /// We compare on launch and only re-run the (system-call-heavy) resync
    /// when the shape actually changed since the previous launch.
    static var lastReminderSyncFingerprint: String? {
        get { UserDefaults.standard.string(forKey: Key.lastReminderSyncFingerprint) }
        set { UserDefaults.standard.set(newValue, forKey: Key.lastReminderSyncFingerprint) }
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

}
