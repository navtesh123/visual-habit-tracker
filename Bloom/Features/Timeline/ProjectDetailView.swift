import SwiftUI
import SwiftData

/// Project detail — the timeline grid plus entry points to the payoff views (PRD §3.5).
struct ProjectDetailView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var context

    @State private var viewerPhoto: Photo?
    @State private var showCamera: Bool = false
    @State private var showCompare: Bool = false
    @State private var showTimelapse: Bool = false
    @State private var showProgressToast: Bool = false
    @State private var lastSeenPhotoCount: Int = 0

    private let backup = CloudKitBackupController.shared

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

            if showProgressToast {
                progressToast
                    .padding(.bottom, 110)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
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
        .navigationDestination(isPresented: $showCompare) {
            CompareView(project: project)
        }
        .navigationDestination(isPresented: $showTimelapse) {
            TimelapsePlayerView(project: project)
        }
        .fullScreenCover(item: $viewerPhoto) { photo in
            PhotoViewerView(
                project: project,
                photo: photo,
                onDelete: { delete(photo) },
                onRetake: { showCamera = true }
            )
        }
        .onAppear {
            lastSeenPhotoCount = project.photos.count
        }
        .onChange(of: project.photos.count) { _, newCount in
            // PRD §3.4 — surface the compare payoff as soon as a second
            // photo exists, the moment we return from the camera.
            if newCount > lastSeenPhotoCount && newCount >= 2 {
                withAnimation(.spring(duration: 0.35)) {
                    showProgressToast = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { showProgressToast = false }
                }
            }
            lastSeenPhotoCount = newCount
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(project.accentColor.color)
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
                .foregroundStyle(project.accentColor.color)
            Text("\(count) \(count == 1 ? "photo" : "photos") this month")
        }
        .bodyStyle(12, weight: .semibold)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(project.accentColor.color.opacity(0.18), in: AppShape.chip)
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
                .foregroundStyle(project.accentColor.color)
            Text("No photos yet")
                .displayStyle(28)
                .foregroundStyle(NeonPlayroom.ghostWhite)
            Text("Take your first shot. The next one will line up with this one using a ghost overlay.")
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
            HStack(spacing: 12) {
                Button {
                    showCompare = true
                } label: {
                    Label("Compare", systemImage: "rectangle.split.2x1")
                        .bodyStyle(14, weight: .semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .foregroundStyle(NeonPlayroom.ghostWhite)
                }
                .glassControl()
                .disabled(project.photos.count < 2)
                .opacity(project.photos.count < 2 ? 0.5 : 1)

                Button {
                    showTimelapse = true
                } label: {
                    Label("Timelapse", systemImage: "play.rectangle")
                        .bodyStyle(14, weight: .semibold)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .foregroundStyle(
                            project.photos.count < 2
                            ? NeonPlayroom.ghostWhite.opacity(0.55)
                            : NeonPlayroom.ghostWhite
                        )
                }
                .glassControl()
                .disabled(project.photos.count < 2)
                .opacity(project.photos.count < 2 ? 0.5 : 1)

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
            }
        }
    }

    // MARK: - Toast

    private var progressToast: some View {
        Button {
            withAnimation { showProgressToast = false }
            showCompare = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(NeonPlayroom.limeSqueeze)
                VStack(alignment: .leading, spacing: 2) {
                    Text("See your progress")
                        .bodyStyle(14, weight: .semibold)
                        .foregroundStyle(NeonPlayroom.ghostWhite)
                    Text("Compare your first and latest shot")
                        .bodyStyle(12)
                        .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.65))
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
        .glassControl()
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private func delete(_ photo: Photo) {
        do {
            try PhotoStore.shared.delete(photo, in: context)
        } catch {
            assertionFailure("Failed to delete photo: \(error)")
        }
    }
}

/// One cell in the timeline grid. Content-layer — no glass (PRD §7.1).
private struct PhotoThumbnail: View {
    let photo: Photo
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
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

            // M7 — per-photo sync status. Hidden when backup is off so it
            // doesn't add visual noise for users who never opt in.
            if let badgeIcon = backupBadgeIcon {
                Image(systemName: badgeIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(4)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
                    .background(NeonPlayroom.midnightAbyss.opacity(0.65), in: Circle())
                    .padding(4)
            }
        }
        .task(id: photo.id) {
            image = PhotoStore.shared.loadThumb(photo)
        }
    }

    private var backupBadgeIcon: String? {
        let state = CloudKitBackupController.shared.syncState(for: photo)
        return state.systemImage
    }
}
