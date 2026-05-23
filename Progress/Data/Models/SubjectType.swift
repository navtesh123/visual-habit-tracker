import Foundation

/// What's being tracked. Drives capture overlay defaults and alignment hints (PRD §3.2).
enum SubjectType: String, Codable, CaseIterable, Identifiable, Sendable {
    case face
    case body
    case object
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .face: return "Face"
        case .body: return "Body"
        case .object: return "Object"
        case .other: return "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .face: return "face.smiling"
        case .body: return "figure.stand"
        case .object: return "cube"
        case .other: return "circle.dashed"
        }
    }
}
