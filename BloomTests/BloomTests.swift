import XCTest
@testable import Bloom

/// Smoke tests for the M0–M5 data layer plus the pure-Swift surface of
/// the deferred milestones (M6–M13). Anything that requires the iOS
/// simulator runtime (CloudKit, UserNotifications, AVAssetWriter, Vision)
/// is exercised at unit-test level via its pure-math seams only.
final class BloomTests: XCTestCase {

    // MARK: - Existing M0–M5 smoke tests

    func testProjectCreatesWithStableUUID() {
        let project = Project(name: "Bicep")
        XCTAssertEqual(project.name, "Bicep")
        XCTAssertEqual(project.subjectType, .object)
        XCTAssertEqual(project.cadence, .weekly)
        XCTAssertEqual(project.accentColor, AccentToken.default)
        XCTAssertFalse(project.id.uuidString.isEmpty)
    }

    func testCadenceGapThresholds() {
        XCTAssertEqual(Cadence.daily.expectedIntervalDays, 1)
        XCTAssertEqual(Cadence.weekly.expectedIntervalDays, 7)
        XCTAssertEqual(Cadence.daily.gapThresholdDays, 3)
        XCTAssertNil(Cadence.custom.expectedIntervalDays)
    }

    func testAccentTokenRoundTrip() {
        for token in AccentToken.allCases {
            let raw = token.rawValue
            XCTAssertEqual(AccentToken(rawValue: raw), token)
        }
    }

    func testProjectIsBehindCadenceFalseWhenNoPhotos() {
        let project = Project(name: "Plant", cadence: .weekly)
        XCTAssertFalse(project.isBehindCadence)
        XCTAssertNil(project.daysSinceLastCapture)
    }

    // MARK: - M8 reminder habit copy

    func testReminderHabitRoundTrip() {
        for habit in ReminderHabit.allCases {
            XCTAssertEqual(ReminderHabit(rawValue: habit.rawValue), habit)
        }
    }

    func testReminderHabitBodyAlwaysInterpolatesName() {
        for habit in ReminderHabit.allCases {
            let body = habit.notificationBody(for: "Left bicep")
            XCTAssertTrue(
                body.contains("Left bicep"),
                "habit body for \(habit) should mention the project name"
            )
        }
    }

    func testProjectDefaultsReminderHabitToCustom() {
        let project = Project(name: "Plant")
        XCTAssertEqual(project.reminderHabit, .custom)
    }

    func testProjectStoresReminderHabit() {
        let project = Project(name: "Plant", reminderHabit: .afterCoffee)
        XCTAssertEqual(project.reminderHabit, .afterCoffee)
    }

    // MARK: - M8 cumulative-this-month chip

    func testCumulativeThisMonthIsZeroWithNoPhotos() {
        let project = Project(name: "Plant")
        XCTAssertEqual(project.cumulativeThisMonth, 0)
    }

    // MARK: - M10 ProjectExporter helpers

    func testProjectExporterSafeNameSlugifies() {
        XCTAssertEqual(ProjectExporter.safeName("Left Bicep"), "Left-Bicep")
        XCTAssertEqual(ProjectExporter.safeName("  Spaces  "), "Spaces")
        XCTAssertEqual(ProjectExporter.safeName("Punc!@#tuation"), "Punc-tuation")
        XCTAssertEqual(ProjectExporter.safeName(""), "Project")
        XCTAssertEqual(ProjectExporter.safeName("!!!"), "Project")
    }

    func testProjectExporterScratchURLLandsInTemporary() {
        let url = ProjectExporter.scratchURL(suggestedName: "demo.png")
        XCTAssertEqual(url.lastPathComponent, "demo.png")
        XCTAssertTrue(
            url.path.hasPrefix(FileManager.default.temporaryDirectory.path),
            "exports should always live in the temporary directory"
        )
    }

    func testProjectExporterTimestampIsStableISODay() {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 UTC
        let stamp = ProjectExporter.formattedFilenameTimestamp(date)
        XCTAssertEqual(stamp.count, "2023-11-14".count)
        XCTAssertTrue(stamp.contains("-"))
    }

    // MARK: - M13 AutoAlignProcessor math

    func testAutoAlignIsIdentityWhenLandmarksMatch() {
        let landmarks = AutoAlignProcessor.LandmarkSet(
            centroid: CGPoint(x: 100, y: 200),
            axisAngleRadians: 0.1
        )
        let alignment = AutoAlignProcessor.computeAlignment(
            candidate: landmarks, reference: landmarks
        )
        XCTAssertEqual(alignment.translation.width, 0, accuracy: 1e-6)
        XCTAssertEqual(alignment.translation.height, 0, accuracy: 1e-6)
        XCTAssertEqual(alignment.rotationRadians, 0, accuracy: 1e-6)
    }

    func testAutoAlignTranslationAndRotation() {
        let candidate = AutoAlignProcessor.LandmarkSet(
            centroid: CGPoint(x: 10, y: 20), axisAngleRadians: 0
        )
        let reference = AutoAlignProcessor.LandmarkSet(
            centroid: CGPoint(x: 30, y: 60), axisAngleRadians: .pi / 4
        )
        let alignment = AutoAlignProcessor.computeAlignment(
            candidate: candidate, reference: reference
        )
        XCTAssertEqual(alignment.translation.width, 20, accuracy: 1e-6)
        XCTAssertEqual(alignment.translation.height, 40, accuracy: 1e-6)
        XCTAssertEqual(alignment.rotationRadians, .pi / 4, accuracy: 1e-6)
    }

    // MARK: - M9 widget snapshot type

    func testWidgetSnapshotRoundTripsThroughCodable() throws {
        let snapshot = WidgetSnapshot(
            schema: WidgetSnapshot.currentSchema,
            projectID: UUID(),
            projectName: "Beard",
            accentTokenRaw: AccentToken.sunsetOrange.rawValue,
            photoCount: 7,
            lastCaptureAt: Date(timeIntervalSince1970: 1_700_000_000),
            cumulativeThisMonth: 3,
            latestPhotoJPEGRelativePath: "widget-latest.jpg"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testWidgetCaptureURLEmbedsProjectID() {
        let id = UUID()
        let url = WidgetSharedConstants.captureURL(for: id)
        XCTAssertEqual(url.scheme, "bloom")
        XCTAssertEqual(url.host, "capture")
        XCTAssertTrue(url.path.contains(id.uuidString))
    }

    func testWidgetCaptureURLWithoutProjectID() {
        let url = WidgetSharedConstants.captureURL(for: nil)
        XCTAssertEqual(url.scheme, "bloom")
        XCTAssertEqual(url.host, "capture")
    }

    // MARK: - M7 BackupStatus copy semantics

    func testBackupStatusOKReflectsActiveStates() {
        XCTAssertTrue(BackupStatus.active(lastSynced: nil).isOK)
        XCTAssertTrue(BackupStatus.syncing.isOK)
        XCTAssertFalse(BackupStatus.disabled.isOK)
        XCTAssertFalse(BackupStatus.paused(reason: .quotaExceeded).isOK)
        XCTAssertFalse(BackupStatus.error(message: "oops").isOK)
    }

    func testBackupQuotaCopyMentionsFull() {
        let pill = BackupStatus.paused(reason: .quotaExceeded)
        XCTAssertTrue(pill.headline.lowercased().contains("iclou"))
        XCTAssertTrue(pill.headline.lowercased().contains("full"))
    }
}
