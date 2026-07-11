import AppKit
import ApplicationServices
import CoreGraphics

enum WindowFocus {
    private static let cacheLock = NSLock()
    private static var lastPID: pid_t = 0
    private static var lastWindowID: CGWindowID = 0
    private static var lastAt: CFAbsoluteTime = 0

    /// Bring this exact window above others before injecting input.
    /// Overlapping windows: always raise when `force` (mouse-down) so clicks hit A not B on top.
    static func ensureFocused(pid: pid_t, windowID: CGWindowID, title: String?, force: Bool = false) {
        // If another window is literally covering us on screen, ignore cache.
        let top = isTopmostOnScreen(windowID: windowID)
        if top, !force {
            cacheLock.lock()
            let cached =
                lastPID == pid
                && lastWindowID == windowID
                && (CFAbsoluteTimeGetCurrent() - lastAt) < 1.0
            cacheLock.unlock()
            if cached { return }
        }
        if top, force {
            // On-screen topmost, but still ensure the app is frontmost so the
            // click isn't delivered to another active app's event path.
            let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            if frontPID == pid {
                remember(pid: pid, windowID: windowID)
                return
            }
            // Fall through to activate without full raise thrash if possible.
        }

        let app = NSRunningApplication(processIdentifier: pid)
        let work = {
            if app?.isHidden == true {
                _ = app?.unhide()
            }
            // Steal frontmost app from whatever covers us (window B).
            if #available(macOS 14.0, *) {
                _ = app?.activate()
            } else {
                _ = app?.activate(options: [.activateIgnoringOtherApps])
            }
            raiseWindow(pid: pid, windowID: windowID, title: title)
            // Second raise after activate — more reliable when another app was front.
            raiseWindow(pid: pid, windowID: windowID, title: title)
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }

        // Short settle — long sleep makes drag selection feel broken.
        usleep(force ? 12_000 : 5_000)
        remember(pid: pid, windowID: windowID)
    }

    static func invalidateCache() {
        cacheLock.lock()
        lastPID = 0
        lastWindowID = 0
        lastAt = 0
        cacheLock.unlock()
    }

    // MARK: - Topmost check

    /// True if `windowID` is the frontmost layer-0 on-screen window (nothing covers it).
    static func isTopmostOnScreen(windowID: CGWindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        for info in list {
            // Skip menus, overlays, etc.
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            if alpha < 0.05 { continue }
            guard let num = info[kCGWindowNumber as String] as? NSNumber else { continue }
            return CGWindowID(truncatingIfNeeded: num.intValue) == windowID
        }
        return false
    }

    private static func remember(pid: pid_t, windowID: CGWindowID) {
        cacheLock.lock()
        lastPID = pid
        lastWindowID = windowID
        lastAt = CFAbsoluteTimeGetCurrent()
        cacheLock.unlock()
    }

    private static func raiseWindow(pid: pid_t, windowID: CGWindowID, title: String?) {
        let (app, _) = AccessibilityHelpers.windows(for: pid)
        guard let target = AccessibilityHelpers.findWindow(pid: pid, windowID: windowID, title: title)
        else { return }

        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(app, kAXMainWindowAttribute as CFString, target)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, target)
        // Press front again.
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
    }
}
