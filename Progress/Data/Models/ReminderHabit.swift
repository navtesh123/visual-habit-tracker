import Foundation

/// Habit-stacked reminder phrasing (PRD §6).
///
/// Notification body copy borrows the surrounding habit so reminders feel
/// like an invitation to ride an existing routine, never a guilt trip:
/// "After your coffee — quick progress shot of <project>?"
enum ReminderHabit: String, Codable, CaseIterable, Identifiable, Sendable {
    case afterShower
    case afterCoffee
    case beforeBed
    case afterWorkout
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .afterShower:  return "After my shower"
        case .afterCoffee:  return "After my coffee"
        case .beforeBed:    return "Before bed"
        case .afterWorkout: return "After my workout"
        case .custom:       return "Just a friendly nudge"
        }
    }

    /// Copy used as the notification body. `projectName` is interpolated at
    /// schedule time. PRD §6 — never frames a missed day as failure.
    func notificationBody(for projectName: String) -> String {
        switch self {
        case .afterShower:
            return "After your shower — a quick progress shot of \(projectName)?"
        case .afterCoffee:
            return "After your coffee — fancy a quick \(projectName) shot?"
        case .beforeBed:
            return "Before bed — one quick \(projectName) shot wraps the day."
        case .afterWorkout:
            return "Post-workout — capture today's \(projectName)?"
        case .custom:
            return "A friendly nudge for \(projectName) — whenever you have a moment."
        }
    }
}
