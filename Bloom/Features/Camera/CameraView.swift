import SwiftUI
import AVFoundation
import UIKit

/// The critical screen (PRD §3.3). Stacks, bottom-to-top:
/// 1. Live `CameraPreview` (content layer, full-bleed).
/// 2. Rule-of-thirds grid.
/// 3. Glass control strip (FAB-style shutter, timer).
struct CameraView: View {
    let project: Project

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    /// Reuse the process-wide camera session so re-entries (and the very
    /// first capture after install) share one configured AVFoundation stack
    /// instead of constructing a fresh session for every camera entry.
    @ObservedObject private var session = CameraSession.shared
    @State private var motion = MotionTracker()
    @State private var viewModel: CameraViewModel
    @State private var didPresentReview: Bool = false
    private let referencePhoto: Photo?

    init(project: Project) {
        self.project = project
        self.referencePhoto = project.overlayReferencePhoto
        _viewModel = State(initialValue: CameraViewModel(
            referencePhoto: project.overlayReferencePhoto
        ))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: session.session)
                .ignoresSafeArea()

            GhostOverlayView(referencePhoto: referencePhoto)

            RuleOfThirdsGrid()
                .ignoresSafeArea()

            VStack {
                topBar
                Spacer()
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
            if case .failed(let error) = session.status {
                cameraFailed(error)
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .navigationBarBackButtonHidden(true)
        .task {
            await session.requestAuthorization()
            if case .denied = session.status {
                viewModel.permissionDenied = true
                return
            }
            await session.configure()
            guard case .ready = session.status else { return }
            session.start()
            motion.start()
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
            } onDiscard: {
                dismiss()
            }
        }
        .alert("Camera capture failed", isPresented: captureErrorBinding) {
            Button("OK", role: .cancel) { viewModel.captureErrorMessage = nil }
        } message: {
            Text(viewModel.captureErrorMessage ?? "Please try again.")
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
                } else if referencePhoto != nil {
                    Text("Reference overlay")
                        .bodyStyle(11, weight: .medium)
                        .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.7))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassControl()

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                timerChip
                Spacer()
                shutterButton
                Spacer()
                Color.clear.frame(width: 56, height: 56)
            }
        }
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
        .buttonStyle(GlassButtonStyle())
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

    private var captureErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.captureErrorMessage != nil },
            set: { isPresented in
                if !isPresented { viewModel.captureErrorMessage = nil }
            }
        )
    }

    // MARK: - Camera failed state

    private func cameraFailed(_ error: Error) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "camera.fill.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.85))
            Text("Camera unavailable")
                .displayStyle(28)
                .foregroundStyle(NeonPlayroom.ghostWhite)
            Text(error.localizedDescription)
                .bodyStyle(13)
                .multilineTextAlignment(.center)
                .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.6))
                .padding(.horizontal, 32)
            Button("Go back") { dismiss() }
                .bodyStyle(15, weight: .semibold)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .foregroundStyle(NeonPlayroom.midnightAbyss)
                .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
                .buttonStyle(.plain)
        }
        .padding(28)
        .background(NeonPlayroom.midnightAbyss.opacity(0.85), in: AppShape.card)
        .padding(.horizontal, 24)
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
