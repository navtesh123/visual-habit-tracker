import SwiftUI
import UIKit

/// Renders the current Compare composition into a shareable image for the
/// "Share this comparison" action (PRD §3.6).
///
/// Uses `ImageRenderer` so the export carries the date labels and the
/// project's accent band — turning the share into a small piece of brand
/// real estate.
@MainActor
enum ShareCompositionRenderer {
    static func render(
        left: UIImage,
        right: UIImage,
        leftDate: Date,
        rightDate: Date,
        accent: Color,
        title: String
    ) -> UIImage? {
        let view = ShareComposition(
            leftImage: left,
            rightImage: right,
            leftDate: leftDate,
            rightDate: rightDate,
            accent: accent,
            title: title
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}

private struct ShareComposition: View {
    let leftImage: UIImage
    let rightImage: UIImage
    let leftDate: Date
    let rightDate: Date
    let accent: Color
    let title: String

    private let canvasWidth: CGFloat = 1080

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                halfPane(image: leftImage, date: leftDate)
                halfPane(image: rightImage, date: rightDate)
            }
            .frame(width: canvasWidth, height: canvasWidth)

            HStack {
                Text(title)
                    .displayStyle(54)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                Spacer()
                Text("Bloom Tracker")
                    .bodyStyle(18, weight: .semibold)
                    .foregroundStyle(NeonPlayroom.midnightAbyss.opacity(0.75))
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 32)
            .frame(width: canvasWidth)
            .background(accent)
        }
        .frame(width: canvasWidth)
    }

    private func halfPane(image: UIImage, date: Date) -> some View {
        ZStack(alignment: .topLeading) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: canvasWidth / 2 - 3, height: canvasWidth)
                .clipped()

            Text(RelativeDateFormatting.short(date))
                .bodyStyle(20, weight: .semibold)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(NeonPlayroom.ghostWhite)
                .background(NeonPlayroom.midnightAbyss.opacity(0.7), in: AppShape.pill)
                .padding(20)
        }
        .frame(width: canvasWidth / 2 - 3, height: canvasWidth)
    }
}
