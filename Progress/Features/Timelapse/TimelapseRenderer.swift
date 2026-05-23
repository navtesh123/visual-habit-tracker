// PRD §3.3 / §3.7 / §7.4 — Timelapse export.
//
// Produces an MP4 from a project's photo sequence using `AVAssetWriter`.
// Each photo is held for `1.0 / speed` seconds; frames are normalized for
// exposure/white-balance coherence; the end-card (project name + accent) is
// composited as the final frame.

import Foundation
import AVFoundation
import CoreImage
import UIKit

/// Pure-data input for a single timelapse frame. Resolved upstream so the
/// renderer doesn't need to touch `PhotoStore` on the writer queue.
struct TimelapseFrame {
    let image: UIImage
    let capturedAt: Date
}

/// Renders a sequence of frames into an MP4 sitting in `tmp/`.
/// Mark `@MainActor` only at the call boundary — the heavy lifting runs on
/// AVFoundation's serialized writer queue inside `render`.
enum TimelapseRenderer {
    enum RenderError: Error {
        case noFrames
        case writerSetupFailed
        case pixelBufferUnavailable
        case writeFailed(underlying: Error?)
    }

    /// Output canvas dimensions. 1080 × 1920 is the safe-everywhere portrait
    /// frame for iOS sharing (Instagram Reels, TikTok, iMessage previews).
    static let canvasSize = CGSize(width: 1080, height: 1920)

    /// Frames-per-second of the rendered MP4. We use a constant high FPS so
    /// the slow-motion / fast-motion effect comes from how long each photo
    /// is displayed, not from variable framerate (which players handle poorly).
    static let fps: Int32 = 30

    /// Where rendered timelapses live before sharing.
    static func outputURL(for projectName: String) -> URL {
        let safeName = projectName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined(separator: "-")
        let timestamp = Int(Date.now.timeIntervalSince1970)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("Progress-\(safeName)-\(timestamp).mp4")
    }

    /// Render `frames` at `speed` (×) playback. `1.0` shows each photo for
    /// 1 s; `4.0` for 0.25 s.
    static func render(
        frames: [TimelapseFrame],
        speed: Double,
        projectName: String,
        accent: AccentToken,
        normalize: Bool = true
    ) async throws -> URL {
        guard frames.count >= 1 else { throw RenderError.noFrames }

        let endCard = await TimelapseEndCard.render(
            projectName: projectName,
            accent: accent,
            photoCount: frames.count,
            size: canvasSize
        )

        let target = normalize
            ? TimelapseFrameNormalizer.computeTarget(from: frames.map(\.image))
            : nil

        let url = outputURL(for: projectName)
        try? FileManager.default.removeItem(at: url)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            throw RenderError.writerSetupFailed
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(canvasSize.width),
            AVVideoHeightKey: Int(canvasSize.height),
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(canvasSize.width),
            kCVPixelBufferHeightKey as String: Int(canvasSize.height),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(input) else { throw RenderError.writerSetupFailed }
        writer.add(input)

        guard writer.startWriting() else {
            throw RenderError.writeFailed(underlying: writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        // Each frame holds for `holdSeconds`, so it occupies `holdFrames`
        // worth of presentation time at the timeline FPS.
        let holdSeconds = max(0.05, 1.0 / max(0.1, speed))
        let holdFrames = max(Int32(1), Int32((holdSeconds * Double(fps)).rounded()))

        let ciContext = CIContext(options: nil)
        var presentationFrameIndex: Int32 = 0
        var renderError: Error?

        // Walk the source frames sequentially. We push the same pixel buffer
        // `holdFrames` times so the photo lingers at full FPS.
        for source in frames {
            let normalized: UIImage
            if let target {
                normalized = TimelapseFrameNormalizer.normalize(source.image, toward: target)
            } else {
                normalized = source.image
            }
            guard let buffer = renderPixelBuffer(
                from: normalized,
                size: canvasSize,
                adaptor: adaptor,
                ciContext: ciContext
            ) else {
                renderError = RenderError.pixelBufferUnavailable
                break
            }
            for _ in 0..<holdFrames {
                while !input.isReadyForMoreMediaData {
                    try? await Task.sleep(for: .milliseconds(5))
                }
                let pts = CMTime(value: CMTimeValue(presentationFrameIndex), timescale: fps)
                adaptor.append(buffer, withPresentationTime: pts)
                presentationFrameIndex += 1
            }
        }

        // Append the branded end card for a generous 1.5 seconds.
        if renderError == nil, let endCard,
           let endBuffer = renderPixelBuffer(
                from: endCard,
                size: canvasSize,
                adaptor: adaptor,
                ciContext: ciContext
           )
        {
            let endHold = max(Int32(fps + (fps / 2)), holdFrames * 2)
            for _ in 0..<endHold {
                while !input.isReadyForMoreMediaData {
                    try? await Task.sleep(for: .milliseconds(5))
                }
                let pts = CMTime(value: CMTimeValue(presentationFrameIndex), timescale: fps)
                adaptor.append(endBuffer, withPresentationTime: pts)
                presentationFrameIndex += 1
            }
        }

        input.markAsFinished()
        await writer.finishWriting()

        if let renderError { throw renderError }
        if writer.status != .completed {
            throw RenderError.writeFailed(underlying: writer.error)
        }
        return url
    }

    // MARK: - Pixel buffer rasterization

    private static func renderPixelBuffer(
        from image: UIImage,
        size: CGSize,
        adaptor: AVAssetWriterInputPixelBufferAdaptor,
        ciContext: CIContext
    ) -> CVPixelBuffer? {
        guard let pool = adaptor.pixelBufferPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let cgContext = CGContext(
            data: baseAddress,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Black letterbox + aspect-fit so the canvas is always 1080×1920
        // regardless of source aspect ratio.
        cgContext.setFillColor(UIColor.black.cgColor)
        cgContext.fill(CGRect(origin: .zero, size: size))

        if let cg = image.cgImage {
            let imageSize = CGSize(width: cg.width, height: cg.height)
            let fittedRect = aspectFitRect(content: imageSize, into: CGRect(origin: .zero, size: size))
            cgContext.draw(cg, in: fittedRect)
        }
        return buffer
    }

    private static func aspectFitRect(content: CGSize, into bounds: CGRect) -> CGRect {
        let scale = min(bounds.width / content.width, bounds.height / content.height)
        let scaled = CGSize(width: content.width * scale, height: content.height * scale)
        return CGRect(
            x: bounds.midX - scaled.width / 2,
            y: bounds.midY - scaled.height / 2,
            width: scaled.width,
            height: scaled.height
        )
    }
}
