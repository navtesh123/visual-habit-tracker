import UIKit

/// Wrapper around `UIImpactFeedbackGenerator` for short tactile cues
/// on capture, save, and compare-slider snap points.
enum Haptics {
    static func tap(style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let g = UIImpactFeedbackGenerator(style: style)
        g.prepare()
        g.impactOccurred()
    }

    static func success() {
        let g = UINotificationFeedbackGenerator()
        g.prepare()
        g.notificationOccurred(.success)
    }
}
