// PRD §3.1 / M12 — first-launch flow. Three panels: value, privacy posture
// (in-context camera permission), notification opt-in. Closes by presenting
// `ProjectEditorView` with a friendly default name so the user lands in a
// real, ready-to-use spot rather than an empty list.
//
// Each panel is a single Neon Playroom block + display headline + CTA pill,
// matching the design language used for the empty-state on Home.

import SwiftUI
import AVFoundation

struct OnboardingView: View {
    /// Invoked once the user finishes the flow. Parent (RootView) flips the
    /// `hasCompletedOnboarding` UserDefault and presents the project editor.
    let onComplete: () -> Void

    @State private var pageIndex: Int = 0
    @State private var cameraGranted: Bool? = nil
    @State private var notificationsGranted: Bool? = nil

    private let totalPages = 3

    var body: some View {
        ZStack {
            background.ignoresSafeArea()

            VStack(spacing: 0) {
                pages
                pagerDots
                bottomCTA
            }
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private var pages: some View {
        TabView(selection: $pageIndex) {
            valuePage
                .tag(0)
            privacyPage
                .tag(1)
            notificationsPage
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var valuePage: some View {
        OnboardingPanel(
            backdrop: NeonPlayroom.lavenderMist,
            headline: "Track\nanything\nover time.",
            subhead: "Photograph the same subject on a schedule. Watch real change emerge."
        )
    }

    private var privacyPage: some View {
        OnboardingPanel(
            backdrop: NeonPlayroom.limeSqueeze,
            headline: "Your photos\nstay on\nthis phone.",
            subhead: "Bloom Tracker doesn't add anything to your camera roll. iCloud backup is opt-in.",
            actionLabel: cameraGranted == nil ? "Allow camera access" : "Camera access ready",
            actionDisabled: cameraGranted == true,
            action: requestCamera
        )
    }

    private var notificationsPage: some View {
        OnboardingPanel(
            backdrop: NeonPlayroom.amethystGlow,
            headline: "Gentle\nreminders.\nNo pressure.",
            subhead: "Choose a habit-stacked nudge, like \"after coffee\". Skip a day with no guilt.",
            actionLabel: notificationsGranted == nil
                ? "Allow notifications"
                : (notificationsGranted == true ? "Reminders ready" : "Skipped — change later in Settings"),
            actionDisabled: notificationsGranted != nil,
            action: requestNotifications
        )
    }

    // MARK: - Bottom

    private var background: Color {
        switch pageIndex {
        case 0: return NeonPlayroom.lavenderMist
        case 1: return NeonPlayroom.limeSqueeze
        default: return NeonPlayroom.amethystGlow
        }
    }

    private var pagerDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == pageIndex
                          ? NeonPlayroom.midnightAbyss
                          : NeonPlayroom.midnightAbyss.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.top, 12)
    }

    private var bottomCTA: some View {
        VStack(spacing: 8) {
            Button {
                advance()
            } label: {
                Text(pageIndex == totalPages - 1 ? "Start tracking" : "Continue")
                    .bodyStyle(17, weight: .semibold)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                    .background(NeonPlayroom.limeSqueeze, in: AppShape.pill)
            }
            .buttonStyle(.plain)
            .opacity(pageIndex == 1 && cameraGranted == nil ? 0.45 : 1)
            .disabled(pageIndex == 1 && cameraGranted == nil)

            if pageIndex < totalPages - 1 {
                Button("Skip") {
                    finish()
                }
                .bodyStyle(14, weight: .medium)
                .foregroundStyle(NeonPlayroom.midnightAbyss.opacity(0.6))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 36)
        .padding(.top, 18)
    }

    // MARK: - Actions

    private func advance() {
        if pageIndex < totalPages - 1 {
            withAnimation(.spring(duration: 0.3)) { pageIndex += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        AppSettings.hasCompletedOnboarding = true
        onComplete()
    }

    private func requestCamera() {
        Task {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .authorized:
                cameraGranted = true
            case .notDetermined:
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                cameraGranted = granted
            case .denied, .restricted:
                cameraGranted = false
            @unknown default:
                cameraGranted = false
            }

            // If the user granted access, eagerly pre-warm the camera
            // session in the background. They'll likely spend a few
            // seconds finishing onboarding and creating a project before
            // the first capture tap — plenty of head-room for AVFoundation
            // device discovery and input/output wiring to complete off
            // the main thread.
            if cameraGranted == true {
                Task.detached(priority: .background) {
                    await CameraSession.shared.prewarm()
                }
            }
        }
    }

    private func requestNotifications() {
        Task {
            let granted = await ReminderScheduler.shared.requestAuthorizationIfNeeded()
            notificationsGranted = granted
        }
    }
}

private struct OnboardingPanel: View {
    let backdrop: Color
    let headline: String
    let subhead: String
    var actionLabel: String? = nil
    var actionDisabled: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)
            Text(headline)
                .displayStyle(64, tracking: -1.5)
                .foregroundStyle(NeonPlayroom.midnightAbyss)
                .multilineTextAlignment(.leading)

            Text(subhead)
                .bodyStyle(17, weight: .medium)
                .foregroundStyle(NeonPlayroom.midnightAbyss.opacity(0.75))

            if let actionLabel, let action {
                Button {
                    action()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: actionDisabled ? "checkmark" : "lock.open")
                        Text(actionLabel)
                    }
                    .bodyStyle(15, weight: .semibold)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .foregroundStyle(NeonPlayroom.midnightAbyss)
                    .background(NeonPlayroom.ghostWhite, in: AppShape.pill)
                }
                .buttonStyle(.plain)
                .opacity(actionDisabled ? 0.7 : 1)
                .padding(.top, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(backdrop)
    }
}
