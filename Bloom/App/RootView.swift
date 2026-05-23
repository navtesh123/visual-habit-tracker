import SwiftUI
import SwiftData

/// Root navigation surface. Single-stack for v1 — Home is the only
/// top-level destination; everything else is pushed or sheet-presented.
///
/// PRD §3.1 / §3.8 / §5.3 — this layer also hosts the Onboarding gate
/// (`hasCompletedOnboarding`), the Face ID lock (`AppLockController`), and
/// the deep-link router for `progress://capture/<projectID>` from the
/// home-screen widget.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var reduceTransparency: Bool = UIAccessibility.isReduceTransparencyEnabled
    @State private var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled
    @State private var hasCompletedOnboarding: Bool = AppSettings.hasCompletedOnboarding
    @State private var creatingFirstProject: Bool = false

    /// Project the deep-link router resolved from `progress://capture/<UUID>`.
    /// Set on `onOpenURL`, consumed by the navigation destination.
    @State private var deepLinkCaptureProject: Project?

    @Bindable private var lockController = AppLockController.shared

    var body: some View {
        ZStack {
            NavigationStack {
                HomeView(deepLinkCaptureProject: $deepLinkCaptureProject)
            }

            if !hasCompletedOnboarding {
                OnboardingView {
                    hasCompletedOnboarding = true
                    creatingFirstProject = true
                }
                .transition(.opacity)
                .zIndex(2)
            }

            if shouldShowLock {
                LockScreenView(controller: lockController)
                    .transition(.opacity)
                    .zIndex(3)
            }
        }
        .environment(\.reduceTransparencyEnabled, reduceTransparency)
        .environment(\.reduceMotionEnabled, reduceMotion)
        .animation(.easeInOut(duration: 0.2), value: hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.2), value: lockController.state)
        .sheet(isPresented: $creatingFirstProject) {
            ProjectEditorView(mode: .create) { _ in
                creatingFirstProject = false
            }
        }
        .onOpenURL(perform: handleDeepLink)
        .onReceive(NotificationCenter.default.publisher(
            for: UIAccessibility.reduceTransparencyStatusDidChangeNotification
        )) { _ in
            reduceTransparency = UIAccessibility.isReduceTransparencyEnabled
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIAccessibility.reduceMotionStatusDidChangeNotification
        )) { _ in
            reduceMotion = UIAccessibility.isReduceMotionEnabled
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                lockController.handleEnteredBackground()
            case .active:
                lockController.handleEnteredForeground()
                CloudKitBackupController.shared.refresh()
            @unknown default:
                break
            }
        }
        .task {
            // Re-sync notifications on launch so deleted projects don't
            // leave stale reminders firing forever.
            let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            await ReminderScheduler.shared.resync(allProjects: projects)
            WidgetSnapshotPublisher.publish(from: projects)
        }
    }

    private var shouldShowLock: Bool {
        guard hasCompletedOnboarding else { return false }
        switch lockController.state {
        case .locked, .failed: return true
        case .authenticated, .unlocked: return false
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == WidgetSharedConstants.captureURLScheme else { return }
        guard url.host == "capture" else { return }
        let components = url.pathComponents.filter { $0 != "/" }
        if let raw = components.first, let projectID = UUID(uuidString: raw) {
            let descriptor = FetchDescriptor<Project>(
                predicate: #Predicate { $0.id == projectID }
            )
            if let match = (try? context.fetch(descriptor))?.first {
                deepLinkCaptureProject = match
            }
        } else {
            // No specific project — fall through; HomeView's capture handler
            // picks the most recent.
            deepLinkCaptureProject = nil
        }
    }
}
