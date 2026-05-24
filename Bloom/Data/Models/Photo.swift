import Foundation
import SwiftData

/// A single captured photo within a project (PRD §4.2).
///
/// `fileRef` and `thumbRef` are paths relative to the app's `Documents`
/// directory. The originals live in the app's private container — never
/// the camera roll (PRD §4.1).
@Model
final class Photo {
    @Attribute(.unique) var id: UUID
    /// Inverse relationship populated by `Project.photos`.
    var project: Project?

    /// Relative path under `Documents/` to the full-resolution HEIC original.
    var fileRef: String
    /// Relative path under `Documents/` to the cached thumbnail.
    var thumbRef: String

    var capturedAt: Date
    var note: String?

    init(
        id: UUID = UUID(),
        project: Project? = nil,
        fileRef: String,
        thumbRef: String,
        capturedAt: Date = .now,
        note: String? = nil
    ) {
        self.id = id
        self.project = project
        self.fileRef = fileRef
        self.thumbRef = thumbRef
        self.capturedAt = capturedAt
        self.note = note
    }
}
