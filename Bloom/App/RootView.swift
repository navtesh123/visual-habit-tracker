import SwiftUI
import SwiftData

/// Root navigation surface. Single-stack for v1 — Home is the only
/// top-level destination; everything else is pushed or sheet-presented.
///
/// PRD §3.1 / §3.8 — this layer also hosts the Onboarding gate
/// (`hasCompletedOnboarding`) and the deep-link router for
/// `bloom://capture/<projectID>` from the home-screen widget.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var reduceTransparency: Bool = UIAccessibility.isReduceTransparencyEnabled
    @State private var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled
    @State private var hasCompletedOnboarding: Bool = AppSettings.hasCompletedOnboarding
    @State private var creatingFirstProject: Bool = false

    /// Project the deep-link router resolved from `bloom://capture/<UUID>`.
    /// Set on `onOpenURL`, consumed by the navigation destination.
    @State private var deepLinkCaptureProject: Project?

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
        }
        .environment(\.reduceTransparencyEnabled, reduceTransparency)
        .environment(\.reduceMotionEnabled, reduceMotion)
        .animation(.easeInOut(duration: 0.2), value: hasCompletedOnboarding)
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
            if phase == .active {
                CloudKitBackupController.shared.refresh()
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
