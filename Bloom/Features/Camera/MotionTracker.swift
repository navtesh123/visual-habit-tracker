import Foundation
import CoreMotion

/// Records device attitude (pitch / roll / yaw) for capture-time metadata (PRD §3.3).
///
/// Plain class — not ObservableObject — because pitch/roll/yaw are only read at
/// shutter-tap time, not used for live UI rendering. Removing the @Published
/// wrappers eliminates objectWillChange notifications that were causing CameraView
/// to re-evaluate its body on every threshold crossing.
@MainActor
final class MotionTracker {
    private(set) var pitch: Double = 0
    private(set) var roll: Double = 0
    private(set) var yaw: Double = 0

    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    /// Smallest delta (radians) that justifies hopping back to the main
    /// actor. ~0.5° — well below what the user can perceive in the level
    /// indicator and capture metadata, but coarse enough to avoid a flood
    /// of `Task { @MainActor in }` spawns per second while the phone is
    /// held reasonably still. These trackers are only ever read/written
    /// from the serial CoreMotion queue, so no synchronization is needed.
    private static let publishThresholdRadians: Double = 0.009
    nonisolated(unsafe) private var lastSampledPitch: Double = .infinity
    nonisolated(unsafe) private var lastSampledRoll: Double = .infinity
    nonisolated(unsafe) private var lastSampledYaw: Double = .infinity

    init() {
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        // 15 Hz is plenty for capture-time metadata and halves the main
        // actor churn that contributed to UIKit gesture-gate timeouts in
        // the Camera screen.
        manager.deviceMotionUpdateInterval = 1.0 / 15.0
        let threshold = Self.publishThresholdRadians
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let p = motion.attitude.pitch
            let r = motion.attitude.roll
            let y = motion.attitude.yaw
            let pitchChanged = abs(p - self.lastSampledPitch) >= threshold
            let rollChanged = abs(r - self.lastSampledRoll) >= threshold
            let yawChanged = abs(y - self.lastSampledYaw) >= threshold
            guard pitchChanged || rollChanged || yawChanged else { return }
            self.lastSampledPitch = p
            self.lastSampledRoll = r
            self.lastSampledYaw = y
            Task { @MainActor [weak self] in
                self?.pitch = p
                self?.roll = r
                self?.yaw = y
            }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
    }

}
