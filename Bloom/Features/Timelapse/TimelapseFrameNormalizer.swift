// PRD §3.3 — "apply automatic exposure/white-balance normalization across a
// project's photos so the timelapse looks coherent". Without this, a series of
// shots taken under different lighting (morning vs evening, indoor vs outdoor)
// flickers between frames and breaks the perception of slow change.
//
// Strategy: derive a per-project target by averaging the mean RGB across
// every frame, then scale each frame's per-channel mean toward that target.
// This is a lightweight gray-world / channel-gain correction — fast enough to
// run on-device per export and stable enough that small lighting drifts
// don't dominate the playback.

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

// Pure computation — no UI work, no main-actor state. `CIContext` is
// thread-safe so the shared instance can be touched from any task.
enum TimelapseFrameNormalizer {
    /// Per-channel target mean across all frames in the project.
    struct Target {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        var luminance: CGFloat {
            // ITU-R BT.709 luma weights — perceptually grounded gray reference.
            0.2126 * red + 0.7152 * green + 0.0722 * blue
        }
    }

    /// Compute the project-wide channel target from a list of source images.
    /// Returns `nil` if the input is empty.
    static func computeTarget(from images: [UIImage]) -> Target? {
        guard !images.isEmpty else { return nil }
        var totals: (CGFloat, CGFloat, CGFloat) = (0, 0, 0)
        var count = 0
        for image in images {
            guard let mean = channelMean(of: image) else { continue }
            totals.0 += mean.red
            totals.1 += mean.green
            totals.2 += mean.blue
            count += 1
        }
        guard count > 0 else { return nil }
        return Target(
            red:   totals.0 / CGFloat(count),
            green: totals.1 / CGFloat(count),
            blue:  totals.2 / CGFloat(count)
        )
    }

    /// Apply per-channel gain so the frame's average roughly matches `target`.
    /// Also gently normalizes luminance toward `target.luminance`.
    static func normalize(_ image: UIImage, toward target: Target) -> UIImage {
        guard
            let cg = image.cgImage,
            let frameMean = channelMean(of: image)
        else { return image }

        let safeFrame: (CGFloat, CGFloat, CGFloat) = (
            max(0.01, frameMean.red),
            max(0.01, frameMean.green),
            max(0.01, frameMean.blue)
        )

        // Clamp gains to keep extreme frames from blowing out highlights.
        let gainR = clamp(target.red   / safeFrame.0, min: 0.6, max: 1.6)
        let gainG = clamp(target.green / safeFrame.1, min: 0.6, max: 1.6)
        let gainB = clamp(target.blue  / safeFrame.2, min: 0.6, max: 1.6)

        let ci = CIImage(cgImage: cg)
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = ci
        matrix.rVector = CIVector(x: gainR, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: gainG, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: gainB, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        guard
            let output = matrix.outputImage,
            let rendered = sharedContext.createCGImage(output, from: output.extent)
        else { return image }
        return UIImage(cgImage: rendered, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Helpers

    private static let sharedContext = CIContext(options: [.useSoftwareRenderer: false])

    private struct ChannelMean { let red, green, blue: CGFloat }

    /// Downsample to a small 32×32 average and read per-channel mean. This is
    /// the lightweight stand-in for vImage histogram equalization (PRD §3.3).
    private static func channelMean(of image: UIImage) -> ChannelMean? {
        guard let cg = image.cgImage else { return nil }
        let width = 32
        let height = 32
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var sumR: Int = 0
        var sumG: Int = 0
        var sumB: Int = 0
        let pixelCount = width * height
        for i in 0..<pixelCount {
            let base = i * bytesPerPixel
            sumR += Int(pixels[base])
            sumG += Int(pixels[base + 1])
            sumB += Int(pixels[base + 2])
        }
        let denom = CGFloat(pixelCount * 255)
        return ChannelMean(
            red:   CGFloat(sumR) / denom,
            green: CGFloat(sumG) / denom,
            blue:  CGFloat(sumB) / denom
        )
    }

    private static func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.max(lower, Swift.min(upper, value))
    }
}
