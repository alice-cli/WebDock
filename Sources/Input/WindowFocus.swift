import AppKit
import ApplicationServices
import CoreGraphics

/// Raise / activate the remote target window so CGEvent hits *it*, not a covering app.
///
/// Synthetic mouse events use screen coordinates: whatever window is topmost **at that
/// point** receives the click. Activating the app without raising the window is not enough.
enum WindowFocus {
    private static let cacheLock = NSLock()
    private static var lastPID: pid_t = 0
    private static var lastWindowID: CGWindowID = 0
    private static var lastAt: CFAbsoluteTime = 0

    /// True when `windowID` is the frontmost layer-0 window covering `point` (or globally if point is nil)
    /// and its process is the frontmost app.
    static func isReadyForInput(pid: pid_t, windowID: CGWindowID, at point: CGPoint? = nil) -> Bool {
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

    /// Bring target app + exact window to front. Retries until topmost or timeout.
    @discardableResult
    static func ensureFocused(
        pid: pid_t,
        windowID: CGWindowID,
        title: String?,
        force: Bool = false,
        at point: CGPoint? = nil
    ) -> Bool {
        if !force, isReadyForInput(pid: pid, windowID: windowID, at: point) {
            cacheLock.lock()
            let cached =
                lastPID == pid
                && lastWindowID == windowID
                && (CFAbsoluteTimeGetCurrent() - lastAt) < 0.5
            cacheLock.unlock()
            if cached { return true }
        }

        if isReadyForInput(pid: pid, windowID: windowID, at: point), force {
            remember(pid: pid, windowID: windowID)
            return true
        }

        let deadline = CFAbsoluteTimeGetCurrent() + 0.25
        var attempt = 0
        while CFAbsoluteTimeGetCurrent() < deadline {
            attempt += 1
            hardRaise(pid: pid, windowID: windowID, title: title)
            usleep(attempt == 1 ? 40_000 : 25_000)
            if isReadyForInput(pid: pid, windowID: windowID, at: point) {
                remember(pid: pid, windowID: windowID)
                return true
            }
        }

        // Last try + AppleScript activate (only if still covered)
        hardRaise(pid: pid, windowID: windowID, title: title)
        if !isReadyForInput(pid: pid, windowID: windowID, at: point) {
            appleScriptActivate(pid: pid)
            raiseWindow(pid: pid, windowID: windowID, title: title)
            usleep(50_000)
        }
        let ok = isReadyForInput(pid: pid, windowID: windowID, at: point)
        remember(pid: pid, windowID: windowID)
        if !ok {
            print("focus: still not front windowID=\(windowID) pid=\(pid) top=\(String(describing: topWindowID(at: point)))")
        }
        return ok
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
