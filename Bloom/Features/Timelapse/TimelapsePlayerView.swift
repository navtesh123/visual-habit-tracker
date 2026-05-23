// PRD §3.7 — Timelapse playback. The user can hit play and watch their
// project animate from first to latest, with a speed control. Sharing
// invokes `TimelapseRenderer` to produce a real MP4 the OS share sheet
// can hand off to Photos / Messages / TikTok / etc.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct TimelapsePlayerView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.reduceMotionEnabled) private var reduceMotion

    @State private var loadedImages: [TimelapseFrame] = []
    @State private var currentIndex: Int = 0
    @State private var isPlaying: Bool = false
    @State private var speed: Double = 1.0
    @State private var ticker: Task<Void, Never>?

    @State private var isRendering: Bool = false
    @State private var sharePayload: ShareableMP4?

    private let speeds: [Double] = [0.5, 1.0, 2.0, 4.0]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            currentFrameLayer
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .task { await loadAllImages() }
        .onDisappear { ticker?.cancel() }
        .sheet(item: $sharePayload) { payload in
            VideoShareSheet(url: payload.url)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Frame display (content layer; no glass)

    @ViewBuilder
    private var currentFrameLayer: some View {
        if loadedImages.isEmpty {
            ProgressView()
                .tint(NeonPlayroom.ghostWhite)
        } else {
            let frame = loadedImages[currentIndex]
            Image(uiImage: frame.image)
                .resizable()
                .scaledToFit()
                .transition(.opacity)
                .id(currentIndex)
        }
    }

    // MARK: - Top bar (glass)

    private var topBar: some View {
        HStack {
            Button {
                ticker?.cancel()
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
            }
            .glassControl()
            .accessibilityLabel("Close timelapse")

            Spacer()

            if !loadedImages.isEmpty {
                Text(progressText)
                    .bodyStyle(13, weight: .semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
                    .glassControl()
            }

            Spacer()

            Button {
                Task { await exportAndShare() }
            } label: {
                if isRendering {
                    ProgressView()
                        .tint(NeonPlayroom.ghostWhite)
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(NeonPlayroom.ghostWhite)
                }
            }
            .glassControl()
            .disabled(isRendering || loadedImages.isEmpty)
            .accessibilityLabel("Export timelapse")
        }
    }

    // MARK: - Bottom bar (glass)

    private var bottomBar: some View {
        GlassGroup {
            HStack(spacing: 14) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 56, height: 56)
                        .foregroundStyle(NeonPlayroom.midnightAbyss)
                        .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
                }
                .buttonStyle(.plain)
                .disabled(loadedImages.count < 2)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")

                Spacer()

                speedSelector
            }
        }
    }

    private var speedSelector: some View {
        HStack(spacing: 6) {
            ForEach(speeds, id: \.self) { value in
                Button {
                    speed = value
                    if isPlaying { restartTicker() }
                    Haptics.tap(style: .light)
                } label: {
                    Text(speedLabel(for: value))
                        .bodyStyle(13, weight: .semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(
                            speed == value
                            ? NeonPlayroom.midnightAbyss
                            : NeonPlayroom.ghostWhite
                        )
                        .background(
                            speed == value
                            ? AnyShapeStyle(NeonPlayroom.limeSqueeze)
                            : AnyShapeStyle(Color.clear),
                            in: AppShape.pill
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Speed \(speedLabel(for: value))")
                .accessibilityAddTraits(speed == value ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassControl()
    }

    private func speedLabel(for value: Double) -> String {
        value == floor(value)
            ? String(format: "%.0f×", value)
            : String(format: "%.1f×", value)
    }

    private var progressText: String {
        guard !loadedImages.isEmpty else { return "" }
        return "\(currentIndex + 1) / \(loadedImages.count)"
    }

    // MARK: - Playback control

    private func togglePlayback() {
        Haptics.tap(style: .light)
        if isPlaying {
            isPlaying = false
            ticker?.cancel()
            ticker = nil
        } else {
            // If we're at the end, loop back to start so play restarts.
            if currentIndex >= loadedImages.count - 1 {
                currentIndex = 0
            }
            isPlaying = true
            restartTicker()
        }
    }

    private func restartTicker() {
        ticker?.cancel()
        ticker = Task {
            while !Task.isCancelled && isPlaying {
                let hold = max(0.05, 1.0 / max(0.1, speed))
                try? await Task.sleep(for: .seconds(hold))
                if Task.isCancelled { return }
                if currentIndex >= loadedImages.count - 1 {
                    isPlaying = false
                    return
                }
                if reduceMotion {
                    currentIndex += 1
                } else {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        currentIndex += 1
                    }
                }
            }
        }
    }

    // MARK: - Loading

    private func loadAllImages() async {
        let ordered = project.photosByDateAscending
        var collected: [TimelapseFrame] = []
        for photo in ordered {
            if let image = PhotoStore.shared.loadFullImage(photo) {
                collected.append(TimelapseFrame(image: image, capturedAt: photo.capturedAt))
            }
        }
        await MainActor.run {
            self.loadedImages = collected
            self.currentIndex = 0
        }
    }

    // MARK: - Export

    private func exportAndShare() async {
        guard !loadedImages.isEmpty else { return }
        isRendering = true
        defer { isRendering = false }
        do {
            let url = try await TimelapseRenderer.render(
                frames: loadedImages,
                speed: speed,
                projectName: project.name,
                accent: project.accentColor,
                normalize: true
            )
            await MainActor.run { sharePayload = ShareableMP4(url: url) }
        } catch {
            // Errors are surfaced silently in v1; a future iteration would
            // toast a non-blocking failure with a "try again" affordance.
            assertionFailure("Timelapse render failed: \(error)")
        }
    }
}

// MARK: - Share sheet bridge

private struct ShareableMP4: Identifiable {
    let id = UUID()
    let url: URL
}

private struct VideoShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
