import Foundation
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Image helpers used by `PhotoStore` (PRD §3.3, §5.3).
///
/// Responsibilities:
/// - Encode UIImage to HEIC at high quality.
/// - Strip GPS / location-bearing EXIF on save.
/// - Generate ~512px thumbnails for the grid views without re-decoding the full image.
enum ImageProcessing {
    enum Error: Swift.Error {
        case cgImageUnavailable
        case encodingFailed
        case thumbnailFailed
    }

    /// Encode a UIImage as HEIC with GPS/EXIF stripped (PRD §5.3).
    static func encodeStrippedHEIC(_ image: UIImage, quality: CGFloat = 0.92) throws -> Data {
        guard let cgImage = image.cgImage else { throw Error.cgImageUnavailable }

        let data = NSMutableData()
        let utType = UTType.heic.identifier as CFString
        guard let destination = CGImageDestinationCreateWithData(data, utType, 1, nil) else {
            throw Error.encodingFailed
        }

        // Explicitly null out GPS / Exif location fields and omit auxiliary
        // metadata that could carry location/device fingerprints.
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: quality,
            kCGImagePropertyGPSDictionary: kCFNull as Any,
            kCGImagePropertyOrientation: image.imageOrientation.cgOrientation.rawValue,
        ]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Error.encodingFailed }
        return data as Data
    }

    /// Generate a thumbnail UIImage at approximately `maxPixelDimension` on the long edge.
    /// Uses `CGImageSource` so we never decode the full original into memory.
    static func makeThumbnail(from data: Data, maxPixelDimension: Int = 512) throws -> UIImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw Error.thumbnailFailed
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { throw Error.thumbnailFailed }
        return UIImage(cgImage: cgThumb)
    }
}

private extension UIImage.Orientation {
    var cgOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
