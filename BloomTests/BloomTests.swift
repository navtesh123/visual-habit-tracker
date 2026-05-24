import XCTest
import SwiftData
@testable import Bloom

/// Smoke tests for the local data layer and pure helpers.
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

    // MARK: - Helpers

    @MainActor
    private func makeInMemoryContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Project.self, Photo.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
