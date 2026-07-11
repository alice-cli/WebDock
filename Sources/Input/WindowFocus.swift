import AppKit
import ApplicationServices
import CoreGraphics

enum WindowFocus {
    private static let cacheLock = NSLock()
    private static var lastPID: pid_t = 0
    private static var lastWindowID: CGWindowID = 0
    private static var lastAt: CFAbsoluteTime = 0

    /// True when this window is frontmost on screen AND its app is active.
    static func isReadyForInput(pid: pid_t, windowID: CGWindowID) -> Bool {
        guard isTopmostOnScreen(windowID: windowID) else { return false }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    /// Bring this exact window above others before injecting input.
    /// If another app covers the target, always activate + raise (ignore short cache).
    @discardableResult
    static func ensureFocused(pid: pid_t, windowID: CGWindowID, title: String?, force: Bool = false) -> Bool {
        let top = isTopmostOnScreen(windowID: windowID)
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let appFront = frontPID == pid
        let ready = top && appFront

        if ready, !force {
            cacheLock.lock()
            let cached =
                lastPID == pid
                && lastWindowID == windowID
                && (CFAbsoluteTimeGetCurrent() - lastAt) < 0.8
            cacheLock.unlock()
            if cached { return true }
        }

        // Already the top window of the front app — light path.
        if ready, force {
            remember(pid: pid, windowID: windowID)
            return true
        }

        let covered = !top || !appFront
        let app = NSRunningApplication(processIdentifier: pid)
        let work = {
            if app?.isHidden == true {
                _ = app?.unhide()
            }
            // Steal focus from whatever is covering us (including WebDock itself).
            if #available(macOS 14.0, *) {
                if let app {
                    // Prefer yielding from WebDock → target so activation actually switches.
                    _ = NSRunningApplication.current.yieldActivation(to: app)
                    _ = app.activate()
                }
            } else {
                _ = app?.activate(options: [.activateIgnoringOtherApps])
            }
            raiseWindow(pid: pid, windowID: windowID, title: title)
            raiseWindow(pid: pid, windowID: windowID, title: title)
            // Third pass after short yield if still covered (another app was front).
            if covered {
                raiseWindow(pid: pid, windowID: windowID, title: title)
            }
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }

        // Covered windows need a longer settle so the click hits the raised app.
        usleep(covered ? 45_000 : (force ? 15_000 : 6_000))

        // Verify; one more hard raise if still not ready.
        if !isReadyForInput(pid: pid, windowID: windowID) {
            let retry = {
                if let app {
                    if #available(macOS 14.0, *) {
                        _ = NSRunningApplication.current.yieldActivation(to: app)
                        _ = app.activate()
                    } else {
                        _ = app.activate(options: [.activateIgnoringOtherApps])
                    }
                }
                raiseWindow(pid: pid, windowID: windowID, title: title)
            }
            if Thread.isMainThread { retry() } else { DispatchQueue.main.sync(execute: retry) }
            usleep(35_000)
        }

        remember(pid: pid, windowID: windowID)
        return isReadyForInput(pid: pid, windowID: windowID)
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

        // Skip our own WebDock windows so they don't "cover" the target for z-order checks
        // when the user is looking at the stream but WebDock is frontmost in the Dock sense.
        // (Clicks still need the target raised above other *content* windows.)
        let myPID = ProcessInfo.processInfo.processIdentifier

        for info in list {
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            if layer != 0 { continue }
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 1
            if alpha < 0.05 { continue }
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t
            // Ignore WebDock's own UI when deciding if the *target* is topmost among apps.
            if let ownerPID, ownerPID == myPID { continue }
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
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
    }
}
