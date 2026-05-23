import SwiftUI
import UIKit

@MainActor
@Observable
final class ExportCoordinator {
    var isExporting: Bool = false
    var lastError: String?
    var pendingShare: ExportArtifact?

    struct ExportArtifact: Identifiable {
        let id = UUID()
        let url: URL
        let label: String
    }

    func runAllProjects(_ projects: [Project]) async {
        isExporting = true
        defer { isExporting = false }
        do {
            let url = try ProjectExporter.exportAllProjectsZIP(projects: projects)
            pendingShare = ExportArtifact(url: url, label: "Bloom export")
        } catch {
            lastError = "Couldn't export — please try again."
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
