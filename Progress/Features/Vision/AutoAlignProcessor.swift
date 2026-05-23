// PRD §3.3 — v2 enhancement: optional Vision-based auto-align toggle.
//
// Given the freshly-captured image and the reference image, detect
// face landmarks (subject = .face) or body pose (subject = .body),
// compute the affine transform that aligns the new image's landmark
// centroid + rotation to the reference, then return the aligned UIImage.
//
// The math is intentionally simple — centroid translation + a single
// rotation angle derived from the eye-line (face) or shoulder-line (body)
// — because the goal is "good enough that the timelapse stops jittering",
// not "produce a perfect biometric overlay".

import Foundation
import Vision
import CoreImage
import UIKit

@MainActor
enum AutoAlignProcessor {
    enum AlignError: Error {
        case unsupportedSubject
        case noLandmarksDetected
        case cgImageUnavailable
        case renderFailed
    }

    /// Result of a successful alignment — exposed separately from `align(...)`
    /// so tests can verify the computed transform without an image pipeline.
    struct Alignment: Equatable {
        let translation: CGSize
        let rotationRadians: CGFloat
    }

    /// Pure landmark struct used internally and from tests. Coordinates are
    /// in the source image's pixel space (origin top-left).
    struct LandmarkSet: Equatable {
        let centroid: CGPoint
        /// Direction of the dominant axis (e.g. eye line, shoulder line) in
        /// the source image. Used to derive `rotationRadians`.
        let axisAngleRadians: CGFloat
    }

    // MARK: - Public API

    static func align(
        candidate: UIImage,
        reference: UIImage,
        subjectType: SubjectType
    ) async throws -> UIImage {
        switch subjectType {
        case .object, .other:
            // No-op for non-biometric subjects (PRD §3.3). The toggle is
            // hidden in the UI, but we still guard in case someone calls
            // through programmatically.
            return candidate
        case .face, .body:
            break
        }

        guard let referenceLandmarks = try await detectLandmarks(in: reference, subject: subjectType) else {
            throw AlignError.noLandmarksDetected
        }
        guard let candidateLandmarks = try await detectLandmarks(in: candidate, subject: subjectType) else {
            throw AlignError.noLandmarksDetected
        }

        let alignment = computeAlignment(
            candidate: candidateLandmarks,
            reference: referenceLandmarks
        )
        return try await applyAlignment(alignment, to: candidate)
    }

    // MARK: - Pure math (testable)

    /// Compute the (translation, rotation) that takes `candidate` landmarks
    /// onto `reference` landmarks. Exposed so unit tests can mock landmarks
    /// without standing up Vision requests.
    static func computeAlignment(
        candidate: LandmarkSet,
        reference: LandmarkSet
    ) -> Alignment {
        let translation = CGSize(
            width: reference.centroid.x - candidate.centroid.x,
            height: reference.centroid.y - candidate.centroid.y
        )
        let rotation = reference.axisAngleRadians - candidate.axisAngleRadians
        return Alignment(translation: translation, rotationRadians: rotation)
    }

    // MARK: - Vision detection

    private static func detectLandmarks(
        in image: UIImage,
        subject: SubjectType
    ) async throws -> LandmarkSet? {
        guard let cg = image.cgImage else { throw AlignError.cgImageUnavailable }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let imageSize = CGSize(width: cg.width, height: cg.height)

        switch subject {
        case .face:
            let request = VNDetectFaceLandmarksRequest()
            try handler.perform([request])
            guard let face = (request.results as? [VNFaceObservation])?.first else {
                return nil
            }
            return faceLandmarkSet(from: face, in: imageSize)

        case .body:
            let request = VNDetectHumanBodyPoseRequest()
            try handler.perform([request])
            guard let pose = (request.results as? [VNHumanBodyPoseObservation])?.first else {
                return nil
            }
            return bodyLandmarkSet(from: pose, in: imageSize)

        case .object, .other:
            return nil
        }
    }

    private static func faceLandmarkSet(
        from face: VNFaceObservation,
        in size: CGSize
    ) -> LandmarkSet? {
        let bbox = VNImageRectForNormalizedRect(face.boundingBox, Int(size.width), Int(size.height))
        let centroid = CGPoint(x: bbox.midX, y: bbox.midY)

        // Use the roll Vision already computes when available; otherwise
        // derive an axis angle from the eye-line landmarks.
        if let roll = face.roll as? CGFloat {
            return LandmarkSet(centroid: centroid, axisAngleRadians: roll)
        }
        if let landmarks = face.landmarks,
           let leftEye = landmarks.leftEye,
           let rightEye = landmarks.rightEye
        {
            let lP = averagePoint(of: leftEye, in: bbox)
            let rP = averagePoint(of: rightEye, in: bbox)
            let dx = rP.x - lP.x
            let dy = rP.y - lP.y
            return LandmarkSet(
                centroid: centroid,
                axisAngleRadians: atan2(dy, dx)
            )
        }
        return LandmarkSet(centroid: centroid, axisAngleRadians: 0)
    }

    private static func bodyLandmarkSet(
        from observation: VNHumanBodyPoseObservation,
        in size: CGSize
    ) -> LandmarkSet? {
        guard
            let leftShoulder = try? observation.recognizedPoint(.leftShoulder),
            let rightShoulder = try? observation.recognizedPoint(.rightShoulder)
        else { return nil }

        let leftPoint = denormalize(leftShoulder.location, in: size)
        let rightPoint = denormalize(rightShoulder.location, in: size)
        let centroid = CGPoint(
            x: (leftPoint.x + rightPoint.x) / 2,
            y: (leftPoint.y + rightPoint.y) / 2
        )
        let dx = rightPoint.x - leftPoint.x
        let dy = rightPoint.y - leftPoint.y
        return LandmarkSet(centroid: centroid, axisAngleRadians: atan2(dy, dx))
    }

    // MARK: - Image transform

    private static func applyAlignment(
        _ alignment: Alignment,
        to image: UIImage
    ) async throws -> UIImage {
        guard let cg = image.cgImage else { throw AlignError.cgImageUnavailable }
        let ci = CIImage(cgImage: cg)
        let imageExtent = ci.extent
        let center = CGPoint(x: imageExtent.midX, y: imageExtent.midY)

        // Rotate about the image center, then translate.
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x, y: center.y)
        transform = transform.rotated(by: alignment.rotationRadians)
        transform = transform.translatedBy(x: -center.x, y: -center.y)
        transform = transform.translatedBy(x: alignment.translation.width, y: alignment.translation.height)

        let transformed = ci.transformed(by: transform)
            .cropped(to: imageExtent)
        let context = CIContext(options: nil)
        guard let cgResult = context.createCGImage(transformed, from: imageExtent) else {
            throw AlignError.renderFailed
        }
        return UIImage(cgImage: cgResult, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Geometry helpers

    private static func averagePoint(of region: VNFaceLandmarkRegion2D, in bbox: CGRect) -> CGPoint {
        let points = region.normalizedPoints
        guard !points.isEmpty else { return CGPoint(x: bbox.midX, y: bbox.midY) }
        let sum = points.reduce(into: CGPoint.zero) { acc, p in
            acc.x += p.x
            acc.y += p.y
        }
        let mean = CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
        // Vision face landmark points are normalized within the bbox; map back
        // to image-pixel space.
        return CGPoint(
            x: bbox.minX + mean.x * bbox.width,
            y: bbox.minY + (1 - mean.y) * bbox.height
        )
    }

    private static func denormalize(_ point: CGPoint, in size: CGSize) -> CGPoint {
        // Vision body-pose points use a normalized origin at bottom-left;
        // convert to top-left to match our image coordinate space.
        CGPoint(
            x: point.x * size.width,
            y: (1 - point.y) * size.height
        )
    }
}
