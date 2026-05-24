import SwiftUI
import SwiftData
import os

private let localLaunchLogger = Logger(subsystem: "app.bloomtracker.Bloom", category: "Launch")

@main
struct BloomApp: App {
    /// Cold-start container is built off the main actor in a Task so the
    /// SwiftUI window can present immediately.
    ///
    /// On a fresh install the user lands in `OnboardingView`, which does not
    /// need SwiftData. We delay the bootstrap for a moment in that path so first
    /// paint is not competing with SQLite/schema setup. Returning launches
    /// still bootstrap immediately because Home needs the store.
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
        let shouldFavorFirstPaint = !hasCompletedOnboarding
        if shouldFavorFirstPaint {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(150))
        }

        let started = launchStarted
        let priority: TaskPriority = shouldFavorFirstPaint ? .utility : .userInitiated
        let resolved = await Task.detached(priority: priority) {
            do {
                return try ModelContainer(for: Project.self, Photo.self)
            } catch {
                fatalError("Failed to initialize local SwiftData container: \(error)")
            }
        }.value
        let elapsedMs = Int(started.duration(to: .now).milliseconds)
        localLaunchLogger.info("Local container ready, \(elapsedMs, privacy: .public)ms after launch")
        container = resolved
    }
}

extension Duration {
    /// Approximate milliseconds for logging; not for accounting.
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1_000_000_000_000_000
    }
}
