import SwiftUI
import AVFoundation
import UIKit

/// The critical screen (PRD §3.3). Stacks, bottom-to-top:
/// 1. Live `CameraPreview` (content layer, full-bleed).
/// 2. Ghost overlay of the previous photo.
/// 3. Rule-of-thirds grid.
/// 4. Bubble-level indicator with alignment target.
/// 5. Glass control strip (FAB-style shutter, timer, ghost controls).
struct CameraView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var session = CameraSession()
    @StateObject private var motion = MotionTracker()
    @State private var viewModel: CameraViewModel
    @State private var didPresentReview: Bool = false

    init(project: Project) {
        self.project = project
        _viewModel = State(initialValue: CameraViewModel(
            referencePhoto: project.overlayReferencePhoto
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: session.session)
                .ignoresSafeArea()

            if viewModel.ghostEnabled {
                GhostOverlayView(
                    image: viewModel.referenceImage,
                    opacity: viewModel.ghostOpacity
                )
                .ignoresSafeArea()
            }

            RuleOfThirdsGrid()
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
                LevelIndicator(
                    pitch: motion.pitch,
                    roll: motion.roll,
                    targetPitch: viewModel.targetPitch,
                    targetRoll: viewModel.targetRoll,
                    alignmentTolerance: 0.05
                )
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            if let n = viewModel.countdownValue {
                Text("\(n)")
                    .displayStyle(140)
                    .foregroundStyle(NeonPlayroom.limeSqueeze)
                    .shadow(radius: 0)
                    .transition(.scale.combined(with: .opacity))
            }

            if case .denied = session.status {
                permissionDenied
            }
        }
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .task {
            await session.requestAuthorization()
            if case .denied = session.status {
                viewModel.permissionDenied = true
                return
            }
            await session.configure()
            session.start()
            motion.start()
            viewModel.loadReferenceImage()
            viewModel.applyLockedZoom(to: session)
        }
        .onDisappear {
            session.stop()
            motion.stop()
        }
        .fullScreenCover(item: capturedBinding) { wrapped in
            ReviewSaveView(
                project: project,
                image: wrapped.image,
                meta: wrapped.meta
            ) { saved in
                viewModel.capturedImage = nil
                viewModel.lastCaptureMeta = nil
                if saved {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
            }
            .glassControl()
            .accessibilityLabel("Close camera")

            Spacer()

            VStack(spacing: 2) {
                Text(project.name)
                    .bodyStyle(15, weight: .semibold)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
                if let zoom = viewModel.lockedZoom {
                    Text(String(format: "Zoom %.1f×", zoom))
                        .bodyStyle(11, weight: .medium)
                        .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassControl()

            Spacer()

            Button {
                viewModel.toggleGhost()
            } label: {
                Image(systemName: viewModel.ghostEnabled ? "rectangle.stack.fill" : "rectangle.stack")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(viewModel.ghostEnabled ? NeonPlayroom.limeSqueeze : NeonPlayroom.ghostWhite)
            }
            .glassControl()
            .accessibilityLabel(viewModel.ghostEnabled ? "Hide ghost overlay" : "Show ghost overlay")
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 14) {
            if viewModel.ghostEnabled && viewModel.referenceImage != nil {
                ghostSlider
            }

            HStack(alignment: .center, spacing: 18) {
                timerChip
                Spacer()
                shutterButton
                Spacer()
                Color.clear.frame(width: 56, height: 56)
            }
        }
    }

    private var ghostSlider: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle.dotted")
                .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.75))
            Slider(value: $viewModel.ghostOpacity, in: 0.0...0.6)
                .tint(NeonPlayroom.limeSqueeze)
            Image(systemName: "rectangle.stack.fill")
                .foregroundStyle(NeonPlayroom.ghostWhite)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassControl()
    }

    private var timerChip: some View {
        Button {
            viewModel.cycleTimer()
        } label: {
            Text(viewModel.timerSeconds == 0 ? "Off" : "\(viewModel.timerSeconds)s")
                .bodyStyle(13, weight: .semibold)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: 56, height: 56)
                .foregroundStyle(NeonPlayroom.ghostWhite)
        }
        .glassControl()
        .accessibilityLabel("Self timer")
        .accessibilityValue(viewModel.timerSeconds == 0 ? "Off" : "\(viewModel.timerSeconds) seconds")
    }

    private var shutterButton: some View {
        Button {
            Task {
                await viewModel.shutterTapped(session: session, motion: motion)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(NeonPlayroom.limeSqueeze)
                    .frame(width: 72, height: 72)
                Circle()
                    .strokeBorder(NeonPlayroom.ghostWhite, lineWidth: 4)
                    .frame(width: 84, height: 84)
            }
            .padding(6)
        }
        .buttonStyle(.glass)
        .disabled(viewModel.isCapturing || session.status.isNotReady)
        .accessibilityLabel("Capture photo")
    }

    // MARK: - Captured-image bridge for fullScreenCover
    //
    // Wrapper id is keyed on `meta.capturedAt` so SwiftUI sees a stable
    // identity across re-renders — otherwise `fullScreenCover(item:)`
    // would re-present each body update.

    private struct CapturedWrapper: Identifiable {
        let id: Date
        let image: UIImage
        let meta: CaptureMeta
    }

    private var capturedBinding: Binding<CapturedWrapper?> {
        Binding(
            get: {
                guard let image = viewModel.capturedImage,
                      let meta = viewModel.lastCaptureMeta else { return nil }
                return CapturedWrapper(id: meta.capturedAt, image: image, meta: meta)
            },
            set: { newValue in
                if newValue == nil {
                    viewModel.capturedImage = nil
                    viewModel.lastCaptureMeta = nil
                }
            }
        )
    }

    // MARK: - Permission denied state

    private var permissionDenied: some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill.badge.ellipsis")
                .font(.system(size: 44))
                .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.85))
            Text("Camera access is off")
                .displayStyle(28)
                .foregroundStyle(NeonPlayroom.ghostWhite)
            Text("Bloom Tracker needs the camera to take your tracking photos. Your shots stay on this device.")
                .bodyStyle(14)
                .multilineTextAlignment(.center)
                .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.7))
                .padding(.horizontal, 32)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .bodyStyle(15, weight: .semibold)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                    .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
            }
            .buttonStyle(.plain)

            Button("Cancel") { dismiss() }
                .bodyStyle(14, weight: .medium)
                .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.7))
        }
        .padding(28)
        .background(NeonPlayroom.midnightAbyss.opacity(0.85), in: AppShape.card)
        .padding(.horizontal, 24)
    }
}

private extension CameraSession.Status {
    var isNotReady: Bool {
        if case .ready = self { return false }
        return true
    }
}
