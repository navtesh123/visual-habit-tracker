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

    // CoreMotion attitude at capture time, recorded so the next session
    // can guide the user back to the same pose (PRD §3.3).
    var pitch: Double?
    var roll: Double?
    var yaw: Double?

    /// Zoom factor active at capture (e.g. `1.0`, `2.0`). Persisted so the
    /// camera can restore framing distance on the next session.
    var zoom: Double?

    init(
        id: UUID = UUID(),
        project: Project? = nil,
        fileRef: String,
        thumbRef: String,
        capturedAt: Date = .now,
        note: String? = nil,
        pitch: Double? = nil,
        roll: Double? = nil,
        yaw: Double? = nil,
        zoom: Double? = nil
    ) {
        self.id = id
        self.project = project
        self.fileRef = fileRef
        self.thumbRef = thumbRef
        self.capturedAt = capturedAt
        self.note = note
        self.pitch = pitch
        self.roll = roll
        self.yaw = yaw
        self.zoom = zoom
    }
}
