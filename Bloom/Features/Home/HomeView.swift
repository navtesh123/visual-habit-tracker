import SwiftUI
import SwiftData

/// Home — the project list and the entry point to capture.
///
/// Layering rule (PRD §7.1): project cards are content-layer (solid brand
/// accents, no glass). The floating capture FAB and toolbar sit above them
/// using Liquid Glass.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.createdAt, order: .reverse) private var projects: [Project]

    @State private var editingProject: Project?
    @State private var creatingNew: Bool = false
    @State private var pickerPresented: Bool = false
    @State private var pendingCaptureProject: Project?
    @State private var showSettings: Bool = false

    @Bindable private var backup = CloudKitBackupController.shared

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content

            VStack(spacing: 12) {
                // PRD §4.3 — calm "Backup paused" pill above the FAB region.
                if !backup.status.isOK && backup.status != .disabled {
                    BackupStatusPill(status: backup.status) {
                        showSettings = true
                    }
                    .padding(.horizontal, 16)
                }
                Color.clear.frame(height: 0)
            }
            .frame(maxWidth: .infinity, alignment: .bottom)
            .padding(.bottom, 104)

            fab
                .padding(.trailing, 24)
                .padding(.bottom, 28)
        }
        .background(NeonPlayroom.midnightAbyss.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $creatingNew) {
            ProjectEditorView(mode: .create) { newProject in
                pendingCaptureProject = newProject
            }
        }
        .sheet(item: $editingProject) { project in
            ProjectEditorView(mode: .edit(project)) { _ in }
        }
        .sheet(isPresented: $pickerPresented) {
            ProjectPickerSheet(projects: projects) { selected in
                pendingCaptureProject = selected
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .navigationDestination(item: $pendingCaptureProject) { project in
            CameraView(project: project)
        }
        .task {
            backup.refresh()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .systemGray))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Settings")
        }
        ToolbarItem(placement: .principal) {
            Text("Bloom")
                .displayStyle(20)
                .foregroundStyle(NeonPlayroom.ghostWhite)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                creatingNew = true
            } label: {
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("New project")
        }
    }

    @ViewBuilder
    private var content: some View {
        if projects.isEmpty {
            emptyState
        } else {
            projectList
        }
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(projects) { project in
                    NavigationLink {
                        ProjectDetailView(project: project)
                    } label: {
                        ProjectCard(project: project)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            pendingCaptureProject = project
                        } label: {
                            Label("Capture now", systemImage: "camera")
                        }
                        Button {
                            editingProject = project
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            delete(project)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 120)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Track\nanything\nover time.")
                    .displayStyle(56, tracking: -1.5)
                    .lineSpacing(-4)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                    .multilineTextAlignment(.leading)

                Text("Photograph the same subject on a schedule. Watch it change.")
                    .bodyStyle(15, weight: .medium)
                    .foregroundStyle(NeonPlayroom.midnightAbyss.opacity(0.75))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(28)
            .background(NeonPlayroom.lavenderMist, in: AppShape.card)

            Button {
                creatingNew = true
            } label: {
                Text("Start your first project")
                    .bodyStyle(17, weight: .semibold)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                    .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - FAB

    private var fab: some View {
        GlassGroup {
            Button {
                handleCaptureTap()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                    .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
            }
            .buttonStyle(.glass)
            .accessibilityLabel("Capture photo")
        }
    }

    private func handleCaptureTap() {
        Haptics.tap(style: .light)
        switch projects.count {
        case 0:
            creatingNew = true
        case 1:
            pendingCaptureProject = projects.first
        default:
            pickerPresented = true
        }
    }

    private func delete(_ project: Project) {
        context.delete(project)
        try? context.save()
    }
}

/// Glass picker shown when the user taps the capture FAB with multiple projects.
private struct ProjectPickerSheet: View {
    let projects: [Project]
    let onSelect: (Project) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(projects) { project in
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                onSelect(project)
                            }
                        } label: {
                            HStack(spacing: 14) {
                                Circle()
                                    .fill(project.accentColor.color)
                                    .frame(width: 18, height: 18)
                                Text(project.name)
                                    .bodyStyle(17, weight: .medium)
                                    .foregroundStyle(NeonPlayroom.ghostWhite)
                                Spacer()
                                Image(systemName: "camera")
                                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.5))
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .background(NeonPlayroom.midnightAbyss.opacity(0.6), in: AppShape.tile)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(NeonPlayroom.midnightAbyss.ignoresSafeArea())
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

