import ApplicationServices
import CoreGraphics

/// Shared Accessibility helpers used by focus, resize, and input injection.
enum AccessibilityHelpers {
    /// Private HIServices symbol: maps an AX window to its `CGWindowID`.
    static let windowIDGetter: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError)? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "_AXUIElementGetWindow")
        else { return nil }
        return unsafeBitCast(
            symbol,
            to: (@convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError).self
        )
    }()

    static func applicationElement(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    static func windows(for pid: pid_t) -> (app: AXUIElement, windows: [AXUIElement]) {
        let app = applicationElement(pid: pid)
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref)
        return (app, (ref as? [AXUIElement]) ?? [])
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getter = windowIDGetter else { return nil }
        var id: CGWindowID = 0
        guard getter(element, &id) == .success else { return nil }
        return id
    }

    /// Exact match by CGWindowID, then title. Returns nil if neither matches
    /// (never falls back to an arbitrary window).
    static func findWindow(
        pid: pid_t,
        windowID: CGWindowID,
        title: String?
    ) -> AXUIElement? {
        let (_, windows) = windows(for: pid)
        guard !windows.isEmpty else { return nil }

        if let match = windows.first(where: { self.windowID(of: $0) == windowID }) {
            return match
        }
        if let title, !title.isEmpty {
            for window in windows {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                if (titleRef as? String) == title { return window }
            }
        }
        return nil
    }
}
