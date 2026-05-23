// PRD §7.4 — branded end-card frame in the project's accent color, project
// name in display font. Rendered to a single UIImage that the renderer can
// stitch onto the end of the MP4.

import SwiftUI
import UIKit

@MainActor
enum TimelapseEndCard {
    /// Build the branded end-card frame at `size`. Uses Neon Playroom tokens
    /// in the project's accent color; falls back gracefully if fonts are
    /// missing (the `AppFont` helpers already do this).
    static func render(
        projectName: String,
        accent: AccentToken,
        photoCount: Int,
        size: CGSize
    ) -> UIImage? {
        let view = EndCard(
            projectName: projectName,
            accent: accent,
            photoCount: photoCount
        )
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        return renderer.uiImage
    }
}

private struct EndCard: View {
    let projectName: String
    let accent: AccentToken
    let photoCount: Int

    var body: some View {
        ZStack {
            accent.color.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                Text(projectName)
                    .displayStyle(96, tracking: -1.5)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 40)
                Text("\(photoCount) photos · made with Progress")
                    .bodyStyle(28, weight: .semibold)
                    .foregroundStyle(NeonPlayroom.midnightAbyss.opacity(0.7))
                Spacer(minLength: 0)
            }
        }
    }
}
