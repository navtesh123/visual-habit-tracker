import SwiftUI

/// Shown for the brief window between iOS dropping the launch screen and
/// SwiftData finishing its cold-start work. Matches the launch
/// screen's dark midnight background so the handoff is visually seamless —
/// the user never sees a black flash and never perceives a frozen app.
struct LaunchPlaceholderView: View {
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            NeonPlayroom.midnightAbyss
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Text("Bloom")
                    .displayStyle(40)
                    .foregroundStyle(NeonPlayroom.ghostWhite)
                    .opacity(pulse ? 1 : 0.65)

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(NeonPlayroom.limeSqueeze)
                    .scaleEffect(0.9)
            }
        }
        .task {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
