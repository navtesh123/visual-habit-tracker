import Foundation
import UIKit

/// File-system backed photo asset storage.
///
/// This owns the local-first invariant: original HEICs and thumbnails live
/// inside the app container, never in the user's Photos library.
final class PhotoAssetStore: @unchecked Sendable {
    static let shared = PhotoAssetStore()

    enum StoreError: LocalizedError {
        case documentsDirectoryUnavailable
        case missingAsset(String)

        var errorDescription: String? {
            switch self {
            case .documentsDirectoryUnavailable:
                return "Bloom could not open its private photo folder."
            case .missingAsset:
                return "That photo file is missing from this device."
            }
        }
    }

    private let fileManager: FileManager
    private let documentsURL: URL
    private let rootDirectoryName = "Photos"
    private let thumbsSubdirectoryName = "thumbs"

    init(fileManager: FileManager = .default, documentsURL: URL? = nil) {
        self.fileManager = fileManager
        if let documentsURL {
            self.documentsURL = documentsURL
        } else if let url = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            self.documentsURL = url
        } else {
            self.documentsURL = fileManager.temporaryDirectory
        }
    }

    func fileRefs(projectID: UUID, photoID: UUID) -> (fileRef: String, thumbRef: String) {
        (
            relativeFilePath(projectID: projectID, photoID: photoID),
            relativeThumbPath(projectID: projectID, photoID: photoID)
        )
    }

    func writeCapturedImage(
        _ image: UIImage,
        projectID: UUID,
        photoID: UUID
    ) async throws -> (fileRef: String, thumbRef: String) {
        try ensureProjectDirectoryExists(for: projectID)
        let refs = fileRefs(projectID: projectID, photoID: photoID)
        let originalURL = absoluteURL(for: refs.fileRef)
        let thumbURL = absoluteURL(for: refs.thumbRef)

        try await Task.detached(priority: .userInitiated) {
            let heicData = try ImageProcessing.encodeStrippedHEIC(image)
            let thumbImage = try ImageProcessing.makeThumbnail(from: heicData)
            let thumbData = try ImageProcessing.encodeStrippedHEIC(thumbImage, quality: 0.85)
            try heicData.write(to: originalURL, options: .atomic)
            try thumbData.write(to: thumbURL, options: .atomic)
        }.value

        return refs
    }

    func deleteAssets(fileRef: String, thumbRef: String) throws {
        var firstError: Error?
        for ref in [fileRef, thumbRef] {
            do {
                try fileManager.removeItem(at: absoluteURL(for: ref))
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                continue
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    func deleteProjectDirectory(projectID: UUID) throws {
        do {
            try fileManager.removeItem(at: projectDirectoryURL(for: projectID))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }

    func fileExists(relativePath: String) -> Bool {
        fileManager.fileExists(atPath: absoluteURL(for: relativePath).path)
    }

    func originalURL(fileRef: String) -> URL {
        absoluteURL(for: fileRef)
    }

    func thumbnailURL(thumbRef: String) -> URL {
        absoluteURL(for: thumbRef)
    }

    func loadImage(relativePath: String) -> UIImage? {
        UIImage(contentsOfFile: absoluteURL(for: relativePath).path)
    }

    func loadImageAsync(relativePath: String) async -> UIImage? {
        let path = absoluteURL(for: relativePath).path
        guard let raw = await Task.detached(priority: .userInitiated, operation: {
            UIImage(contentsOfFile: path)
        }).value else { return nil }
        return await raw.byPreparingForDisplay() ?? raw
    }

    func rawData(relativePath: String) -> Data? {
        try? Data(contentsOf: absoluteURL(for: relativePath))
    }

    // MARK: - Path helpers

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
