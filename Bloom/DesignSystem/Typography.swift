import SwiftUI

/// Brand typography (PRD §7.4).
///
/// All text uses SF Pro Rounded — applied app-wide via `.fontDesign(.rounded)` in RootView.
/// Display uses black weight; body scales regular → medium → semibold.
enum AppFont {

    /// Display / headline. Black weight; negative kerning applied at the call site.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black)
    }

    static func body(_ size: CGFloat, weight: Weight = .regular) -> Font {
        .system(size: size, weight: weight.systemWeight)
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
