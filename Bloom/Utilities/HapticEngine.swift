import UIKit

/// Wrapper around `UIImpactFeedbackGenerator` for short tactile cues
/// on capture, save, and small control changes.
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
