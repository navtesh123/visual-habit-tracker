import SwiftUI

/// Side-by-side compare mode (PRD §3.6).
///
/// Two photos in an HStack with synced pinch-zoom + pan, so manipulating
/// either side adjusts both — the user is always comparing the same crop.
struct SideBySideView: View {
    let leftImage: UIImage
    let rightImage: UIImage
    let leftDate: Date
    let rightDate: Date

    @State private var scale: CGFloat = 1
    @State private var pendingScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var pendingOffset: CGSize = .zero

    var body: some View {
        HStack(spacing: 4) {
            pane(image: leftImage, date: leftDate)
            pane(image: rightImage, date: rightDate)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = max(1, min(4, pendingScale * value))
                }
                .onEnded { _ in
                    pendingScale = scale
                    if scale < 1.05 {
                        withAnimation(.spring(duration: 0.3)) {
                            scale = 1
                            pendingScale = 1
                            offset = .zero
                            pendingOffset = .zero
                        }
                    }
                }
        )
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    guard scale > 1 else { return }
                    offset = CGSize(
                        width: pendingOffset.width + value.translation.width,
                        height: pendingOffset.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    pendingOffset = offset
                }
        )
    }

    private func pane(image: UIImage, date: Date) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale)
                    .offset(offset)
                    .clipped()

                HStack {
                    Text(RelativeDateFormatting.short(date))
                        .bodyStyle(12, weight: .semibold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(NeonPlayroom.ghostWhite)
                        .background(NeonPlayroom.midnightAbyss.opacity(0.55), in: AppShape.pill)
                        .padding(10)
                    Spacer()
                }
            }
            .background(NeonPlayroom.midnightAbyss)
            .clipShape(AppShape.tile)
        }
    }
}
