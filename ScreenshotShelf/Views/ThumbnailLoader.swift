import AppKit
import QuickLookThumbnailing

@MainActor
final class ThumbnailLoader: ObservableObject {
    @Published var image: NSImage?

    func load(url: URL, modifiedAt: Date) {
        if let cached = ThumbnailCache.shared.image(for: url, modifiedAt: modifiedAt) {
            image = cached
            return
        }

        Task.detached {
            let generated = ThumbnailCache.shared.generate(url: url, modifiedAt: modifiedAt)
            await MainActor.run {
                self.image = generated
            }
        }
    }
}

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL, modifiedAt: Date) -> NSImage? {
        cache.object(forKey: key(url: url, modifiedAt: modifiedAt))
    }

    func generate(url: URL, modifiedAt: Date) -> NSImage? {
        let cacheKey = key(url: url, modifiedAt: modifiedAt)
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let size = CGSize(width: 360, height: 240)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 2,
            representationTypes: .thumbnail
        )

        let semaphore = DispatchSemaphore(value: 0)
        var result: NSImage?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            result = representation?.nsImage
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 2)

        if result == nil, let full = NSImage(contentsOf: url) {
            result = downsampled(full, to: size)
        }

        if let result {
            cache.setObject(result, forKey: cacheKey)
        }
        return result
    }

    private func key(url: URL, modifiedAt: Date) -> NSString {
        "\(url.path)|\(modifiedAt.timeIntervalSince1970)" as NSString
    }

    private func downsampled(_ image: NSImage, to size: CGSize) -> NSImage {
        let result = NSImage(size: size)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1
        )
        result.unlockFocus()
        return result
    }
}
