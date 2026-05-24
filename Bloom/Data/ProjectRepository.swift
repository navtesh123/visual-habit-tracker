import Foundation
import SwiftData

/// Main-actor SwiftData write boundary for project/photo mutations.
@MainActor
struct ProjectRepository {
    enum RepositoryError: LocalizedError {
        case saveFailed(Error)
        case deleteFailed(Error)

        var errorDescription: String? {
            switch self {
            case .saveFailed:
                return "Bloom could not save your changes."
            case .deleteFailed:
                return "Bloom could not delete that item."
            }
        }
    }

    let context: ModelContext

    @discardableResult
    func createProject(
        name: String,
        subjectType: SubjectType,
        cadence: Cadence,
        reminderTime: Date?,
        reminderHabit: ReminderHabit
    ) throws -> Project {
        let project = Project(
            name: name,
            subjectType: subjectType,
            cadence: cadence,
            reminderTime: reminderTime,
            reminderHabit: reminderHabit
        )
        context.insert(project)
        do {
            try context.save()
            return project
        } catch {
            throw RepositoryError.saveFailed(error)
        }
    }

    func updateProject(
        _ project: Project,
        name: String,
        subjectType: SubjectType,
        cadence: Cadence,
        reminderTime: Date?,
        reminderHabit: ReminderHabit
    ) throws {
        project.name = name
        project.subjectType = subjectType
        project.cadence = cadence
        project.reminderTime = reminderTime
        project.reminderHabit = reminderHabit
        do {
            try context.save()
        } catch {
            throw RepositoryError.saveFailed(error)
        }
    }

    @discardableResult
    func insertPhoto(
        id: UUID,
        project: Project,
        fileRef: String,
        thumbRef: String,
        meta: CaptureMeta
    ) throws -> Photo {
        let photo = Photo(
            id: id,
            project: project,
            fileRef: fileRef,
            thumbRef: thumbRef,
            capturedAt: meta.capturedAt,
            note: meta.note
        )
        context.insert(photo)
        var photos = project.photos.filter { $0.id != photo.id }
        photos.append(photo)
        project.refreshPhotoSummary(from: photos)
        do {
            try context.save()
            return photo
        } catch {
            throw RepositoryError.saveFailed(error)
        }
    }

    func deletePhoto(_ photo: Photo) throws {
        let project = photo.project
        let remainingPhotos = project?.photos.filter { $0.id != photo.id } ?? []
        context.delete(photo)
        project?.refreshPhotoSummary(from: remainingPhotos)
        do {
            try context.save()
        } catch {
            throw RepositoryError.deleteFailed(error)
        }
    }

    func deleteProject(_ project: Project) throws {
        context.delete(project)
        do {
            try context.save()
        } catch {
            throw RepositoryError.deleteFailed(error)
        }
    }

    func backfillPhotoSummaries(projects: [Project]) throws {
        let targets = projects.filter(\.photoSummaryNeedsBackfill)
        guard !targets.isEmpty else { return }
        for project in targets {
            project.refreshPhotoSummaryFromPhotos()
        }
        do {
            try context.save()
        } catch {
            throw RepositoryError.saveFailed(error)
        }
    }
}
