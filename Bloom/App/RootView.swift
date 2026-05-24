import SwiftUI
import SwiftData

/// Root navigation surface. Single-stack for v1 — Home is the only
/// top-level destination; everything else is pushed or sheet-presented.
///
/// `OnboardingView` is hosted by `BloomApp` rather than this view so it
/// can render before the SwiftData container is ready on first launch.
struct RootView: View {
    @Environment(\.modelContext) private var context

    /// Owned by `BloomApp` so onboarding completion (which lives outside
    /// this view) can flip the bit that opens the project editor sheet
    /// over the freshly-mounted Home screen.
    @Binding var openFirstProjectEditor: Bool

    @State private var firstCaptureProject: Project?
    @State private var reduceTransparency: Bool = UIAccessibility.isReduceTransparencyEnabled
    @State private var reduceMotion: Bool = UIAccessibility.isReduceMotionEnabled

    var body: some View {
        NavigationStack {
            HomeView()
                .navigationDestination(item: $firstCaptureProject) { project in
                    CameraView(project: project)
                }
        }
        .background(NeonPlayroom.midnightAbyss.ignoresSafeArea())
        .fontDesign(.rounded)
        .environment(\.reduceTransparencyEnabled, reduceTransparency)
        .environment(\.reduceMotionEnabled, reduceMotion)
        .sheet(isPresented: $openFirstProjectEditor) {
            ProjectEditorView(
                mode: .create,
                suggestedName: "My first project",
                submitLabel: "Start capture"
            ) { project in
                openFirstProjectEditor = false
                firstCaptureProject = project
            }
        }
        .onChange(of: firstCaptureProject) { _, project in
            if project != nil {
                CameraSession.shared.beginCapturePath()
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
        .task(priority: .utility) {
            // Defer reminder resync past first paint. The system calls
            // (`pendingNotificationRequests`, `notificationSettings`, `add`)
            // can stall otherwise. ReminderScheduler short-circuits when
            // the project list hasn't changed since the last launch, so
            // this is essentially free in steady state.
            try? await Task.sleep(for: .milliseconds(800))
            let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            await ReminderScheduler.shared.resync(allProjects: projects)
        }
    }
}
