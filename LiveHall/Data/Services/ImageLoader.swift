import Foundation
import ImageIO
import os

final class ImageLoader: Sendable {
    private static let memoryLimit = 96 * 1024 * 1024
    private static let diskLimit = 200 * 1024 * 1024

    private let session: URLSession
    private let inflight = OSAllocatedUnfairLock(initialState: [String: Task<CGImage?, Never>]())
    private nonisolated(unsafe) let cache = NSCache<NSString, CGImage>()

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 0, diskCapacity: Self.diskLimit,
            directory: URL.cachesDirectory.appending(path: "LiveHall/Images", directoryHint: .isDirectory))
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
        cache.totalCostLimit = Self.memoryLimit
    }

    func cachedImage(url: URL, maxPixelSize: Int) -> CGImage? {
        cache.object(forKey: Self.key(url, maxPixelSize) as NSString)
    }

    func image(url: URL, maxPixelSize: Int) async -> CGImage? {
        let key = Self.key(url, maxPixelSize)
        if let hit = cache.object(forKey: key as NSString) { return hit }
        let task = inflight.withLock { tasks in
            if let existing = tasks[key] { return existing }
            let created = Task.detached(priority: .utility) { [session, cache, inflight] in
                let image = await Self.load(url: url, maxPixelSize: maxPixelSize, session: session)
                if let image { cache.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height) }
                inflight.withLock { $0[key] = nil }
                return image
            }
            tasks[key] = created
            return created
        }
        return await task.value
    }

    private static func key(_ url: URL, _ maxPixelSize: Int) -> String {
        "\(maxPixelSize)|\(url.absoluteString)"
    }

    private static func bytes(url: URL, session: URLSession) async -> Data? {
        let request = URLRequest(url: url)
        if let (data, response) = try? await session.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200
        {
            return data
        }
        return session.configuration.urlCache?.cachedResponse(for: request)?.data
    }

    private static func load(url: URL, maxPixelSize: Int, session: URLSession) async -> CGImage? {
        guard let data = await bytes(url: url, session: session),
            let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
