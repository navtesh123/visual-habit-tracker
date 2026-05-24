import SwiftUI

/// Full-screen photo viewer with delete and "retake this day" actions (PRD §3.5).
struct PhotoViewerView: View {
    let project: Project
    let photo: Photo
    let onDelete: () -> Void
    let onRetake: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var fullImage: UIImage?
    @State private var deleteConfirmation: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let fullImage {
                Image(uiImage: fullImage)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().tint(NeonPlayroom.ghostWhite)
            }

            VStack {
                topBar
                Spacer()
                infoBar
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .preferredColorScheme(.dark)
        .task {
            fullImage = await PhotoStore.shared.loadFullImageAsync(photo)
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: $deleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
            }
            .glassControl()

            Spacer()

            Button {
                deleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
            }
            .glassControl()
            .accessibilityLabel("Delete photo")
        }
    }

    private var infoBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(RelativeDateFormatting.short(photo.capturedAt))
                    .bodyStyle(15, weight: .semibold)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
                Text("·")
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.5))
                Text(RelativeDateFormatting.relative(from: photo.capturedAt))
                    .bodyStyle(13, weight: .medium)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.65))
                Spacer()
                Button {
                    onRetake()
                    dismiss()
                } label: {
                    Text("Retake this day")
                        .bodyStyle(13, weight: .semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(NeonPlayroom.midnightAbyss)
                        .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
                }
                .buttonStyle(.plain)
            }

            if let note = photo.note, !note.isEmpty {
                Text(note)
                    .bodyStyle(14)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.85))
            }
        }
        .padding(14)
        .glassControl()
    }
}
