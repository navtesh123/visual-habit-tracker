import SwiftUI
import SwiftData

/// Root navigation surface. Single-stack for v1 — Home is the only
/// top-level destination; everything else is pushed or sheet-presented.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @State private var reduceTransparency: Bool = UIAccessibility.isReduceTransparencyEnabled
    @State private var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled
    @AppStorage(AppSettings.Key.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false
    @State private var creatingFirstProject: Bool = false

    var body: some View {
        ZStack {
            NavigationStack {
                HomeView()
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
        .background(NeonPlayroom.midnightAbyss.ignoresSafeArea())
        .fontDesign(.rounded)
        .environment(\.reduceTransparencyEnabled, reduceTransparency)
        .environment(\.reduceMotionEnabled, reduceMotion)
        .animation(.easeInOut(duration: 0.2), value: hasCompletedOnboarding)
        .sheet(isPresented: $creatingFirstProject) {
            ProjectEditorView(mode: .create) { _ in
                creatingFirstProject = false
            }
        }
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
        }
    }
}
