import Foundation
import UIKit
import SwiftUI

/// Drives the Camera screen — owns transient capture state and orchestrates
/// the session, motion tracker, and self-timer (PRD §3.3).
@MainActor
@Observable
final class CameraViewModel {
    // MARK: - Outputs to the view

    var ghostOpacity: Double = 0.30
    var ghostEnabled: Bool = true
    var timerSeconds: Int = 0
    var countdownValue: Int? = nil
    var isCapturing: Bool = false
    var capturedImage: UIImage? = nil
    var lastCaptureMeta: CaptureMeta? = nil
    var permissionDenied: Bool = false

    // MARK: - Inputs

    /// Reference photo whose framing we want to match — drives both the ghost
    /// overlay and the alignment target on the level indicator.
    let referencePhoto: Photo?
    /// Decoded reference image, lazily loaded.
    var referenceImage: UIImage?

    /// Last-recorded zoom factor on the project — used as the initial zoom.
    let lockedZoom: CGFloat?

    init(referencePhoto: Photo?) {
        self.referencePhoto = referencePhoto
        self.lockedZoom = referencePhoto.flatMap { CGFloat($0.zoom ?? 1.0) }
    }

    var targetPitch: Double? { referencePhoto?.pitch }
    var targetRoll: Double? { referencePhoto?.roll }

    // MARK: - Setup hooks

    func loadReferenceImage() {
        guard let reference = referencePhoto else { return }
        referenceImage = PhotoStore.shared.loadFullImage(reference)
    }

    func applyLockedZoom(to session: CameraSession) {
        guard let lockedZoom else { return }
        session.applyZoom(lockedZoom)
    }

    // MARK: - Shutter

    func shutterTapped(session: CameraSession, motion: MotionTracker) async {
        guard !isCapturing else { return }
        Haptics.tap(style: .medium)

        if timerSeconds > 0 {
            await runCountdown(seconds: timerSeconds)
        }

        do {
            isCapturing = true
            defer { isCapturing = false }
            let image = try await session.capture()
            Haptics.success()

            let meta = CaptureMeta(
                pitch: motion.pitch,
                roll: motion.roll,
                yaw: motion.yaw,
                zoom: Double(session.currentZoom),
                capturedAt: .now,
                note: nil
            )
            capturedImage = image
            lastCaptureMeta = meta
        } catch {
            isCapturing = false
        }
    }

    func cycleTimer() {
        timerSeconds = (timerSeconds == 0) ? 3 : 0
        Haptics.tap(style: .light)
    }

    func toggleGhost() {
        ghostEnabled.toggle()
        Haptics.tap(style: .light)
    }

    private func runCountdown(seconds: Int) async {
        for remaining in stride(from: seconds, through: 1, by: -1) {
            countdownValue = remaining
            Haptics.tap(style: .light)
            try? await Task.sleep(for: .seconds(1))
        }
        countdownValue = nil
    }
}
