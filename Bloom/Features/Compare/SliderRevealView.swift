import SwiftUI

/// The "wow" moment (PRD §3.6).
///
/// Stacks the two images and lets the user wipe a draggable divider between
/// them, revealing the before/after. Date pills sit in each half so the
/// rendered share image stays self-describing.
struct SliderRevealView: View {
    let leftImage: UIImage
    let rightImage: UIImage
    let leftDate: Date
    let rightDate: Date

    @State private var dividerProgress: CGFloat = 0.5

    var body: some View {
        GeometryReader { proxy in
            let dividerX = proxy.size.width * dividerProgress

            ZStack(alignment: .leading) {
                Image(uiImage: rightImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                Image(uiImage: leftImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .mask(
                        Rectangle()
                            .frame(width: dividerX, height: proxy.size.height)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )

                VStack {
                    HStack {
                        datePill(leftDate)
                            .padding(12)
                        Spacer()
                        datePill(rightDate)
                            .padding(12)
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .top)

                divider(height: proxy.size.height, x: dividerX)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let raw = value.location.x / proxy.size.width
                                dividerProgress = max(0, min(1, raw))
                            }
                            .onEnded { _ in
                                Haptics.tap(style: .light)
                            }
                    )
            }
            .background(NeonPlayroom.midnightAbyss)
        }
        .clipShape(AppShape.tile)
    }

    private func divider(height: CGFloat, x: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(NeonPlayroom.ghostWhite)
                .frame(width: 2, height: height)

            Circle()
                .fill(NeonPlayroom.limeSqueeze)
                .frame(width: 36, height: 36)
                .overlay(
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                )
                .glassControl()
        }
        .position(x: x, y: height / 2)
    }

    private func datePill(_ date: Date) -> some View {
        Text(RelativeDateFormatting.short(date))
            .bodyStyle(12, weight: .semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(NeonPlayroom.ghostWhite)
            .background(NeonPlayroom.midnightAbyss.opacity(0.55), in: AppShape.pill)
    }
}
