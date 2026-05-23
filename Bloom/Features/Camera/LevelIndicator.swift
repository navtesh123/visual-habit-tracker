import SwiftUI

/// Subtle bubble-level overlay above the camera preview (PRD §3.3).
///
/// Renders a hairline crosshair plus a small bubble that drifts away from
/// center based on device pitch/roll. When a `targetPitch`/`targetRoll`
/// is provided (from the previous capture's metadata), a pill appears in
/// `Lime Squeeze` when the user has returned to the same attitude.
struct LevelIndicator: View {
    let pitch: Double
    let roll: Double
    let targetPitch: Double?
    let targetRoll: Double?
    let alignmentTolerance: Double

    /// Maximum bubble travel in points from center.
    private let travel: CGFloat = 36

    var body: some View {
        ZStack {
            // Center crosshair anchor.
            Circle()
                .strokeBorder(NeonPlayroom.ghostWhite.opacity(0.45), lineWidth: 1)
                .frame(width: 14, height: 14)

            // Drifting bubble.
            Circle()
                .fill(bubbleColor)
                .frame(width: 12, height: 12)
                .offset(bubbleOffset)
                .animation(.easeOut(duration: 0.08), value: pitch)
                .animation(.easeOut(duration: 0.08), value: roll)

            if isAligned {
                Text("Aligned")
                    .bodyStyle(11, weight: .semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                    .offset(y: 28)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(width: travel * 2 + 24, height: travel * 2 + 40)
        .animation(.easeInOut(duration: 0.18), value: isAligned)
    }

    private var bubbleOffset: CGSize {
        let dxRaw: Double
        let dyRaw: Double
        if let tp = targetPitch, let tr = targetRoll {
            dxRaw = (roll - tr)
            dyRaw = (pitch - tp)
        } else {
            dxRaw = roll
            dyRaw = pitch
        }
        // Map radians to points; ~0.5 rad ≈ full travel.
        let clampedX = max(-1, min(1, dxRaw / 0.5))
        let clampedY = max(-1, min(1, dyRaw / 0.5))
        return CGSize(width: clampedX * travel, height: clampedY * travel)
    }

    private var isAligned: Bool {
        guard let tp = targetPitch, let tr = targetRoll else { return false }
        return abs(pitch - tp) < alignmentTolerance && abs(roll - tr) < alignmentTolerance
    }

    private var bubbleColor: Color {
        isAligned ? NeonPlayroom.limeSqueeze : NeonPlayroom.ghostWhite
    }
}
