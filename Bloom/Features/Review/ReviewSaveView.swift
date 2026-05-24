import SwiftUI
import SwiftData

/// The confirmation gate after a capture (PRD §3.4).
///
/// Image preview (aspect-fit, rounded) in the upper portion of the screen,
/// with controls fixed at the bottom so they are always fully visible.
struct ReviewSaveView: View {
    let project: Project
    let image: UIImage
    let meta: CaptureMeta
    /// Invoked when the sheet dismisses. `true` if the photo was saved.
    let onCompletion: (Bool) -> Void
    /// Called when the user taps ✕ to discard the photo entirely and return
    /// to wherever they were before opening the camera.
    var onDiscard: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var note: String = ""
    @State private var noteFieldVisible: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 12)

            previewStack
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 16)

            Spacer(minLength: 12)

            VStack(spacing: 10) {
                if noteFieldVisible {
                    noteField
                }
                bottomBar
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .alert("Bloom could not save this photo", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var previewStack: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
    }

    private var topBar: some View {
        HStack {
            Spacer()

            Button {
                onDiscard?()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 40, height: 40)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
            }
            .glassControl()
            .accessibilityLabel("Discard photo")
        }
    }

    private var bottomBar: some View {
        GlassGroup {
            HStack(spacing: 12) {
                Button {
                    onCompletion(false)
                    dismiss()
                } label: {
                    Text("Retake")
                        .bodyStyle(15, weight: .semibold)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .foregroundStyle(NeonPlayroom.ghostWhite)
                }
                .glassControl()

                Button {
                    withAnimation { noteFieldVisible.toggle() }
                } label: {
                    Image(systemName: noteFieldVisible ? "text.badge.checkmark" : "text.badge.plus")
                        .font(.headline)
                        .padding(14)
                        .foregroundStyle(NeonPlayroom.ghostWhite)
                }
                .glassControl()
                .accessibilityLabel(noteFieldVisible ? "Hide note" : "Add note")

                Spacer()

                Button {
                    save()
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(NeonPlayroom.midnightAbyss)
                        } else {
                            Image(systemName: "checkmark")
                        }
                        Text("Save")
                    }
                    .bodyStyle(15, weight: .semibold)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                    .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
    }

    private var noteField: some View {
        TextField("Optional note", text: $note, axis: .vertical)
            .bodyStyle(15)
            .lineLimit(1...3)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: AppShape.tile)
            .foregroundStyle(NeonPlayroom.ghostWhite)
            .padding(.bottom, 12)
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true

        var resolvedMeta = meta
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        resolvedMeta.note = trimmed.isEmpty ? nil : trimmed

        let imageToSave = image
        let metaToSave = resolvedMeta
        Task {
            do {
                _ = try await PhotoStore.shared.save(
                    imageToSave,
                    for: project,
                    meta: metaToSave,
                    in: context
                )
                Haptics.success()
                onCompletion(true)
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in
                if !isPresented { errorMessage = nil }
            }
        )
    }
}
