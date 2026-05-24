import Foundation
import UIKit
import SwiftData

/// Metadata recorded by the camera at capture time.
/// Persisted onto `Photo` for the next session's framing guidance (PRD §3.3).
struct CaptureMeta: Sendable {
    var pitch: Double?
    var roll: Double?
    var yaw: Double?
    var zoom: Double?
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

    private let fileManager: FileManager
    private let rootDirectoryName = "Photos"
    private let thumbsSubdirectoryName = "thumbs"

    /// In-memory thumbnail cache keyed on the relative on-disk path.
    /// Avoids re-decoding HEIC bytes every time a `ProjectCard` re-renders
    /// or a Home row scrolls back into view. NSCache evicts under memory
    /// pressure automatically.
    private let thumbCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 200
        return cache
    }()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Could not resolve Documents directory")
        }
        self.documentsURL = url
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
        try ensureProjectDirectoryExists(for: project.id)

        let projectID = project.id
        let fileRef = relativeFilePath(projectID: projectID, photoID: photoID)
        let thumbRef = relativeThumbPath(projectID: projectID, photoID: photoID)
        let originalURL = absoluteURL(for: fileRef)
        let thumbURL = absoluteURL(for: thumbRef)

        try await Task.detached(priority: .userInitiated) {
            let heicData = try ImageProcessing.encodeStrippedHEIC(image)
            let thumbImage = try ImageProcessing.makeThumbnail(from: heicData)
            let thumbData = try ImageProcessing.encodeStrippedHEIC(thumbImage, quality: 0.85)
            try heicData.write(to: originalURL, options: .atomic)
            try thumbData.write(to: thumbURL, options: .atomic)
        }.value

        let photo = Photo(
            id: photoID,
            project: project,
            fileRef: fileRef,
            thumbRef: thumbRef,
            capturedAt: meta.capturedAt,
            note: meta.note,
            pitch: meta.pitch,
            roll: meta.roll,
            yaw: meta.yaw,
            zoom: meta.zoom
        )
        context.insert(photo)
        var photos = project.photos.filter { $0.id != photo.id }
        photos.append(photo)
        project.refreshPhotoSummary(from: photos)
        try context.save()
        return photo
    }

    /// Delete a photo and both of its on-disk files.
    @MainActor
    func delete(_ photo: Photo, in context: ModelContext) throws {
        try? fileManager.removeItem(at: absoluteURL(for: photo.fileRef))
        try? fileManager.removeItem(at: absoluteURL(for: photo.thumbRef))
        let project = photo.project
        let remainingPhotos = project?.photos.filter { $0.id != photo.id } ?? []
        context.delete(photo)
        project?.refreshPhotoSummary(from: remainingPhotos)
        try context.save()
    }

    /// Load the full-resolution image for compare/timelapse views.
    func loadFullImage(_ photo: Photo) -> UIImage? {
        UIImage(contentsOfFile: absoluteURL(for: photo.fileRef).path)
    }

    /// Async full-resolution load for user-facing flows (photo viewer,
    /// review screen, compare). Decoding HEIC at full resolution can take
    /// tens of milliseconds — long enough to starve UIKit's gesture gate
    /// when called synchronously on the main thread.
    func loadFullImageAsync(_ photo: Photo) async -> UIImage? {
        let absolutePath = absoluteURL(for: photo.fileRef).path
        return await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: absolutePath)
        }.value
    }

    /// Load the cached thumbnail for grid/list views.
    func loadThumb(_ photo: Photo) -> UIImage? {
        loadThumb(relativePath: photo.thumbRef)
    }

    /// Load a cached thumbnail. Hits an in-memory NSCache first; on miss,
    /// reads the file (synchronously) and inserts into the cache.
    func loadThumb(relativePath: String) -> UIImage? {
        let key = relativePath as NSString
        if let cached = thumbCache.object(forKey: key) {
            return cached
        }
        guard let image = UIImage(contentsOfFile: absoluteURL(for: relativePath).path) else {
            return nil
        }
        thumbCache.setObject(image, forKey: key)
        return image
    }

    /// Async thumbnail loader for Home rows. Decodes off the main actor
    /// (file read + HEIC decode are non-trivial and otherwise pile onto
    /// the main thread when many `ProjectCard`s render at once) and
    /// memoizes the result.
    func loadThumbAsync(relativePath: String) async -> UIImage? {
        let key = relativePath as NSString
        if let cached = thumbCache.object(forKey: key) {
            return cached
        }
        let absolutePath = absoluteURL(for: relativePath).path
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            UIImage(contentsOfFile: absolutePath)
        }.value
        if let image {
            thumbCache.setObject(image, forKey: key)
        }
        return image
    }

    // MARK: - Path helpers

    private let documentsURL: URL

    private func projectDirectoryURL(for projectID: UUID) -> URL {
        documentsURL
            .appendingPathComponent(rootDirectoryName, isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    private func thumbsDirectoryURL(for projectID: UUID) -> URL {
        projectDirectoryURL(for: projectID)
            .appendingPathComponent(thumbsSubdirectoryName, isDirectory: true)
    }

    private func ensureProjectDirectoryExists(for projectID: UUID) throws {
        try fileManager.createDirectory(
            at: thumbsDirectoryURL(for: projectID),
            withIntermediateDirectories: true
        )
    }

    private func relativeFilePath(projectID: UUID, photoID: UUID) -> String {
        "\(rootDirectoryName)/\(projectID.uuidString)/\(photoID.uuidString).heic"
    }

    private func relativeThumbPath(projectID: UUID, photoID: UUID) -> String {
        "\(rootDirectoryName)/\(projectID.uuidString)/\(thumbsSubdirectoryName)/\(photoID.uuidString).heic"
    }

    private func absoluteURL(for relativePath: String) -> URL {
        documentsURL.appendingPathComponent(relativePath)
    }
}
