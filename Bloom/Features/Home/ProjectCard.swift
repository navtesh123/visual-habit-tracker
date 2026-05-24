import SwiftUI

/// One row in the Home list (PRD §3.1, §7.1).
struct ProjectCard: View {
    let project: Project
    @State private var thumbnail: UIImage?

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            coverImage
                .frame(width: 88, height: 88)
                .clipShape(AppShape.tile)

            VStack(alignment: .leading, spacing: 6) {
                Text(project.name)
                    .displayStyle(28)
                    .lineLimit(1)
                    .foregroundStyle(NeonPlayroom.ghostWhite)

                HStack(spacing: 8) {
                    Label(lastCapturedSubtitle, systemImage: "calendar")
                        .bodyStyle(13, weight: .medium)
                        .labelStyle(.titleOnly)
                        .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.6))
                    Text("·")
                        .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.4))
                    Text(photoCountText)
                        .bodyStyle(13, weight: .medium)
                        .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.6))
                }

                if project.cachedIsBehindCadence, let gap = project.cachedDaysSinceLastCapture {
                    Text("Last shot \(gap) days ago")
                        .bodyStyle(12, weight: .medium)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(NeonPlayroom.lavenderMist.opacity(0.25), in: AppShape.chip)
                        .foregroundStyle(NeonPlayroom.lavenderMist)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(NeonPlayroom.midnightAbyss, in: AppShape.card)
        .overlay(
            AppShape.card
                .strokeBorder(NeonPlayroom.limeSqueeze, lineWidth: 3)
        )
        .task(id: project.cachedLatestPhotoID) {
            await loadThumbnail()
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
        } else if project.cachedLatestPhotoCapturedAt != nil {
            ZStack {
                NeonPlayroom.limeSqueeze.opacity(0.4)
                ProgressView()
                    .tint(NeonPlayroom.ghostWhite)
            }
        } else {
            ZStack {
                NeonPlayroom.limeSqueeze.opacity(0.35)
                Image(systemName: project.subjectType.systemImage)
                    .font(.title)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.9))
            }
        }
    }

    private var lastCapturedSubtitle: String {
        guard let capturedAt = project.cachedLatestPhotoCapturedAt else { return "No photos yet" }
        return RelativeDateFormatting.relative(from: capturedAt)
    }

    private var photoCountText: String {
        let n = project.cachedPhotoCount
        return n == 1 ? "1 photo" : "\(n) photos"
    }

    private func loadThumbnail() async {
        guard let thumbRef = project.cachedLatestPhotoThumbRef else {
            thumbnail = nil
            return
        }
        thumbnail = await PhotoStore.shared.loadThumbAsync(relativePath: thumbRef)
    }
}
