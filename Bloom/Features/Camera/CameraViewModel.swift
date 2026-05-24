import Foundation
import UIKit

/// Drives the Camera screen — owns transient capture state and orchestrates
/// the session and self-timer (PRD §3.3).
@MainActor
@Observable
final class CameraViewModel {
    // MARK: - Outputs to the view

    var timerSeconds: Int = 0
    var countdownValue: Int? = nil
    var isCapturing: Bool = false
    var capturedImage: UIImage? = nil
    var lastCaptureMeta: CaptureMeta? = nil
    var permissionDenied: Bool = false
    var captureErrorMessage: String? = nil

    // MARK: - Shutter

    func shutterTapped(session: CameraSession) async {
        guard !isCapturing else { return }
        Haptics.tap(style: .medium)

        if timerSeconds > 0 {
            await runCountdown(seconds: timerSeconds)
        }

        do {
            captureErrorMessage = nil
            isCapturing = true
            defer { isCapturing = false }
            let image = try await session.capture()
            session.stop()
            Haptics.success()

            let meta = CaptureMeta(capturedAt: .now, note: nil)
            capturedImage = image
            lastCaptureMeta = meta
        } catch {
            isCapturing = false
            captureErrorMessage = "Bloom could not capture a photo. Please try again."
        }
    }

    func cycleTimer() {
        timerSeconds = (timerSeconds == 0) ? 3 : 0
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
