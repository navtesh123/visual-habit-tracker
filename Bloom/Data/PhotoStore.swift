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

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    // MARK: - Public API

    /// Persist a captured image for the given project and insert a `Photo` record.
    /// EXIF/GPS is stripped before writing (PRD §5.3).
    @MainActor
    @discardableResult
    func save(
        _ image: UIImage,
        for project: Project,
        meta: CaptureMeta,
        in context: ModelContext
    ) throws -> Photo {
        let photoID = UUID()
        try ensureProjectDirectoryExists(for: project.id)

        // Encode original (HEIC, stripped) and a 512px thumb.
        let heicData = try ImageProcessing.encodeStrippedHEIC(image)
        let thumbImage = try ImageProcessing.makeThumbnail(from: heicData)
        let thumbData = try ImageProcessing.encodeStrippedHEIC(thumbImage, quality: 0.85)

        let fileRef = relativeFilePath(projectID: project.id, photoID: photoID)
        let thumbRef = relativeThumbPath(projectID: project.id, photoID: photoID)
        try heicData.write(to: absoluteURL(for: fileRef), options: .atomic)
        try thumbData.write(to: absoluteURL(for: thumbRef), options: .atomic)

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
        try context.save()
        return photo
    }

    /// Delete a photo and both of its on-disk files.
    @MainActor
    func delete(_ photo: Photo, in context: ModelContext) throws {
        try? fileManager.removeItem(at: absoluteURL(for: photo.fileRef))
        try? fileManager.removeItem(at: absoluteURL(for: photo.thumbRef))
        context.delete(photo)
        try context.save()
    }

    /// Load the full-resolution image for compare/timelapse views.
    func loadFullImage(_ photo: Photo) -> UIImage? {
        UIImage(contentsOfFile: absoluteURL(for: photo.fileRef).path)
    }

    /// Load the cached thumbnail for grid/list views.
    func loadThumb(_ photo: Photo) -> UIImage? {
        UIImage(contentsOfFile: absoluteURL(for: photo.thumbRef).path)
    }

    // MARK: - Path helpers

    private var documentsURL: URL {
        guard let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            fatalError("Could not resolve Documents directory")
        }
        return url
    }

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
