// PRD §4.3 — the "Backup paused — iCloud full" pill on Home.
//
// Calm tone: never red, never modal, never blocks the FAB. Sits above the
// FAB region so the capture flow is always one tap away.

import SwiftUI

struct BackupStatusPill: View {
    let status: BackupStatus
    let action: () -> Void

    @Environment(\.reduceTransparencyEnabled) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .foregroundStyle(tone)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.headline)
                        .bodyStyle(13, weight: .semibold)
                        .foregroundStyle(NeonPlayroom.ghostWhite)
                    Text(status.subtitle)
                        .bodyStyle(11)
                        .foregroundStyle(NeonPlayroom.ghostWhite.opacity(0.7))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassControl()
        .accessibilityLabel(status.headline)
        .accessibilityHint(status.subtitle)
    }

    private var iconName: String {
        switch status {
        case .disabled:                       return "icloud.slash"
        case .syncing:                        return "arrow.triangle.2.circlepath.icloud"
        case .active:                         return "checkmark.icloud"
        case .paused(.quotaExceeded):         return "exclamationmark.icloud"
        case .paused(.offline):               return "icloud.slash"
        case .paused(.notSignedIn):           return "person.icloud"
        case .error:                          return "exclamationmark.icloud"
        }
    }

    private var tone: Color {
        switch status {
        case .active, .syncing: return NeonPlayroom.limeSqueeze
        case .paused:           return NeonPlayroom.goldenRod
        case .error:            return NeonPlayroom.sunsetOrange
        case .disabled:         return NeonPlayroom.ghostWhite.opacity(0.6)
        }
    }
}
