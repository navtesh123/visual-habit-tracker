import SwiftUI

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
