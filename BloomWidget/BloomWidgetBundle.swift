// PRD §3.7 / M9 — widget entry point. iOS 26 widgets are declared via
// `WidgetBundle`; the bundle hosts every widget kind shipped by the
// extension. We currently ship a single medium widget for the user's
// primary project.

import WidgetKit
import SwiftUI

@main
struct BloomWidgetBundle: WidgetBundle {
    var body: some Widget {
        BloomWidget()
    }
}
