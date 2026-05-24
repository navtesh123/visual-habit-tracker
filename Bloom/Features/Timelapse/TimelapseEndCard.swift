// PRD §7.4 — branded end-card frame, project name in display font.
// Rendered to a single UIImage that the renderer stitches onto the end of the MP4.

import SwiftUI
import UIKit

@MainActor
enum TimelapseEndCard {
    /// Build the branded end-card frame at `size`.
    static func render(
        projectName: String,
        photoCount: Int,
        size: CGSize
    ) -> UIImage? {
        let view = EndCard(
            projectName: projectName,
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
    let photoCount: Int

    var body: some View {
        ZStack {
            NeonPlayroom.limeSqueeze.ignoresSafeArea()
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                Text(projectName)
                    .displayStyle(96, tracking: -1.5)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 40)
                Text("\(photoCount) photos · made with Bloom Tracker")
                    .bodyStyle(28, weight: .semibold)
                    .foregroundStyle(NeonPlayroom.midnightAbyss.opacity(0.7))
                Spacer(minLength: 0)
            }
        }
    }
}
