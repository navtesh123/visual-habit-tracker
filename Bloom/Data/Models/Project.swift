import Foundation
import SwiftData

/// A tracked subject and its capture schedule (PRD §4.2).
///
/// The stable `id: UUID` is the primary key for any future CloudKit / account
/// migration (PRD §4.4). Never key persistence on insertion order or file name.
@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var subjectTypeRaw: String
    var cadenceRaw: String
    var reminderTime: Date?
    var accentColorTokenRaw: String
    var createdAt: Date

    /// Habit-stacked reminder copy (PRD §6, M8). Optional for migration
    /// safety — projects created before M8 default to `.custom`.
    var reminderHabitRaw: String?

    @Relationship(deleteRule: .cascade, inverse: \Photo.project)
    var photos: [Photo] = []

    @Relationship(deleteRule: .cascade, inverse: \ReferenceShot.project)
    var referenceShot: ReferenceShot?

    init(
        id: UUID = UUID(),
        name: String,
        subjectType: SubjectType = .object,
        cadence: Cadence = .weekly,
        reminderTime: Date? = nil,
        reminderHabit: ReminderHabit = .custom,
        accentColor: AccentToken = .default,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.subjectTypeRaw = subjectType.rawValue
        self.cadenceRaw = cadence.rawValue
        self.reminderTime = reminderTime
        self.reminderHabitRaw = reminderHabit.rawValue
        self.accentColorTokenRaw = accentColor.rawValue
        self.createdAt = createdAt
    }

    var subjectType: SubjectType {
        get { SubjectType(rawValue: subjectTypeRaw) ?? .other }
        set { subjectTypeRaw = newValue.rawValue }
    }

    var cadence: Cadence {
        get { Cadence(rawValue: cadenceRaw) ?? .weekly }
        set { cadenceRaw = newValue.rawValue }
    }

    var accentColor: AccentToken {
        get { AccentToken(rawValue: accentColorTokenRaw) ?? .default }
        set { accentColorTokenRaw = newValue.rawValue }
    }

    var reminderHabit: ReminderHabit {
        get { ReminderHabit(rawValue: reminderHabitRaw ?? "") ?? .custom }
        set { reminderHabitRaw = newValue.rawValue }
    }

    // MARK: Derived helpers

    var photosByDateAscending: [Photo] {
        photos.sorted { $0.capturedAt < $1.capturedAt }
    }

    var latestPhoto: Photo? {
        photosByDateAscending.last
    }

    var firstPhoto: Photo? {
        photosByDateAscending.first
    }

    /// The photo whose framing should be used as the camera ghost overlay.
    /// Falls back to the most recent capture if no explicit reference is set
    /// (PRD §3.3, §4.2 ReferenceShot entity).
    var overlayReferencePhoto: Photo? {
        if let referenceID = referenceShot?.photoID,
           let match = photos.first(where: { $0.id == referenceID }) {
            return match
        }
        return latestPhoto
    }

    /// Whole days since the most recent capture, or `nil` if no captures yet.
    var daysSinceLastCapture: Int? {
        guard let latest = latestPhoto else { return nil }
        let comps = Calendar.current.dateComponents([.day], from: latest.capturedAt, to: .now)
        return comps.day
    }

    /// True when we're past the soft-gap threshold for the cadence (PRD §6).
    /// Used for a gentle chip — never a streak-break penalty.
    var isBehindCadence: Bool {
        guard
            let threshold = cadence.gapThresholdDays,
            let gap = daysSinceLastCapture
        else { return false }
        return gap > threshold
    }

    /// Number of photos captured in the current calendar month (PRD §6, M8).
    ///
    /// Powers the "12 photos this month" chip — a forgiving alternative to a
    /// streak counter. The metric only counts up, never resets to zero, so
    /// a missed day reads as a pause, not a failure.
    var cumulativeThisMonth: Int {
        let calendar = Calendar.current
        let now = Date.now
        guard let start = calendar.dateInterval(of: .month, for: now)?.start else {
            return 0
        }
        return photos.reduce(into: 0) { count, photo in
            if photo.capturedAt >= start { count += 1 }
        }
    }
}
