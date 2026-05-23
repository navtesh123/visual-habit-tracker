import Foundation
import SwiftData

/// Records which photo in a project is the alignment reference for the
/// camera ghost overlay (PRD §4.2).
///
/// If absent, the camera uses the most recent photo as the reference.
@Model
final class ReferenceShot {
    @Attribute(.unique) var id: UUID
    var project: Project?
    /// UUID of the `Photo` to overlay on the live camera preview.
    var photoID: UUID

    init(id: UUID = UUID(), project: Project? = nil, photoID: UUID) {
        self.id = id
        self.project = project
        self.photoID = photoID
    }
}
