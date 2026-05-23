import SwiftUI

/// Brand shape language (PRD §7.4).
///
/// Highly rounded cards and pill-shaped buttons. No drop shadows anywhere —
/// depth comes from color contrast and the glass material itself.
enum AppShape {
    /// Project / content card radius.
    static let cardRadius: CGFloat = 43
    /// Smaller content tile radius (thumbnails, chips).
    static let tileRadius: CGFloat = 18
    /// Chip / small token radius.
    static let chipRadius: CGFloat = 12

    static var card: RoundedRectangle {
        RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
    }

    static var tile: RoundedRectangle {
        RoundedRectangle(cornerRadius: tileRadius, style: .continuous)
    }

    static var chip: RoundedRectangle {
        RoundedRectangle(cornerRadius: chipRadius, style: .continuous)
    }

    static var pill: Capsule {
        Capsule(style: .continuous)
    }
}
