// PRD §4.3 — Manual export. A contact-sheet PNG gives the user a single,
// shareable artifact that documents the whole project at a glance.
//
// Layout: 3-column grid of thumbnails over a Neon Playroom header band
// (accent color + project name + capture-window summary). Rendered via
// `ImageRenderer` so the typography lines up exactly with the rest of the app.

import SwiftUI
import UIKit

@MainActor
enum ContactSheetRenderer {
    /// Generate a contact-sheet image. Always rendered at fixed 1080pt width;
    /// the height grows with photo count so very long projects still produce
    /// a single coherent PNG.
    static func render(
        projectName: String,
        photos: [(image: UIImage, capturedAt: Date)],
        columnsPerRow: Int = 3
    ) -> UIImage? {
        guard !photos.isEmpty else { return nil }

        let view = ContactSheet(
            projectName: projectName,
            photos: photos,
            columnsPerRow: max(1, columnsPerRow)
        )
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.uiImage
    }
}

private struct ContactSheet: View {
    let projectName: String
    let photos: [(image: UIImage, capturedAt: Date)]
    let columnsPerRow: Int

    private let canvasWidth: CGFloat = 1080
    private let outerPadding: CGFloat = 36
    private let interItemSpacing: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            header
            grid
                .padding(outerPadding)
                .background(NeonPlayroom.ghostWhite)
        }
        .frame(width: canvasWidth)
        .background(NeonPlayroom.ghostWhite)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(projectName)
                    .displayStyle(64, tracking: -1)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                Text(dateRangeText)
                    .bodyStyle(18, weight: .semibold)
                    .foregroundStyle(NeonPlayroom.midnightAbyss.opacity(0.75))
            }
            Spacer()
            Text("\(photos.count) photos")
                .bodyStyle(18, weight: .semibold)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(NeonPlayroom.midnightAbyss, in: AppShape.pill)
                .foregroundStyle(NeonPlayroom.ghostWhite)
        }
        .padding(.horizontal, outerPadding)
        .padding(.vertical, 28)
        .frame(width: canvasWidth)
        .background(NeonPlayroom.limeSqueeze)
    }

    private var grid: some View {
        let cellSize = floor(
            (canvasWidth - outerPadding * 2 - interItemSpacing * CGFloat(columnsPerRow - 1))
            / CGFloat(columnsPerRow)
        )
        let rows = stride(from: 0, to: photos.count, by: columnsPerRow).map { startIndex in
            Array(photos[startIndex..<min(startIndex + columnsPerRow, photos.count)])
        }
        return VStack(spacing: interItemSpacing) {
            ForEach(0..<rows.count, id: \.self) { row in
                HStack(spacing: interItemSpacing) {
                    ForEach(0..<rows[row].count, id: \.self) { col in
                        cell(rows[row][col], size: cellSize)
                    }
                    if rows[row].count < columnsPerRow {
                        ForEach(0..<(columnsPerRow - rows[row].count), id: \.self) { _ in
                            Color.clear.frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }

    private func cell(_ photo: (image: UIImage, capturedAt: Date), size: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()

            Text(RelativeDateFormatting.short(photo.capturedAt))
                .bodyStyle(12, weight: .semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundStyle(NeonPlayroom.ghostWhite)
                .background(NeonPlayroom.midnightAbyss.opacity(0.75), in: AppShape.pill)
                .padding(8)
        }
        .frame(width: size, height: size)
        .background(NeonPlayroom.midnightAbyss)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var dateRangeText: String {
        guard let first = photos.first?.capturedAt,
              let last = photos.last?.capturedAt
        else { return "" }
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return RelativeDateFormatting.short(first)
        }
        return "\(RelativeDateFormatting.short(first)) — \(RelativeDateFormatting.short(last))"
    }
}
