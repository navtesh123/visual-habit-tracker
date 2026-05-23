import SwiftUI
import SwiftData

/// The confirmation gate after a capture (PRD §3.4).
///
/// Full-bleed view of the just-captured image with a horizontal-swipe
/// affordance to compare against the previous photo. Glass controls float
/// above: Retake, optional note, Save.
struct ReviewSaveView: View {
    let project: Project
    let image: UIImage
    let meta: CaptureMeta
    /// Invoked when the sheet dismisses. `true` if the photo was saved.
    let onCompletion: (Bool) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var swipeProgress: CGFloat = 0
    @State private var note: String = ""
    @State private var noteFieldVisible: Bool = false
    @State private var isSaving: Bool = false
    @State private var previousImage: UIImage?

    // M13 — auto-align toggle. Default off in v1 (per PRD §3.3, "v2
    // enhancement"). Only shown for face / body subjects.
    @State private var autoAlignEnabled: Bool = false
    @State private var isAligning: Bool = false
    @State private var alignedImage: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            previewStack
                .ignoresSafeArea()
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard previousImage != nil else { return }
                            let proportion = -value.translation.width / 280.0
                            swipeProgress = max(0, min(1, proportion))
                        }
                        .onEnded { _ in
                            withAnimation(.spring(duration: 0.3)) {
                                swipeProgress = swipeProgress > 0.5 ? 1 : 0
                            }
                        }
                )

            VStack {
                topBar
                Spacer()
                if showsAutoAlign {
                    autoAlignToggle
                }
                if noteFieldVisible {
                    noteField
                }
                bottomBar
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
        .task {
            if let previous = project.latestPhoto {
                previousImage = PhotoStore.shared.loadFullImage(previous)
            }
        }
    }

    private var previewStack: some View {
        ZStack {
            if let previousImage {
                Image(uiImage: previousImage)
                    .resizable()
                    .scaledToFill()
                    .opacity(Double(swipeProgress))
            }
            Image(uiImage: displayedImage)
                .resizable()
                .scaledToFill()
                .opacity(Double(1 - swipeProgress))
        }
    }

    /// The image actually shown / saved — swaps to the aligned result once
    /// the M13 processor finishes.
    private var displayedImage: UIImage {
        alignedImage ?? image
    }

    private var showsAutoAlign: Bool {
        // PRD §3.3 — only meaningful for face / body subjects, and only
        // when we have a reference photo to align to.
        guard previousImage != nil else { return false }
        return project.subjectType == .face || project.subjectType == .body
    }

    private var autoAlignToggle: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope")
                .foregroundStyle(NeonPlayroom.limeSqueeze)
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-align to reference")
                    .bodyStyle(13, weight: .semibold)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
                Text("Beta — for face / body subjects")
                    .bodyStyle(11)
                    .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.65))
            }
            Spacer()
            if isAligning {
                ProgressView()
                    .tint(NeonPlayroom.ghostWhite)
            } else {
                Toggle("", isOn: $autoAlignEnabled)
                    .labelsHidden()
                    .tint(NeonPlayroom.limeSqueeze)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassControl()
        .padding(.bottom, 8)
        .onChange(of: autoAlignEnabled) { _, isOn in
            if isOn {
                runAutoAlign()
            } else {
                alignedImage = nil
            }
        }
    }

    private func runAutoAlign() {
        guard let reference = previousImage else { return }
        guard !isAligning else { return }
        isAligning = true
        let candidate = image
        let subject = project.subjectType
        Task {
            do {
                let aligned = try await AutoAlignProcessor.align(
                    candidate: candidate,
                    reference: reference,
                    subjectType: subject
                )
                await MainActor.run {
                    alignedImage = aligned
                    isAligning = false
                }
            } catch {
                await MainActor.run {
                    isAligning = false
                    autoAlignEnabled = false
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            if previousImage != nil {
                Text(swipeProgress > 0.5 ? "Previous" : "Just now")
                    .bodyStyle(13, weight: .semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
                    .glassControl()
            }
            Spacer()
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

        do {
            _ = try PhotoStore.shared.save(displayedImage, for: project, meta: resolvedMeta, in: context)
            Haptics.success()
            // Republish widget snapshot so the home-screen tile reflects
            // the brand-new photo without waiting for the next timeline tick.
            let allProjects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
            WidgetSnapshotPublisher.publish(from: allProjects)
            onCompletion(true)
            dismiss()
        } catch {
            isSaving = false
        }
    }
}
