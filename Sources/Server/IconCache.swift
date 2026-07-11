import AppKit
import Foundation

/// Thread-safe cache of app icons as `data:image/png;base64,...` URLs.
final class IconCache {
    static let shared = IconCache()

    private var cache: [String: String] = [:]
    private let lock = NSLock()
    private let defaultSize = 32

    private init() {}

    func dataURL(forFilePath path: String, size: Int? = nil) -> String? {
        let pixelSize = size ?? defaultSize
        if let hit = lockedGet(path) { return hit }

        let image = NSWorkspace.shared.icon(forFile: path)
        guard let encoded = encode(image, size: pixelSize) else { return nil }
        lockedSet(path, encoded)
        return encoded
    }

    func dataURL(for image: NSImage?, key: String, size: Int? = nil) -> String? {
        guard let image else { return nil }
        let pixelSize = size ?? defaultSize
        if let hit = lockedGet(key) { return hit }
        guard let encoded = encode(image, size: pixelSize) else { return nil }
        lockedSet(key, encoded)
        return encoded
    }

    // MARK: - Private

    private func lockedGet(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return cache[key]
    }

    private func lockedSet(_ key: String, _ value: String) {
        lock.lock(); defer { lock.unlock() }
        cache[key] = value
    }

    private func encode(_ image: NSImage, size: Int) -> String? {
        let work = { () -> String? in
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: size,
                pixelsHigh: size,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) else { return nil }

            rep.size = NSSize(width: size, height: size)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(
                in: NSRect(x: 0, y: 0, width: size, height: size),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
            NSGraphicsContext.restoreGraphicsState()

            guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
            return "data:image/png;base64," + png.base64EncodedString()
        }

        if Thread.isMainThread { return work() }
        return DispatchQueue.main.sync(execute: work)
    }
}
