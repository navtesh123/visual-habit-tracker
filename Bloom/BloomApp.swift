import SwiftUI
import SwiftData

@main
struct BloomApp: App {
    /// SwiftData container holds Projects, Photos, and ReferenceShots.
    /// UUIDs on every model make a future CloudKit/account migration clean (PRD §4.4).
    ///
    /// PRD §4.3 — `CloudKitBackupController` owns container selection so
    /// flipping the iCloud backup toggle in Settings can swap stores at
    /// launch without a destructive teardown.
    private let backupController = CloudKitBackupController.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(NeonPlayroom.limeSqueeze)
        }
        .modelContainer(backupController.activeContainer)
    }
}
