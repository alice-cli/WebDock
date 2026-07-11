import CoreGraphics
import Foundation

enum WindowGeometry {
    private static let lock = NSLock()
    private static var cache: (windowID: CGWindowID, bounds: CGRect, at: CFAbsoluteTime)?

    /// Live on-screen bounds for a window (falls back to `fallback` if unavailable).
    /// Cached ~50ms per windowID to avoid CGWindowList on every mouse move.
    static func liveBounds(windowID: CGWindowID, fallback: CGRect) -> CGRect {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        if let cache, cache.windowID == windowID, now - cache.at < 0.05 {
            let bounds = cache.bounds
            lock.unlock()
            return bounds
        }
        lock.unlock()

        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let info = list.first,
              let raw = info[kCGWindowBounds as String] as? [String: CGFloat],
              let width = raw["Width"],
              let height = raw["Height"],
              width > 0, height > 0
        else { return fallback }

        let bounds = CGRect(
            x: raw["X"] ?? 0,
            y: raw["Y"] ?? 0,
            width: width,
            height: height
        )

        lock.lock()
        cache = (windowID, bounds, now)
        lock.unlock()
        return bounds
    }

    /// Convert fractional (0…1) coordinates inside a window to global screen points.
    static func globalPoint(
        xFraction: Double,
        yFraction: Double,
        windowID: CGWindowID,
        fallback: CGRect
    ) -> CGPoint {
        let frame = liveBounds(windowID: windowID, fallback: fallback)
        return CGPoint(
            x: frame.origin.x + CGFloat(xFraction) * frame.width,
            y: frame.origin.y + CGFloat(yFraction) * frame.height
        )
    }
}
