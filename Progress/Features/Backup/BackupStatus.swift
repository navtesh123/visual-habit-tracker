// PRD §4.3 — backup status surfaced calmly on Home and Settings.
//
// Status is intentionally a small enum, not a string, so the UI can render
// a specific tone (info / caution / error) without re-parsing the message.

import Foundation

enum BackupStatus: Equatable, Sendable {
    case disabled
    case syncing
    case active(lastSynced: Date?)
    case paused(reason: PauseReason)
    case error(message: String)

    enum PauseReason: Equatable, Sendable {
        case quotaExceeded
        case offline
        case notSignedIn
    }

    var isOK: Bool {
        switch self {
        case .active, .syncing: return true
        default: return false
        }
    }

    var headline: String {
        switch self {
        case .disabled:         return "iCloud backup off"
        case .syncing:          return "Syncing…"
        case .active:           return "Backed up to iCloud"
        case .paused(.quotaExceeded):
            return "Backup paused — iCloud full"
        case .paused(.offline): return "Backup paused — offline"
        case .paused(.notSignedIn):
            return "Backup paused — sign in to iCloud"
        case .error(let m):     return "Backup error: \(m)"
        }
    }

    var subtitle: String {
        switch self {
        case .disabled:
            return "Your photos still live on this device. Turn on in Settings."
        case .syncing:
            return "Sending your latest photos to your private iCloud."
        case .active(let date):
            if let date {
                return "Last synced \(RelativeDateFormatting.relative(from: date))."
            }
            return "Your photos are safe in your private iCloud."
        case .paused(.quotaExceeded):
            return "Free up some iCloud space and we'll pick up where we left off — your photos are safe on this device in the meantime."
        case .paused(.offline):
            return "We'll resume once you're back online. Nothing's lost."
        case .paused(.notSignedIn):
            return "Sign in to iCloud in System Settings to back up your photos."
        case .error:
            return "We hit a snag. Your photos are still safe on this device — try again from Settings."
        }
    }
}
