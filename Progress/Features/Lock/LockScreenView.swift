// PRD §5.3 — Face ID lock screen. Full-bleed Midnight Abyss with a Lime
// Squeeze pill CTA. Critically: no app content is visible behind this
// view, so even a debugger snapshot doesn't leak photos.

import SwiftUI

struct LockScreenView: View {
    @Bindable var controller: AppLockController

    var body: some View {
        ZStack {
            NeonPlayroom.midnightAbyss
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 16) {
                    Image(systemName: iconName)
                        .font(.system(size: 64))
                        .foregroundStyle(NeonPlayroom.limeSqueeze)
                    Text("Progress is locked")
                        .displayStyle(40)
                        .foregroundStyle(NeonPlayroom.ghostWhite)
                    Text("Your photos are private. Unlock to continue.")
                        .bodyStyle(15)
                        .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }

                Spacer()

                if case .failed(let reason) = controller.state {
                    Text(reason)
                        .bodyStyle(13)
                        .foregroundStyle(NeonPlayroom.sunsetOrange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task { await controller.authenticate() }
                } label: {
                    Text("Unlock with \(controller.biometryDisplayName)")
                        .bodyStyle(17, weight: .semibold)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(NeonPlayroom.midnightAbyss)
                        .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .task {
            // Auto-prompt on appear so the user doesn't need an extra tap.
            if case .locked = controller.state {
                await controller.authenticate()
            }
        }
    }

    private var iconName: String {
        switch controller.biometryDisplayName {
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default:         return "faceid"
        }
    }
}
