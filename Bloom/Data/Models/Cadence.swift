import Foundation

/// Capture frequency. Drives gap detection and reminder scheduling (PRD §3.2, §6).
enum Cadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case fewDays
    case weekly
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .fewDays: return "Every few days"
        case .weekly: return "Weekly"
        case .custom: return "Custom"
        }
    }

    /// Expected interval between captures, in days. `custom` has no fixed interval.
    var expectedIntervalDays: Int? {
        switch self {
        case .daily: return 1
        case .fewDays: return 3
        case .weekly: return 7
        case .custom: return nil
        }
    }

    /// Human-readable label for the reminder toggle in the project editor.
    var reminderToggleLabel: String {
        switch self {
        case .daily:   return "Daily reminder"
        case .fewDays: return "Reminder"
        case .weekly:  return "Weekly reminder"
        case .custom:  return "Reminder"
        }
    }

    /// How many days past expected before we surface a soft "behind cadence" chip.
    /// PRD §6 — never frame a gap as a failure; this is for nudges, not penalties.
    var gapThresholdDays: Int? {
        guard let expected = expectedIntervalDays else { return nil }
        return expected + 2
    }
}
