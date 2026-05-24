import Foundation
import UIKit

/// Memory-bounded image loader for UI surfaces.
///
/// SwiftUI cells call into this from `.task`; those tasks are automatically
/// cancelled when the cell leaves the hierarchy, so stale thumbnail/full-image
/// work does not keep competing with visible UI.
final class MediaLoader: @unchecked Sendable {
    static let shared = MediaLoader()

    private let assets: PhotoAssetStore
    private let thumbnailCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 220
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()
    private let fullImageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 8
        cache.totalCostLimit = 96 * 1024 * 1024
        return cache
    }()

    init(assets: PhotoAssetStore = .shared) {
        self.assets = assets
    }

    func thumbnail(relativePath: String) async -> UIImage? {
        await cachedImage(
            relativePath: relativePath,
            cache: thumbnailCache,
            priority: .userInitiated
        )
    }

    func fullImage(relativePath: String) async -> UIImage? {
        await cachedImage(
            relativePath: relativePath,
            cache: fullImageCache,
            priority: .userInitiated
        )
    }

    func cachedThumbnail(relativePath: String) -> UIImage? {
        let key = relativePath as NSString
        if let cached = thumbnailCache.object(forKey: key) {
            return cached
        }
        guard let image = assets.loadImage(relativePath: relativePath) else {
            return nil
        }
        thumbnailCache.setObject(image, forKey: key, cost: image.memoryCost)
        return image
    }

    private func cachedImage(
        relativePath: String,
        cache: NSCache<NSString, UIImage>,
        priority: TaskPriority
    ) async -> UIImage? {
        let key = relativePath as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard !Task.isCancelled else { return nil }
        guard let image = await assets.loadImageAsync(relativePath: relativePath) else {
            return nil
        }
        guard !Task.isCancelled else { return nil }
        cache.setObject(image, forKey: key, cost: image.memoryCost)
        return image
    }
}

private extension UIImage {
    var memoryCost: Int {
        guard let cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
