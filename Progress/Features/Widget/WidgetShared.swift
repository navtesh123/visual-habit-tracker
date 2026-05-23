// PRD §3.7 / M9 — shared between the main app target and the
// `ProgressWidget` extension. Contains only pure-data types and the App
// Group constant; deliberately imports nothing beyond Foundation so the
// widget binary stays lean.

import Foundation

/// Plain-data shape persisted to disk for the widget. Versioned with a
/// `schema` field so future widget releases can refuse to render snapshots
/// they don't understand instead of crashing.
struct WidgetSnapshot: Codable, Equatable {
    static let currentSchema = 1

    let schema: Int
    let projectID: UUID?
    let projectName: String
    let accentTokenRaw: String
    let photoCount: Int
    let lastCaptureAt: Date?
    let cumulativeThisMonth: Int
    let latestPhotoJPEGRelativePath: String?
}

enum WidgetSharedConstants {
    static let appGroupIdentifier = "group.app.bloomtracker.BloomTracker"
    static let snapshotFilename = "widget-snapshot.json"
    static let latestPhotoFilename = "widget-latest.jpg"
    static let widgetKind = "ProgressWidget"

    static func appGroupContainerURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        )
    }

    /// Deep-link URL the widget puts behind its "Tap to capture" affordance.
    /// The main app's `.onOpenURL` handler routes these to the camera.
    static let captureURLScheme = "progress"
    static func captureURL(for projectID: UUID?) -> URL {
        if let projectID {
            return URL(string: "\(captureURLScheme)://capture/\(projectID.uuidString)")!
        }
        return URL(string: "\(captureURLScheme)://capture")!
    }
}
