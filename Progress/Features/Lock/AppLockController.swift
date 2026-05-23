// PRD §5.3 — Face ID app lock. Optional toggle in Settings; when on, the
// app demands biometric auth on cold launch and on foregrounding. While
// locked, no project content is visible (the lock view is full-bleed).

import Foundation
import LocalAuthentication
import UIKit

@MainActor
@Observable
final class AppLockController {
    static let shared = AppLockController()

    enum State: Equatable {
        /// Lock is disabled in settings; the rest of the app is visible.
        case unlocked
        /// Lock is enabled and Face ID auth has succeeded for this session.
        case authenticated
        /// Lock screen is showing; awaiting biometric attempt.
        case locked
        /// Auth failed (cancelled, biometry not available, system error).
        case failed(reason: String)
    }

    private(set) var state: State

    /// Whether the device can actually perform Face ID / Touch ID. If not,
    /// the toggle in Settings stays disabled rather than silently failing.
    let biometricsAvailable: Bool
    let biometryDisplayName: String

    init() {
        let context = LAContext()
        var probeError: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &probeError)
        self.biometricsAvailable = canEvaluate

        switch context.biometryType {
        case .faceID:    self.biometryDisplayName = "Face ID"
        case .touchID:   self.biometryDisplayName = "Touch ID"
        case .opticID:   self.biometryDisplayName = "Optic ID"
        case .none:      self.biometryDisplayName = "Biometrics"
        @unknown default:self.biometryDisplayName = "Biometrics"
        }

        if AppSettings.faceIDLockEnabled && canEvaluate {
            self.state = .locked
        } else {
            self.state = .unlocked
        }
    }

    /// Call this from the SwiftUI `.task` on the lock screen, and from the
    /// user-tapped "Unlock" button as a retry path.
    func authenticate() async {
        guard biometricsAvailable else {
            // Should not happen in practice — `enable()` guards this — but
            // we fail open so the user is never locked out of their own data.
            state = .unlocked
            return
        }
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock Progress to see your photos."
            )
            if success {
                state = .authenticated
            } else {
                state = .failed(reason: "Authentication declined.")
            }
        } catch let error as LAError where error.code == .userCancel || error.code == .systemCancel || error.code == .appCancel {
            state = .locked
        } catch {
            state = .failed(reason: error.localizedDescription)
        }
    }

    /// Called from `RootView`'s app-foreground handler.
    func handleEnteredBackground() {
        guard AppSettings.faceIDLockEnabled, biometricsAvailable else { return }
        // Always lock when the app goes to the background so a quick re-open
        // doesn't bypass the prompt.
        state = .locked
    }

    func handleEnteredForeground() {
        if AppSettings.faceIDLockEnabled, biometricsAvailable {
            if case .authenticated = state { return }
            state = .locked
        } else {
            state = .unlocked
        }
    }

    // MARK: - Settings transitions

    /// Enable the lock from Settings. Requires a successful biometric
    /// challenge first — so the user can't accidentally lock themselves out
    /// if Face ID isn't actually configured on the device.
    func enableFromSettings() async -> Bool {
        guard biometricsAvailable else { return false }
        await authenticate()
        guard case .authenticated = state else { return false }
        AppSettings.faceIDLockEnabled = true
        return true
    }

    func disable() {
        AppSettings.faceIDLockEnabled = false
        state = .unlocked
    }
}
