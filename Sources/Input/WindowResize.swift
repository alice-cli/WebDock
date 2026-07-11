import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

enum WindowResize {
    /// Resize the target window via Accessibility (point size).
    /// Used so mobile clients can match remote window size to their viewport
    /// (like changing monitor resolution for readable UI).
    static func resize(_ window: SCWindow, width: Double, height: Double) {
        guard let pid = window.owningApplication?.processID else { return }
        guard let target = AccessibilityHelpers.findWindow(
            pid: pid,
            windowID: window.windowID,
            title: window.title
        ) else { return }

        // Raise first so some apps apply size while frontmost.
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)

        var size = CGSize(width: max(240, width), height: max(160, height))
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(target, kAXSizeAttribute as CFString, value)
        }
        // Some apps only honor size after position write (nudge).
        var pos = CGPoint(x: 40, y: 40)
        if let pref = AXValueCreate(.cgPoint, &pos) {
            var cur: CFTypeRef?
            if AXUIElementCopyAttributeValue(target, kAXPositionAttribute as CFString, &cur) == .success,
               let cur, CFGetTypeID(cur) == AXValueGetTypeID() {
                var existing = CGPoint.zero
                AXValueGetValue(cur as! AXValue, .cgPoint, &existing)
                pos = existing
            }
            if let value = AXValueCreate(.cgPoint, &pos) {
                AXUIElementSetAttributeValue(target, kAXPositionAttribute as CFString, value)
            }
        }
        // Re-apply size once more after position (more reliable).
        if let value = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(target, kAXSizeAttribute as CFString, value)
        }
    }
}
