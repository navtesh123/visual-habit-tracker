import SwiftUI

/// The most important feature in the app (PRD §3.3).
///
/// Renders the previous (or chosen reference) photo as a semi-transparent
/// overlay above the live preview so the user can physically align the
/// current pose/framing to match.
struct GhostOverlayView: View {
    let image: UIImage?
    let opacity: Double

    var body: some View {
        if let image, opacity > 0 {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .opacity(opacity)
                .allowsHitTesting(false)
                .accessibilityLabel("Previous photo overlay")
                .accessibilityHidden(true)
        }
    }
}

/// Rule-of-thirds grid drawn over the live preview to help centering (PRD §3.3).
struct RuleOfThirdsGrid: View {
    var lineColor: Color = NeonPlayroom.ghostWhite.opacity(0.35)
    var lineWidth: CGFloat = 0.5

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            Path { path in
                // Vertical thirds
                path.move(to: CGPoint(x: w / 3, y: 0))
                path.addLine(to: CGPoint(x: w / 3, y: h))
                path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                // Horizontal thirds
                path.move(to: CGPoint(x: 0, y: h / 3))
                path.addLine(to: CGPoint(x: w, y: h / 3))
                path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
            }
            .stroke(lineColor, lineWidth: lineWidth)
        }
        .allowsHitTesting(false)
    }
}
