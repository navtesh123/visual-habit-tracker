// PRD §3.7 / M9 — the home-screen widget needs the latest photo for the
// "primary" project (pinned in Settings or, failing that, the most-recently
// captured). Widgets don't share the main app's SwiftData store, so we
// write a tiny JSON snapshot + a JPEG of the latest thumbnail to the App
// Group container and the widget reads from there.

import Foundation
import UIKit
import SwiftData
import WidgetKit

@MainActor
enum WidgetSnapshotPublisher {
    static let snapshotFilename = WidgetSharedConstants.snapshotFilename
    static let latestPhotoFilename = WidgetSharedConstants.latestPhotoFilename
    static let widgetKind = WidgetSharedConstants.widgetKind

    /// Recompute the snapshot from the live SwiftData store and write it to
    /// the App Group. Call after every photo save / project edit / pin change.
    static func publish(from projects: [Project]) {
        let primary = primaryProject(in: projects)
        guard let containerURL = appGroupURL() else {
            // App Group entitlement missing in this build — skip silently so
            // the widget just shows its empty state.
            return
        }

        let snapshot: WidgetSnapshot
        if let project = primary, let latest = project.latestPhoto {
            let imageRelativePath: String?
            if let fullImage = PhotoStore.shared.loadFullImage(latest)
                ?? PhotoStore.shared.loadThumb(latest),
               let data = fullImage.jpegData(compressionQuality: 0.78)
            {
                let dest = containerURL.appendingPathComponent(latestPhotoFilename)
                do {
                    try data.write(to: dest, options: .atomic)
                    imageRelativePath = latestPhotoFilename
                } catch {
                    imageRelativePath = nil
                }
            } else {
                imageRelativePath = nil
            }

            snapshot = WidgetSnapshot(
                schema: WidgetSnapshot.currentSchema,
                projectID: project.id,
                projectName: project.name,
                accentTokenRaw: project.accentColor.rawValue,
                photoCount: project.photos.count,
                lastCaptureAt: latest.capturedAt,
                cumulativeThisMonth: project.cumulativeThisMonth,
                latestPhotoJPEGRelativePath: imageRelativePath
            )
        } else if let project = primary {
            snapshot = WidgetSnapshot(
                schema: WidgetSnapshot.currentSchema,
                projectID: project.id,
                projectName: project.name,
                accentTokenRaw: project.accentColor.rawValue,
                photoCount: 0,
                lastCaptureAt: nil,
                cumulativeThisMonth: 0,
                latestPhotoJPEGRelativePath: nil
            )
        } else {
            snapshot = WidgetSnapshot(
                schema: WidgetSnapshot.currentSchema,
                projectID: nil,
                projectName: "Progress",
                accentTokenRaw: AccentToken.default.rawValue,
                photoCount: 0,
                lastCaptureAt: nil,
                cumulativeThisMonth: 0,
                latestPhotoJPEGRelativePath: nil
            )
        }

        let url = containerURL.appendingPathComponent(snapshotFilename)
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }

        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// Resolve the primary project: pinned-in-Settings if set and present,
    /// else the project with the most recently captured photo.
    static func primaryProject(in projects: [Project]) -> Project? {
        if let pinnedID = AppSettings.pinnedWidgetProjectID,
           let pinned = projects.first(where: { $0.id == pinnedID })
        {
            return pinned
        }
        return projects
            .compactMap { project -> (Project, Date)? in
                guard let latest = project.latestPhoto else { return nil }
                return (project, latest.capturedAt)
            }
            .max { $0.1 < $1.1 }?
            .0
            ?? projects.first
    }

    static func appGroupURL() -> URL? {
        WidgetSharedConstants.appGroupContainerURL()
    }
}
