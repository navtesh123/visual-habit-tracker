import SwiftUI
import SwiftData

@main
struct BloomApp: App {
    /// Resolved once at app init so `body` never touches the @Observable
    /// CloudKitBackupController — preventing accidental re-runs of `body`
    /// that would swap the ModelContainer mid-session and flash a blank screen.
    private let container: ModelContainer = CloudKitBackupController.shared.activeContainer

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(NeonPlayroom.limeSqueeze)
        }
        .modelContainer(container)
    }
}
