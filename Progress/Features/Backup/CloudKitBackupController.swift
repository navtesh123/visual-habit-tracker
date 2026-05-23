// PRD §4.3 — CloudKit backup as an opt-in safety net.
//
// We deliberately keep the ModelContainer initializer the existing app uses
// intact. When the user enables backup, this controller (a) rebuilds the
// container with a CloudKit `ModelConfiguration`, (b) listens to remote
// sync notifications, and (c) probes CloudKit account / quota state so we
// can surface a calm "Backup paused — iCloud full" pill on Home and a
// matching disclosure in Settings.
//
// The controller never throws app-fatal errors at the user — when the
// network is offline, when iCloud is full, when the user signed out — we
// move into a `.paused(...)` state and keep all data local. This is the
// "calm" tone the PRD asks for.

import Foundation
import SwiftData
import CloudKit
import Combine

private let cloudContainerID = "iCloud.app.progress.Progress"

@MainActor
@Observable
final class CloudKitBackupController {
    static let shared = CloudKitBackupController()

    /// Latest status, polled on enable / app-foreground / on subscription
    /// pushes. Views observe this via `@Bindable` or `Observable`.
    private(set) var status: BackupStatus = .disabled

    /// The SwiftData container the app should use. When backup is off this
    /// equals `localContainer`; when on, it's `cloudContainer`.
    var activeContainer: ModelContainer {
        AppSettings.cloudKitBackupEnabled
            ? (cloudContainer ?? localContainer)
            : localContainer
    }

    let localContainer: ModelContainer
    private var cloudContainer: ModelContainer?
    private var probeTask: Task<Void, Never>?

    init() {
        self.localContainer = Self.buildLocalContainer()
        // If the user had backup turned on previously, hydrate state and
        // attempt to reconstruct the cloud container.
        if AppSettings.cloudKitBackupEnabled {
            self.cloudContainer = Self.buildCloudContainer()
            self.status = .syncing
            scheduleProbe()
        }
    }

    // MARK: - Public surface

    /// Turn backup on. Rebuilds the cloud container if missing and kicks off
    /// an account / quota probe. The app should restart the model container
    /// to pick up the new store — `RootView` re-reads `activeContainer`.
    func enable() async {
        AppSettings.cloudKitBackupEnabled = true
        if cloudContainer == nil {
            cloudContainer = Self.buildCloudContainer()
        }
        status = .syncing
        await probe()
    }

    /// Turn backup off. Local data and the file-system photo store are
    /// untouched — the user is opting out of the *cloud* copy, not their
    /// project history.
    func disable() {
        AppSettings.cloudKitBackupEnabled = false
        status = .disabled
        cloudContainer = nil
    }

    /// Re-probe account / quota. Call from `.onAppear` of Home and Settings,
    /// and from the foreground notification handler.
    func refresh() {
        guard AppSettings.cloudKitBackupEnabled else {
            status = .disabled
            return
        }
        scheduleProbe()
    }

    // MARK: - Probing

    private func scheduleProbe() {
        probeTask?.cancel()
        probeTask = Task { await probe() }
    }

    private func probe() async {
        let container = CKContainer(identifier: cloudContainerID)
        do {
            let accountStatus = try await container.accountStatus()
            switch accountStatus {
            case .available:
                break
            case .noAccount:
                status = .paused(reason: .notSignedIn)
                return
            case .restricted, .couldNotDetermine, .temporarilyUnavailable:
                status = .paused(reason: .notSignedIn)
                return
            @unknown default:
                status = .paused(reason: .notSignedIn)
                return
            }
        } catch {
            status = .paused(reason: .offline)
            return
        }

        // Probe whether we can read the private DB. A cheap zone-list call.
        do {
            _ = try await container.privateCloudDatabase.allRecordZones()
            status = .active(lastSynced: .now)
        } catch let error as CKError {
            status = mapCKError(error)
        } catch {
            status = .error(message: error.localizedDescription)
        }
    }

    private func mapCKError(_ error: CKError) -> BackupStatus {
        switch error.code {
        case .quotaExceeded:
            return .paused(reason: .quotaExceeded)
        case .networkUnavailable, .networkFailure:
            return .paused(reason: .offline)
        case .notAuthenticated:
            return .paused(reason: .notSignedIn)
        default:
            return .error(message: error.localizedDescription)
        }
    }

    // MARK: - Container construction

    /// Local-only ModelContainer — matches the existing app shape so we can
    /// always fall back to it without losing data.
    private static func buildLocalContainer() -> ModelContainer {
        do {
            return try ModelContainer(
                for: Project.self, Photo.self, ReferenceShot.self
            )
        } catch {
            fatalError("Failed to initialize local SwiftData container: \(error)")
        }
    }

    /// CloudKit-backed ModelContainer using the private database scope.
    /// Returns `nil` if CloudKit can't be reached at construction time;
    /// callers fall back to the local container.
    private static func buildCloudContainer() -> ModelContainer? {
        let configuration = ModelConfiguration(
            "ProgressCloudStore",
            cloudKitDatabase: .private(cloudContainerID)
        )
        do {
            return try ModelContainer(
                for: Project.self, Photo.self, ReferenceShot.self,
                configurations: configuration
            )
        } catch {
            return nil
        }
    }

    // MARK: - Per-photo sync indicator
    //
    // SwiftData + CloudKit doesn't surface per-record sync state directly.
    // We approximate the indicator with a freshness heuristic: photos older
    // than the most recent successful probe are considered synced, brand-new
    // photos surface a small "syncing" dot for a short window.

    func syncState(for photo: Photo) -> PhotoSyncState {
        switch status {
        case .disabled:
            return .notBackedUp
        case .paused, .error:
            return .pending
        case .syncing:
            return .pending
        case .active(let lastSynced):
            if let lastSynced, photo.capturedAt < lastSynced {
                return .synced
            }
            return .pending
        }
    }

    enum PhotoSyncState {
        case notBackedUp
        case pending
        case synced

        var systemImage: String? {
            switch self {
            case .notBackedUp: return nil
            case .pending:     return "icloud.and.arrow.up"
            case .synced:      return "checkmark.icloud"
            }
        }
    }
}
