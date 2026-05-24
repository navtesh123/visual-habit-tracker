import SwiftUI
import SwiftData

@main
struct BloomApp: App {
    /// Cold-start container is built off the main actor in a Task so the
    /// SwiftUI window can present immediately and the iOS launch screen
    /// drops as soon as possible.
    ///
    /// On a fresh install the user lands in `OnboardingView` first — and
    /// onboarding doesn't need the SwiftData store. We render it
    /// immediately, in parallel with the bootstrap task, so the user sees
    /// motion within ~one frame and never waits on SQLite store creation
    /// + schema setup before seeing UI.
    @State private var container: ModelContainer?
    @State private var launchStarted: ContinuousClock.Instant = .now
    @AppStorage(AppSettings.Key.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @State private var openFirstProjectEditor: Bool = false

    var body: some Scene {
        WindowGroup {
            content
                .preferredColorScheme(.dark)
                .tint(NeonPlayroom.limeSqueeze)
                .animation(.easeOut(duration: 0.18), value: hasCompletedOnboarding)
                .animation(.easeOut(duration: 0.18), value: container == nil)
                .task(priority: .userInitiated) {
                    await bootstrapIfNeeded()
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            // Post-onboarding stack. Mounted only when we've moved past
            // the onboarding overlay, so HomeView and its @Query don't
            // run on the very first frame of a fresh install.
            if hasCompletedOnboarding {
                if let container {
                    RootView(openFirstProjectEditor: $openFirstProjectEditor)
                        .modelContainer(container)
                        .transition(.opacity)
                } else {
                    LaunchPlaceholderView()
                        .transition(.opacity)
                }
            }

            // Onboarding sits above everything on first launch and runs
            // in parallel with the SwiftData bootstrap task. By the time
            // the user taps through three panels + permission prompts
            // the container is virtually always already resolved.
            if !hasCompletedOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
                    openFirstProjectEditor = true
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
    }

    private func bootstrapIfNeeded() async {
        guard container == nil else { return }
        let started = launchStarted
        let resolved = await CloudKitBackupController.bootstrap()
        let elapsedMs = Int(started.duration(to: .now).milliseconds)
        launchLogger.info("Container ready, \(elapsedMs, privacy: .public)ms after launch")
        container = resolved
    }
}
