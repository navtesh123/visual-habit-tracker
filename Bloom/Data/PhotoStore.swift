import Foundation
import UIKit
import SwiftData

/// Metadata recorded by the camera at capture time.
struct CaptureMeta: Sendable {
    var capturedAt: Date = .now
    var note: String?
}

/// Local-first photo storage (PRD §4.1).
///
/// Originals are written to the app's private container at
/// `Documents/Photos/<projectID>/<photoID>.heic`. Thumbnails sit alongside in
/// `Documents/Photos/<projectID>/thumbs/<photoID>.heic`. **Nothing** is ever
/// written to the system Photos library — this keeps sensitive face/body
/// shots out of the user's main gallery and means deletions from the camera
/// roll cannot affect tracked photos.
final class PhotoStore: @unchecked Sendable {
    static let shared = PhotoStore()

    private let assets: PhotoAssetStore
    private let mediaLoader: MediaLoader

    init(
        assets: PhotoAssetStore = .shared,
        mediaLoader: MediaLoader = .shared
    ) {
        self.assets = assets
        self.mediaLoader = mediaLoader
    }

    // MARK: - Public API

    /// Persist a captured image for the given project and insert a `Photo` record.
    /// EXIF/GPS is stripped before writing (PRD §5.3).
    ///
    /// Async path: HEIC encoding + thumbnail generation + two disk writes
    /// run on a background task so the main thread (and UIKit's gesture
    /// gate) stays responsive while the user waits on the Save button.
    /// Only the final SwiftData mutation hops back to the main actor.
    @MainActor
    @discardableResult
    func save(
        _ image: UIImage,
        for project: Project,
        meta: CaptureMeta,
        in context: ModelContext
    ) async throws -> Photo {
        let photoID = UUID()
        let refs = try await assets.writeCapturedImage(
            image,
            projectID: project.id,
            photoID: photoID
        )

        do {
            return try ProjectRepository(context: context).insertPhoto(
                id: photoID,
                project: project,
                fileRef: refs.fileRef,
                thumbRef: refs.thumbRef,
                meta: meta
            )
        } catch {
            try? assets.deleteAssets(fileRef: refs.fileRef, thumbRef: refs.thumbRef)
            throw error
        }
    }

    /// Delete a photo and both of its on-disk files.
    @MainActor
    func delete(_ photo: Photo, in context: ModelContext) throws {
        let fileRef = photo.fileRef
        let thumbRef = photo.thumbRef
        try ProjectRepository(context: context).deletePhoto(photo)
        try assets.deleteAssets(fileRef: fileRef, thumbRef: thumbRef)
    }

    /// Remove all on-disk assets for a project after its SwiftData record is deleted.
    func deleteFiles(for project: Project) {
        deleteFiles(for: project.id)
    }

    func deleteFiles(for projectID: UUID) {
        try? assets.deleteProjectDirectory(projectID: projectID)
    }

    func deleteFiles(forProjectID projectID: UUID) {
        deleteFiles(for: projectID)
    }

    func fileExists(relativePath: String) -> Bool {
        assets.fileExists(relativePath: relativePath)
    }

    func originalURL(for photo: Photo) -> URL {
        assets.originalURL(fileRef: photo.fileRef)
    }

    func thumbnailURL(for photo: Photo) -> URL {
        assets.thumbnailURL(thumbRef: photo.thumbRef)
    }

    /// Load the full-resolution image for compare/timelapse views.
    func loadFullImage(_ photo: Photo) -> UIImage? {
        loadFullImage(relativePath: photo.fileRef)
    }

    func loadFullImage(relativePath: String) -> UIImage? {
        assets.loadImage(relativePath: relativePath)
    }

    /// Async full-resolution load for user-facing flows (photo viewer,
    /// review screen, compare). Decoding HEIC at full resolution can take
    /// tens of milliseconds — long enough to starve UIKit's gesture gate
    /// when called synchronously on the main thread.
    func loadFullImageAsync(_ photo: Photo) async -> UIImage? {
        await loadFullImageAsync(relativePath: photo.fileRef)
    }

    func loadFullImageAsync(relativePath: String) async -> UIImage? {
        await mediaLoader.fullImage(relativePath: relativePath)
    }

    /// Load the cached thumbnail for grid/list views.
    func loadThumb(_ photo: Photo) -> UIImage? {
        loadThumb(relativePath: photo.thumbRef)
    }

    /// Load a cached thumbnail. Hits an in-memory NSCache first; on miss,
    /// reads the file (synchronously) and inserts into the cache.
    func loadThumb(relativePath: String) -> UIImage? {
        mediaLoader.cachedThumbnail(relativePath: relativePath)
    }

    /// Async thumbnail loader for Home rows. Decodes off the main actor
    /// (file read + HEIC decode are non-trivial and otherwise pile onto
    /// the main thread when many `ProjectCard`s render at once) and
    /// memoizes the result.
    func loadThumbAsync(relativePath: String) async -> UIImage? {
        await mediaLoader.thumbnail(relativePath: relativePath)
    }
}
