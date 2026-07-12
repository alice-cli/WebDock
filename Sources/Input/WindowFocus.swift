import AppKit
import ApplicationServices
import CoreGraphics

/// Raise / activate the remote target window so CGEvent hits *it*, not a covering app.
///
/// Synthetic mouse events use screen coordinates: whatever window is topmost **at that
/// point** receives the click. Activating the app without raising the window is not enough.
///
/// Hot path is optimized for typing: after a successful raise, the same window is treated
/// as focused for a short cache window so every key does not pay CGWindowList + sleep.
enum WindowFocus {
    private static let cacheLock = NSLock()
    private static var lastPID: pid_t = 0
    private static var lastWindowID: CGWindowID = 0
    private static var lastAt: CFAbsoluteTime = 0
    /// Trust a successful focus for this long without re-querying z-order.
    private static let cacheTTL: CFAbsoluteTime = 0.45

    /// True when the cache says this window was successfully focused very recently
    /// and the same process is still frontmost (cheap — no CGWindowList).
    static func isRecentlyFocused(pid: pid_t, windowID: CGWindowID) -> Bool {
        cacheLock.lock()
        let hit = lastPID == pid
            && lastWindowID == windowID
            && (CFAbsoluteTimeGetCurrent() - lastAt) < cacheTTL
        cacheLock.unlock()
        guard hit else { return false }
        // Drop cache if the user switched away on the Mac.
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    /// True when `windowID` is the frontmost layer-0 window covering `point` (or globally if point is nil)
    /// and its process is the frontmost app.
    ///
    /// - Parameter useCache: When true (typing hot path), a recent successful focus may skip
    ///   CGWindowList. After a raise, callers must pass `false` so verification is live.
    static func isReadyForInput(
        pid: pid_t,
        windowID: CGWindowID,
        at point: CGPoint? = nil,
        useCache: Bool = true
    ) -> Bool {
        // Fast path: recent successful focus — skip expensive CGWindowList on every key.
        // Point-based mouse hits always re-check z-order (clicks are less frequent).
        if useCache, point == nil, isRecentlyFocused(pid: pid, windowID: windowID) {
            return true
        }

        if let point {
            guard topWindowID(at: point) == windowID else { return false }
        } else {
            guard isTopmostOnScreen(windowID: windowID) else { return false }
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    /// Frontmost on-screen layer-0 window id (optionally ignoring WebDock UI).
    static func isTopmostOnScreen(windowID: CGWindowID) -> Bool {
        topWindowID(at: nil) == windowID
    }

    /// Window id that would receive a click at `point` (global coords, top-left origin like CG).
    /// If `point` is nil, returns the overall frontmost layer-0 window (skipping WebDock).
    static func topWindowID(at point: CGPoint?) -> CGWindowID? {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let myPID = ProcessInfo.processInfo.processIdentifier

        for info in list {
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            if alpha < 0.05 { continue }

            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                ?? (info[kCGWindowOwnerPID as String] as? Int).map { Int32($0) }
            // WebDock settings/stream UI sits in front of the remote window; ignore for z-order.
            if let ownerPID, ownerPID == myPID { continue }

            guard let num = info[kCGWindowNumber as String] as? NSNumber else { continue }
            let wid = CGWindowID(truncatingIfNeeded: num.intValue)

            if let point {
                guard let bounds = windowBounds(info), bounds.contains(point) else { continue }
            }
            return wid
        }
        return nil
    }

    /// Bring target app + exact window to front.
    ///
    /// Fast path: cache / already-ready → return immediately (no sleep).
    /// Slow path: at most two short raises (~8ms settle each). AppleScript only when `force`.
    @discardableResult
    static func ensureFocused(
        pid: pid_t,
        windowID: CGWindowID,
        title: String?,
        force: Bool = false,
        at point: CGPoint? = nil
    ) -> Bool {
        // 1) Cache hit (keyboard typing): zero cost.
        if !force, point == nil, isRecentlyFocused(pid: pid, windowID: windowID) {
            return true
        }

        // 2) Already frontmost — remember and leave (live check, no cache).
        if isReadyForInput(pid: pid, windowID: windowID, at: point, useCache: false) {
            remember(pid: pid, windowID: windowID)
            return true
        }

        // 3) One raise + short settle.
        hardRaise(pid: pid, windowID: windowID, title: title)
        usleep(8_000)
        if isReadyForInput(pid: pid, windowID: windowID, at: point, useCache: false) {
            remember(pid: pid, windowID: windowID)
            return true
        }

        // 4) Second raise only (still no long polling).
        hardRaise(pid: pid, windowID: windowID, title: title)
        usleep(8_000)
        if isReadyForInput(pid: pid, windowID: windowID, at: point, useCache: false) {
            remember(pid: pid, windowID: windowID)
            return true
        }

        // 5) AppleScript only for explicit force (clicks / hard heal) — never on every key.
        if force {
            appleScriptActivate(pid: pid)
            raiseWindow(pid: pid, windowID: windowID, title: title)
            usleep(12_000)
            if isReadyForInput(pid: pid, windowID: windowID, at: point, useCache: false) {
                remember(pid: pid, windowID: windowID)
                return true
            }
        }

        print("focus: still not front windowID=\(windowID) pid=\(pid) top=\(String(describing: topWindowID(at: point)))")
        return false
    }

    private static func appleScriptActivate(pid: pid_t) {
        guard let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return }
        let script = "tell application id \"\(bundleID)\" to activate"
        let work = {
            if let apple = NSAppleScript(source: script) {
                var err: NSDictionary?
                apple.executeAndReturnError(&err)
            }
        }
        if Thread.isMainThread { work() } else { DispatchQueue.main.sync(execute: work) }
    }

    static func invalidateCache() {
        cacheLock.lock()
        lastPID = 0
        lastWindowID = 0
        lastAt = 0
        cacheLock.unlock()
    }

    // MARK: - Raise

    private static func hardRaise(pid: pid_t, windowID: CGWindowID, title: String?) {
        let work = {
            let app = NSRunningApplication(processIdentifier: pid)
            if app?.isHidden == true {
                _ = app?.unhide()
            }

            let axApp = AccessibilityHelpers.applicationElement(pid: pid)
            // Make application frontmost via Accessibility (stronger than activate alone).
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue as CFTypeRef)

            if let app {
                if #available(macOS 14.0, *) {
                    NSApp.yieldActivation(to: app)
                    // Prefer activate(from:) so macOS treats this as an explicit switch.
                    _ = app.activate(from: NSRunningApplication.current)
                } else {
                    _ = app.activate(options: [.activateIgnoringOtherApps])
                }
            }

            raiseWindow(pid: pid, windowID: windowID, title: title)
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }
    }

    private static func raiseWindow(pid: pid_t, windowID: CGWindowID, title: String?) {
        let (app, windows) = AccessibilityHelpers.windows(for: pid)
        let target = AccessibilityHelpers.findWindow(pid: pid, windowID: windowID, title: title)
            ?? windows.first
        guard let target else {
            print("focus: AX window not found id=\(windowID) pid=\(pid)")
            return
        }

        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue as CFTypeRef)
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(app, kAXMainWindowAttribute as CFString, target)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, target)
        // Some apps need focused attribute on the window itself.
        AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue as CFTypeRef)
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
    }

    private static func remember(pid: pid_t, windowID: CGWindowID) {
        cacheLock.lock()
        lastPID = pid
        lastWindowID = windowID
        lastAt = CFAbsoluteTimeGetCurrent()
        cacheLock.unlock()
    }

    private static func windowBounds(_ info: [String: Any]) -> CGRect? {
        guard let raw = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
        // CGWindow bounds: origin top-left of main display (same as CGEvent).
        let x = raw["X"] ?? 0
        let y = raw["Y"] ?? 0
        let w = raw["Width"] ?? 0
        let h = raw["Height"] ?? 0
        guard w > 0, h > 0 else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
