import Foundation
import SwiftData

/// A tracked subject and its capture schedule (PRD §4.2).
///
/// The stable `id: UUID` keeps projects independent from insertion order or
/// file names.
@Model
final class Project {
    @Attribute(.unique) var id: UUID
    var name: String
    var subjectTypeRaw: String
    var cadenceRaw: String
    var reminderTime: Date?
    var createdAt: Date

    /// Habit-stacked reminder copy (PRD §6, M8). Optional for migration
    /// safety — projects created before M8 default to `.custom`.
    var reminderHabitRaw: String?

    /// Summary fields used by Home so app launch does not have to fault and
    /// sort every photo relationship before the project list can render.
    var photoCountCache: Int?
    var latestPhotoIDCache: UUID?
    var latestPhotoCapturedAtCache: Date?
    var latestPhotoThumbRefCache: String?

    @Relationship(deleteRule: .cascade, inverse: \Photo.project)
    var photos: [Photo] = []

    init(
        id: UUID = UUID(),
        name: String,
        subjectType: SubjectType = .object,
        cadence: Cadence = .weekly,
        reminderTime: Date? = nil,
        reminderHabit: ReminderHabit = .custom,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.subjectTypeRaw = subjectType.rawValue
        self.cadenceRaw = cadence.rawValue
        self.reminderTime = reminderTime
        self.reminderHabitRaw = reminderHabit.rawValue
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

    var reminderHabit: ReminderHabit {
        get { ReminderHabit(rawValue: reminderHabitRaw ?? "") ?? .custom }
        set { reminderHabitRaw = newValue.rawValue }
    }

    // MARK: Derived helpers

    var photosByDateAscending: [Photo] {
        photos.sorted { $0.capturedAt < $1.capturedAt }
    }

    var photoSummaryNeedsBackfill: Bool {
        photoCountCache == nil
    }

    var cachedPhotoCount: Int {
        photoCountCache ?? 0
    }

    var cachedLatestPhotoID: UUID? {
        latestPhotoIDCache
    }

    var cachedLatestPhotoCapturedAt: Date? {
        latestPhotoCapturedAtCache
    }

    var cachedLatestPhotoThumbRef: String? {
        latestPhotoThumbRefCache
    }

    var cachedDaysSinceLastCapture: Int? {
        guard let latest = latestPhotoCapturedAtCache else { return nil }
        let comps = Calendar.current.dateComponents([.day], from: latest, to: .now)
        return comps.day
    }

    var cachedIsBehindCadence: Bool {
        guard
            let threshold = cadence.gapThresholdDays,
            let gap = cachedDaysSinceLastCapture
        else { return false }
        return gap > threshold
    }

    func refreshPhotoSummaryFromPhotos() {
        refreshPhotoSummary(from: photos)
    }

    func refreshPhotoSummary(from photos: [Photo]) {
        photoCountCache = photos.count
        guard let latest = photos.max(by: { $0.capturedAt < $1.capturedAt }) else {
            latestPhotoIDCache = nil
            latestPhotoCapturedAtCache = nil
            latestPhotoThumbRefCache = nil
            return
        }
        latestPhotoIDCache = latest.id
        latestPhotoCapturedAtCache = latest.capturedAt
        latestPhotoThumbRefCache = latest.thumbRef
    }

    var latestPhoto: Photo? {
        photos.max(by: { $0.capturedAt < $1.capturedAt })
    }

    var firstPhoto: Photo? {
        photos.min(by: { $0.capturedAt < $1.capturedAt })
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
