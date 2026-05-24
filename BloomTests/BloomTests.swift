import XCTest
import SwiftData
@testable import Bloom

/// Smoke tests for the M0–M5 data layer plus the pure-Swift surface of
/// the deferred milestones (M6–M13). Anything that requires device services
/// (camera, UserNotifications, AVAssetWriter, Vision)
/// is exercised at unit-test level via its pure-math seams only.
final class BloomTests: XCTestCase {

    // MARK: - Existing M0–M5 smoke tests

    func testProjectCreatesWithStableUUID() {
        let project = Project(name: "Bicep")
        XCTAssertEqual(project.name, "Bicep")
        XCTAssertEqual(project.subjectType, .object)
        XCTAssertEqual(project.cadence, .weekly)
        XCTAssertFalse(project.id.uuidString.isEmpty)
    }

    func testCadenceGapThresholds() {
        XCTAssertEqual(Cadence.daily.expectedIntervalDays, 1)
        XCTAssertEqual(Cadence.weekly.expectedIntervalDays, 7)
        XCTAssertEqual(Cadence.daily.gapThresholdDays, 3)
        XCTAssertNil(Cadence.custom.expectedIntervalDays)
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

    // MARK: - Local service seams

    @MainActor
    func testProjectRepositoryCreatesProjectInMemory() throws {
        let context = try makeInMemoryContext()
        let repository = ProjectRepository(context: context)

        let project = try repository.createProject(
            name: "Plant",
            subjectType: .object,
            cadence: .weekly,
            reminderTime: nil,
            reminderHabit: .custom
        )

        let fetched = try context.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(fetched.map(\.id), [project.id])
        XCTAssertEqual(project.cachedPhotoCount, 0)
    }

    @MainActor
    func testProjectRepositoryInsertsPhotoAndRefreshesSummary() throws {
        let context = try makeInMemoryContext()
        let repository = ProjectRepository(context: context)
        let project = try repository.createProject(
            name: "Plant",
            subjectType: .object,
            cadence: .weekly,
            reminderTime: nil,
            reminderHabit: .custom
        )
        let id = UUID()
        let capturedAt = Date(timeIntervalSince1970: 1_700_000_000)

        let photo = try repository.insertPhoto(
            id: id,
            project: project,
            fileRef: "Photos/project/photo.heic",
            thumbRef: "Photos/project/thumbs/photo.heic",
            meta: CaptureMeta(capturedAt: capturedAt)
        )

        XCTAssertEqual(photo.id, id)
        XCTAssertEqual(project.cachedPhotoCount, 1)
        XCTAssertEqual(project.cachedLatestPhotoID, id)
        XCTAssertEqual(project.cachedLatestPhotoCapturedAt, capturedAt)
    }

    @MainActor
    func testProjectRepositoryDeletesPhotoAndRefreshesSummary() throws {
        let context = try makeInMemoryContext()
        let repository = ProjectRepository(context: context)
        let project = try repository.createProject(
            name: "Plant",
            subjectType: .object,
            cadence: .weekly,
            reminderTime: nil,
            reminderHabit: .custom
        )
        let first = try repository.insertPhoto(
            id: UUID(),
            project: project,
            fileRef: "Photos/project/first.heic",
            thumbRef: "Photos/project/thumbs/first.heic",
            meta: CaptureMeta(capturedAt: Date(timeIntervalSince1970: 100))
        )
        let second = try repository.insertPhoto(
            id: UUID(),
            project: project,
            fileRef: "Photos/project/second.heic",
            thumbRef: "Photos/project/thumbs/second.heic",
            meta: CaptureMeta(capturedAt: Date(timeIntervalSince1970: 200))
        )

        try repository.deletePhoto(second)

        XCTAssertEqual(project.cachedPhotoCount, 1)
        XCTAssertEqual(project.cachedLatestPhotoID, first.id)
    }

    func testPhotoAssetStoreFileRefsPreserveExistingLayout() {
        let store = PhotoAssetStore(documentsURL: URL(fileURLWithPath: "/tmp/BloomTests"))
        let projectID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let photoID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

        let refs = store.fileRefs(projectID: projectID, photoID: photoID)

        XCTAssertEqual(
            refs.fileRef,
            "Photos/11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222.heic"
        )
        XCTAssertEqual(
            refs.thumbRef,
            "Photos/11111111-1111-1111-1111-111111111111/thumbs/22222222-2222-2222-2222-222222222222.heic"
        )
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

    // MARK: - Helpers

    @MainActor
    private func makeInMemoryContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self, Photo.self, ReferenceShot.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
