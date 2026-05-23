import SwiftUI
import SwiftData

/// The payoff screen (PRD §3.6).
///
/// Picks two photos from the project (defaulting to first vs latest), lets
/// the user swap each endpoint via a date strip, and offers two compare
/// modes: slider-reveal and side-by-side.
struct CompareView: View {
    let project: Project

    @State private var mode: Mode = .slider
    @State private var leftPhoto: Photo?
    @State private var rightPhoto: Photo?
    @State private var leftImage: UIImage?
    @State private var rightImage: UIImage?
    @State private var armedEndpoint: Endpoint = .right
    @State private var sharePayload: ShareableImage?

    enum Mode: Hashable { case slider, sideBySide }
    enum Endpoint: Hashable { case left, right }

    var body: some View {
        VStack(spacing: 16) {
            modeToggle

            compareSurface
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            dateStrip

            shareButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(NeonPlayroom.midnightAbyss.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(project.name)
                    .displayStyle(20)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
            }
        }
        .onAppear(perform: loadDefaultEndpoints)
        .sheet(item: $sharePayload) { payload in
            ShareSheet(image: payload.image)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Mode toggle

    private var modeToggle: some View {
        GlassGroup {
            HStack(spacing: 0) {
                modeButton(.slider, label: "Reveal", icon: "rectangle.split.2x1")
                modeButton(.sideBySide, label: "Side by side", icon: "square.split.2x1")
            }
        }
    }

    private func modeButton(_ target: Mode, label: String, icon: String) -> some View {
        Button {
            withAnimation(.spring(duration: 0.25)) { mode = target }
            Haptics.tap(style: .light)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label)
            }
            .bodyStyle(13, weight: .semibold)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(mode == target ? NeonPlayroom.midnightAbyss : NeonPlayroom.ghostWhite)
            .background(
                mode == target
                ? AnyShapeStyle(NeonPlayroom.limeSqueeze)
                : AnyShapeStyle(Color.clear),
                in: AppShape.pill
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Compare surface

    @ViewBuilder
    private var compareSurface: some View {
        if let leftImage, let rightImage, let leftPhoto, let rightPhoto {
            switch mode {
            case .slider:
                SliderRevealView(
                    leftImage: leftImage,
                    rightImage: rightImage,
                    leftDate: leftPhoto.capturedAt,
                    rightDate: rightPhoto.capturedAt
                )
            case .sideBySide:
                SideBySideView(
                    leftImage: leftImage,
                    rightImage: rightImage,
                    leftDate: leftPhoto.capturedAt,
                    rightDate: rightPhoto.capturedAt
                )
            }
        } else {
            VStack(spacing: 12) {
                ProgressView().tint(NeonPlayroom.ghostWhite)
                Text("Loading photos")
                    .bodyStyle(14)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.6))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Date strip

    private var dateStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                endpointPill(.left)
                Spacer()
                endpointPill(.right)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(project.photosByDateAscending) { photo in
                        DateChip(
                            photo: photo,
                            isLeft: leftPhoto?.id == photo.id,
                            isRight: rightPhoto?.id == photo.id,
                            accent: project.accentColor.color
                        ) {
                            assign(photo)
                        }
                    }
                }
            }
        }
    }

    private func endpointPill(_ endpoint: Endpoint) -> some View {
        Button {
            armedEndpoint = endpoint
            Haptics.tap(style: .light)
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(armedEndpoint == endpoint ? NeonPlayroom.limeSqueeze : NeonPlayroom.ghostWhite.opacity(0.4))
                    .frame(width: 8, height: 8)
                Text(endpoint == .left ? "Before" : "After")
                    .bodyStyle(12, weight: .semibold)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .glassControl()
    }

    // MARK: - Share

    private var shareButton: some View {
        Button {
            buildShareImage()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Share this comparison")
            }
            .bodyStyle(15, weight: .semibold)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .foregroundStyle(NeonPlayroom.midnightAbyss)
            .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
        }
        .buttonStyle(.plain)
        .disabled(leftImage == nil || rightImage == nil)
        .opacity((leftImage == nil || rightImage == nil) ? 0.5 : 1)
    }

    private func buildShareImage() {
        guard
            let leftImage,
            let rightImage,
            let leftPhoto,
            let rightPhoto
        else { return }

        let rendered = ShareCompositionRenderer.render(
            left: leftImage,
            right: rightImage,
            leftDate: leftPhoto.capturedAt,
            rightDate: rightPhoto.capturedAt,
            accent: project.accentColor.color,
            title: project.name
        )
        guard let rendered else { return }
        sharePayload = ShareableImage(image: rendered)
    }

    // MARK: - State

    private func loadDefaultEndpoints() {
        guard
            let first = project.firstPhoto,
            let latest = project.latestPhoto,
            first.id != latest.id
        else {
            leftPhoto = project.firstPhoto
            rightPhoto = project.latestPhoto ?? project.firstPhoto
            Task { await reloadImages() }
            return
        }
        leftPhoto = first
        rightPhoto = latest
        Task { await reloadImages() }
    }

    private func assign(_ photo: Photo) {
        switch armedEndpoint {
        case .left:
            leftPhoto = photo
            armedEndpoint = .right
        case .right:
            rightPhoto = photo
            armedEndpoint = .left
        }
        Haptics.tap(style: .light)
        Task { await reloadImages() }
    }

    private func reloadImages() async {
        let leftLoaded = leftPhoto.flatMap { PhotoStore.shared.loadFullImage($0) }
        let rightLoaded = rightPhoto.flatMap { PhotoStore.shared.loadFullImage($0) }
        await MainActor.run {
            leftImage = leftLoaded
            rightImage = rightLoaded
        }
    }
}

private struct DateChip: View {
    let photo: Photo
    let isLeft: Bool
    let isRight: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    NeonPlayroom.midnightAbyss
                    if let thumb = PhotoStore.shared.loadThumb(photo) {
                        Image(uiImage: thumb)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(border, lineWidth: borderWidth)
                )

                Text(RelativeDateFormatting.short(photo.capturedAt))
                    .bodyStyle(10, weight: .medium)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
    }

    private var border: Color {
        if isLeft || isRight { return NeonPlayroom.limeSqueeze }
        return accent.opacity(0.3)
    }

    private var borderWidth: CGFloat {
        (isLeft || isRight) ? 2 : 1
    }
}

private struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
