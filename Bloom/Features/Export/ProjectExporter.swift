// PRD §4.3 — "iCloud-independent escape hatch". A user can always pull a
// full copy of every project out of Progress without an account, without
// network, and without our cloud being involved. M10 surfaces three formats:
//
//   • MP4 timelapse  (the same renderer M6 uses)
//   • contact-sheet PNG
//   • .zip of HEIC originals
//
// Zipping is done via NSFileCoordinator's `.forUploading` option, which
// transparently produces a single-file `.zip` from a directory on iOS —
// no third-party deps, no AppleArchive entitlements.

import Foundation
import UIKit
import SwiftData

@MainActor
enum ProjectExporter {
    enum ExportError: Error {
        case noPhotos
        case fileSystemFailure(underlying: Error)
        case renderFailure(underlying: Error)
    }

    // MARK: - Public entry points

    /// Export the entire project as an MP4 timelapse. Reuses the M6 renderer.
    static func exportTimelapseMP4(
        for project: Project,
        speed: Double = 1.0
    ) async throws -> URL {
        let frames = try resolvedFrames(for: project)
        do {
            return try await TimelapseRenderer.render(
                frames: frames,
                speed: speed,
                projectName: project.name,
                accent: project.accentColor,
                normalize: true
            )
        } catch {
            throw ExportError.renderFailure(underlying: error)
        }
    }

    /// Export a contact-sheet PNG. Falls back to `nil` if `ImageRenderer`
    /// can't produce a backing image for the requested size.
    static func exportContactSheetPNG(for project: Project) throws -> URL {
        guard !project.photos.isEmpty else { throw ExportError.noPhotos }
        let payload: [(UIImage, Date)] = project.photosByDateAscending.compactMap { photo in
            guard let img = PhotoStore.shared.loadFullImage(photo) else { return nil }
            return (img, photo.capturedAt)
        }
        guard !payload.isEmpty else { throw ExportError.noPhotos }
        guard let image = ContactSheetRenderer.render(
            projectName: project.name,
            accent: project.accentColor,
            photos: payload
        ) else {
            throw ExportError.renderFailure(underlying: NSError(
                domain: "ContactSheetRenderer", code: -1
            ))
        }
        guard let data = image.pngData() else {
            throw ExportError.renderFailure(underlying: NSError(
                domain: "ContactSheetRenderer.pngData", code: -1
            ))
        }
        let url = scratchURL(suggestedName: "\(safeName(project.name))-contact-sheet.png")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw ExportError.fileSystemFailure(underlying: error)
        }
        return url
    }

    /// Bundle a project's HEIC originals into a single `.zip` ready for the
    /// share sheet. Uses `NSFileCoordinator` with `.forUploading` so we don't
    /// pull in a third-party archiver.
    static func exportOriginalsZIP(for project: Project) throws -> URL {
        guard !project.photos.isEmpty else { throw ExportError.noPhotos }
        let stagingDir = try makeStagingDirectory(name: safeName(project.name))
        defer {
            try? FileManager.default.removeItem(at: stagingDir)
        }

        for photo in project.photosByDateAscending {
            guard
                let data = PhotoStore.shared.loadFullImage(photo)?.heicData()
                    ?? loadRawData(for: photo)
            else { continue }
            let filename = "\(formattedFilenameTimestamp(photo.capturedAt))-\(photo.id.uuidString.prefix(8)).heic"
            let destination = stagingDir.appendingPathComponent(filename)
            do {
                try data.write(to: destination)
            } catch {
                throw ExportError.fileSystemFailure(underlying: error)
            }
        }

        return try zipDirectory(stagingDir, suggestedName: "\(safeName(project.name))-originals")
    }

    /// One zip containing every project's originals. Used by the Settings
    /// "Export all projects" action.
    static func exportAllProjectsZIP(projects: [Project]) throws -> URL {
        let stagingRoot = try makeStagingDirectory(name: "Bloom-AllProjects")
        defer { try? FileManager.default.removeItem(at: stagingRoot) }

        for project in projects {
            let projectDir = stagingRoot.appendingPathComponent(safeName(project.name), isDirectory: true)
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            for photo in project.photosByDateAscending {
                guard let data = loadRawData(for: photo) else { continue }
                let filename = "\(formattedFilenameTimestamp(photo.capturedAt))-\(photo.id.uuidString.prefix(8)).heic"
                try data.write(to: projectDir.appendingPathComponent(filename))
            }
        }
        return try zipDirectory(stagingRoot, suggestedName: "Bloom-AllProjects")
    }

    // MARK: - Pure helpers (exposed for tests)

    /// Slugify a project name to a filesystem-safe token.
    static func safeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = trimmed
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return slug.isEmpty ? "Project" : slug
    }

    /// Stable, sortable filename timestamp for exported originals.
    static func formattedFilenameTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withYear, .withMonth, .withDay]
        // ISO8601DateFormatter emits "2025-09-12" with these options.
        return formatter.string(from: date)
    }

    /// Target URL the exporter would use for a given suggested filename in
    /// the scratch dir. Pure / synchronous — exposed for tests.
    static func scratchURL(suggestedName: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
    }

    // MARK: - Private helpers

    private static func resolvedFrames(for project: Project) throws -> [TimelapseFrame] {
        guard !project.photos.isEmpty else { throw ExportError.noPhotos }
        let frames: [TimelapseFrame] = project.photosByDateAscending.compactMap { photo in
            guard let image = PhotoStore.shared.loadFullImage(photo) else { return nil }
            return TimelapseFrame(image: image, capturedAt: photo.capturedAt)
        }
        guard !frames.isEmpty else { throw ExportError.noPhotos }
        return frames
    }

    private static func loadRawData(for photo: Photo) -> Data? {
        let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return docsURL.flatMap { try? Data(contentsOf: $0.appendingPathComponent(photo.fileRef)) }
    }

    private static func makeStagingDirectory(name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-staging-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            throw ExportError.fileSystemFailure(underlying: error)
        }
    }

    /// Wrap `directory` in a single `.zip`. `NSFileCoordinator` with
    /// `.forUploading` is the documented Foundation path for producing a zip
    /// on iOS without a third-party dep.
    private static func zipDirectory(_ directory: URL, suggestedName: String) throws -> URL {
        var coordinatorError: NSError?
        var resultURL: URL?
        var moveError: Error?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: directory,
            options: [.forUploading],
            error: &coordinatorError
        ) { zippedURL in
            let finalURL = scratchURL(suggestedName: "\(suggestedName).zip")
            try? FileManager.default.removeItem(at: finalURL)
            do {
                try FileManager.default.copyItem(at: zippedURL, to: finalURL)
                resultURL = finalURL
            } catch {
                moveError = error
            }
        }

        if let coordinatorError {
            throw ExportError.fileSystemFailure(underlying: coordinatorError)
        }
        if let moveError {
            throw ExportError.fileSystemFailure(underlying: moveError)
        }
        guard let resultURL else {
            throw ExportError.fileSystemFailure(underlying: NSError(
                domain: "ProjectExporter.zip", code: -1
            ))
        }
        return resultURL
    }
}

// MARK: - UIImage HEIC convenience

private extension UIImage {
    /// Re-encode the in-memory representation as HEIC. Used when re-bundling
    /// originals for the zip and the original file failed to load.
    func heicData(quality: CGFloat = 0.92) -> Data? {
        try? ImageProcessing.encodeStrippedHEIC(self, quality: quality)
    }
}
