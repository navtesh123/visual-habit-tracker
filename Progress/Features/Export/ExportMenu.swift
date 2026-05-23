// PRD §4.3 — a single shared menu lives behind both the project context-menu
// and the Settings export rows so the iCloud-independent escape hatch is
// always one tap deep. Owns the share-sheet presentation.

import SwiftUI
import UIKit

@MainActor
@Observable
final class ExportCoordinator {
    var isExporting: Bool = false
    var lastError: String?
    var pendingShare: ExportArtifact?

    enum Kind { case timelapse, contactSheet, originalsZIP, allProjectsZIP }

    struct ExportArtifact: Identifiable {
        let id = UUID()
        let url: URL
        let label: String
    }

    func run(_ kind: Kind, project: Project) async {
        isExporting = true
        defer { isExporting = false }
        do {
            let url: URL
            let label: String
            switch kind {
            case .timelapse:
                url = try await ProjectExporter.exportTimelapseMP4(for: project)
                label = "\(project.name) timelapse"
            case .contactSheet:
                url = try ProjectExporter.exportContactSheetPNG(for: project)
                label = "\(project.name) contact sheet"
            case .originalsZIP:
                url = try ProjectExporter.exportOriginalsZIP(for: project)
                label = "\(project.name) originals"
            case .allProjectsZIP:
                // Not a per-project export; callers should use `runAllProjects`.
                return
            }
            pendingShare = ExportArtifact(url: url, label: label)
        } catch {
            lastError = errorMessage(error)
        }
    }

    func runAllProjects(_ projects: [Project]) async {
        isExporting = true
        defer { isExporting = false }
        do {
            let url = try ProjectExporter.exportAllProjectsZIP(projects: projects)
            pendingShare = ExportArtifact(url: url, label: "Progress export")
        } catch {
            lastError = errorMessage(error)
        }
    }

    private func errorMessage(_ error: Error) -> String {
        switch error {
        case ProjectExporter.ExportError.noPhotos:
            return "Add at least one photo before exporting."
        default:
            return "Couldn't export — please try again."
        }
    }
}

/// Glass context-menu group injected into the project detail action bar
/// and Settings rows. Self-contained so callers can drop it in anywhere
/// the share-sheet can present.
struct ExportMenu: View {
    let project: Project
    @Bindable var coordinator: ExportCoordinator

    var body: some View {
        Menu {
            Button {
                Task { await coordinator.run(.timelapse, project: project) }
            } label: {
                Label("Timelapse video (.mp4)", systemImage: "play.rectangle")
            }
            Button {
                Task { await coordinator.run(.contactSheet, project: project) }
            } label: {
                Label("Contact sheet (.png)", systemImage: "square.grid.3x3")
            }
            Button {
                Task { await coordinator.run(.originalsZIP, project: project) }
            } label: {
                Label("Originals (.zip)", systemImage: "doc.zipper")
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
    }
}

/// Reusable share-sheet bridge consumed by `ExportCoordinator.pendingShare`.
struct ExportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
