import SwiftUI

/// Brand typography (PRD §7.4).
///
/// Display headline face is a dense, bold compressed sans (Bebas Neue);
/// body face is a precise neutral sans (Inter). Both have system fallbacks
/// so the app still renders cleanly until the `.ttf` files are bundled.
enum AppFont {
    private static let displayFamily = "BebasNeue-Regular"
    private static let bodyRegular = "Inter-Regular"
    private static let bodyMedium = "Inter-Medium"
    private static let bodySemibold = "Inter-SemiBold"

    /// Display / headline. Negative kerning is applied at the modifier site for compactness.
    static func display(_ size: CGFloat) -> Font {
        if UIFont(name: displayFamily, size: size) != nil {
            return .custom(displayFamily, size: size)
        }
        return .system(size: size, weight: .heavy, design: .default).width(.condensed)
    }

    static func body(_ size: CGFloat, weight: Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .regular: name = bodyRegular
        case .medium: name = bodyMedium
        case .semibold: name = bodySemibold
        }
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: weight.systemWeight)
    }

    enum Weight {
        case regular, medium, semibold
        var systemWeight: Font.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            }
        }
    }
}

extension View {
    /// Apply display-face styling with compact letter-spacing (PRD §7.4).
    func displayStyle(_ size: CGFloat, tracking: CGFloat = -0.5) -> some View {
        self.font(AppFont.display(size))
            .tracking(tracking)
    }

    /// Apply body-face styling at a given size and weight.
    func bodyStyle(_ size: CGFloat = 15, weight: AppFont.Weight = .regular) -> some View {
        self.font(AppFont.body(size, weight: weight))
    }
}
