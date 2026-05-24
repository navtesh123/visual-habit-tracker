import SwiftUI
import SwiftData

/// Project detail — the timeline grid plus entry points to the payoff views (PRD §3.5).
struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context

    @State private var viewerPhoto: Photo?
    @State private var showCamera: Bool = false
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    grid
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 140)
            }

            actionBar
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
        }
        .background(NeonPlayroom.midnightAbyss.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(project.name)
                    .displayStyle(22)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
            }
        }
        .navigationDestination(isPresented: $showCamera) {
            CameraView(project: project)
        }
        .onChange(of: showCamera) { _, isPresented in
            // Delay prewarm until the push gesture has cleared; CameraView
            // owns `startRunning()` once it is visible.
            if isPresented {
                CameraSession.shared.beginCapturePath()
            }
        }
        .fullScreenCover(item: $viewerPhoto) { photo in
            PhotoViewerView(
                project: project,
                photo: photo,
                onDelete: { delete(photo) },
                onRetake: { showCamera = true }
            )
        }
        .alert("Bloom could not finish that action", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(NeonPlayroom.limeSqueeze)
                    .frame(width: 12, height: 12)
                Text(project.subjectType.displayName)
                    .bodyStyle(13, weight: .medium)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.7))
                Text("·")
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.4))
                Text(project.cadence.displayName)
                    .bodyStyle(13, weight: .medium)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.7))
            }

            HStack(spacing: 14) {
                statBlock(value: "\(project.photos.count)", label: "Photos")
                statBlock(value: dateRangeText, label: "Range")
                // PRD §6 — forgiving streak surface. Prefer the cumulative-
                // this-month chip when the user has captured anything this
                // month; fall back to the soft cadence-gap chip otherwise.
                if project.cumulativeThisMonth > 0 {
                    monthlyChip(count: project.cumulativeThisMonth)
                } else if project.isBehindCadence, let gap = project.daysSinceLastCapture {
                    cadenceChip(days: gap)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private func monthlyChip(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(NeonPlayroom.limeSqueeze)
            Text("\(count) \(count == 1 ? "photo" : "photos") this month")
        }
        .bodyStyle(12, weight: .semibold)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NeonPlayroom.limeSqueeze.opacity(0.18), in: AppShape.chip)
        .foregroundStyle(NeonPlayroom.ghostWhite)
    }

    private func statBlock(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .displayStyle(28)
                .foregroundStyle(NeonPlayroom.ghostWhite)
            Text(label)
                .bodyStyle(11, weight: .medium)
                .textCase(.uppercase)
                .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.5))
        }
    }

    private func cadenceChip(days: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "clock")
            Text("Last shot \(days)d ago")
        }
        .bodyStyle(12, weight: .semibold)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(NeonPlayroom.lavenderMist.opacity(0.22), in: AppShape.chip)
        .foregroundStyle(NeonPlayroom.lavenderMist)
    }

    private var dateRangeText: String {
        guard let first = project.firstPhoto, let last = project.latestPhoto else {
            return "—"
        }
        if first.id == last.id {
            return RelativeDateFormatting.short(first.capturedAt)
        }
        let days = Calendar.current.dateComponents(
            [.day], from: first.capturedAt, to: last.capturedAt
        ).day ?? 0
        return "\(days)d"
    }

    // MARK: - Grid

    @ViewBuilder
    private var grid: some View {
        if project.photos.isEmpty {
            emptyGrid
        } else {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(project.photosByDateAscending.reversed()) { photo in
                    Button {
                        viewerPhoto = photo
                    } label: {
                        PhotoThumbnail(photo: photo)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyGrid: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 44))
                .foregroundStyle(NeonPlayroom.limeSqueeze)
            Text("No photos yet")
                .displayStyle(28)
                .foregroundStyle(NeonPlayroom.ghostWhite)
            Text("Take your first shot to start this project timeline.")
                .bodyStyle(14)
                .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Action bar (glass)

    private var actionBar: some View {
        GlassGroup {
            HStack {
                Spacer()
                Button {
                    showCamera = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("Capture")
                    }
                    .bodyStyle(15, weight: .semibold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                    .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
    }

    // MARK: - Actions

    private func delete(_ photo: Photo) {
        do {
            try PhotoStore.shared.delete(photo, in: context)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented { errorMessage = nil }
            }
        )
    }
}

/// One cell in the timeline grid. Content-layer — no glass (PRD §7.1).
private struct PhotoThumbnail: View {
    let photo: Photo
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            NeonPlayroom.midnightAbyss
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .tint(NeonPlayroom.ghostWhite.opacity(0.6))
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: photo.id) {
            // Decode off the main actor — synchronous file read + HEIC
            // decode otherwise piles onto the main thread when many cells
            // come into view at once and starves UIKit's gesture gate
            // (PRD §3.5).
            image = await PhotoStore.shared.loadThumbAsync(relativePath: photo.thumbRef)
        }
    }
}
