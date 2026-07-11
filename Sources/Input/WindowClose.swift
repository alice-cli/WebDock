import AppKit
import ApplicationServices
import CoreGraphics

/// Close a single window without quitting the whole application.
/// (Terminal 등 한 프로세스·여러 창 앱에서 `terminate()`는 창 전부가 죽음.)
enum WindowClose {
    /// Prefer Accessibility close-button; fall back to focused Cmd+W.
    @discardableResult
    static func close(pid: pid_t, windowID: CGWindowID, title: String?) -> Bool {
        guard pid > 0, !CaptureManager.isDisplayRoute(windowID) else { return false }

        let work: () -> Bool = {
            if closeViaAccessibility(pid: pid, windowID: windowID, title: title) {
                return true
            }
            return closeViaCommandW(pid: pid, windowID: windowID, title: title)
        }

        if Thread.isMainThread {
            return work()
        }
        return DispatchQueue.main.sync(execute: work)
    }

    // MARK: - AX close button

    private static func closeViaAccessibility(
        pid: pid_t,
        windowID: CGWindowID,
        title: String?
    ) -> Bool {
        guard let window = AccessibilityHelpers.findWindow(
            pid: pid,
            windowID: windowID,
            title: title
        ) else { return false }

        var closeRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            window,
            kAXCloseButtonAttribute as CFString,
            &closeRef
        )
        guard err == .success, let closeRef else { return false }

        let closeButton = unsafeBitCast(closeRef, to: AXUIElement.self)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        return AXUIElementPerformAction(closeButton, kAXPressAction as CFString) == .success
    }

    // MARK: - Cmd+W fallback

    private static func closeViaCommandW(
        pid: pid_t,
        windowID: CGWindowID,
        title: String?
    ) -> Bool {
        WindowFocus.ensureFocused(
            pid: pid,
            windowID: windowID,
            title: title,
            force: true
        )
        KeyboardInjection.injectKeyGlobal(
            code: "KeyW",
            command: true,
            shift: false,
            control: false,
            option: false
        )
        return true
    }
}
