import Foundation
import CoreMotion

/// Streams device attitude (pitch / roll / yaw) for the camera level indicator
/// and capture-time metadata (PRD §3.3).
@MainActor
final class MotionTracker: ObservableObject {
    @Published private(set) var pitch: Double = 0
    @Published private(set) var roll: Double = 0
    @Published private(set) var yaw: Double = 0

    private let manager = CMMotionManager()
    private let queue = OperationQueue()

    init() {
        queue.qualityOfService = .userInteractive
        queue.maxConcurrentOperationCount = 1
    }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let motion else { return }
            let p = motion.attitude.pitch
            let r = motion.attitude.roll
            let y = motion.attitude.yaw
            Task { @MainActor in
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

    /// Whether the current attitude is within `tolerance` radians of the target
    /// pitch/roll. Used to gate the "aligned" indicator in the camera view.
    func isAligned(toPitch targetPitch: Double, roll targetRoll: Double, tolerance: Double = 0.05) -> Bool {
        abs(pitch - targetPitch) < tolerance && abs(roll - targetRoll) < tolerance
    }
}
