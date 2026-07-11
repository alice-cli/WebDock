import AppKit
import Foundation
import CoreGraphics
import ApplicationServices

/// Screen Recording + Accessibility.
///
/// Do **not** call the system prompt APIs on every launch. When the binary's code
/// signature does not match the TCC row (ad-hoc rebuilds, path changes), preflight
/// stays false forever and `CGRequest*` / AX prompt spam the user even though
/// Settings still shows an old WebDock toggle as "on".
enum Permissions {
    private static let askedScreenKey = "webdock.perm.askedScreen"
    private static let askedAXKey = "webdock.perm.askedAX"
    private static let lastPromptDayKey = "webdock.perm.lastPromptDay"

    static func requestAll() {
        // Log only — never block startup on dialogs.
        let screen = CGPreflightScreenCaptureAccess()
        let ax = AXIsProcessTrusted()
        print(summaryLine())

        if screen && ax { return }

        // At most one system prompt path per calendar day (avoids infinite loops).
        let day = dayStamp()
        let defaults = UserDefaults.standard
        if defaults.string(forKey: lastPromptDayKey) == day {
            if !screen || !ax {
                print("perms: still missing — enable WebDock in System Settings (already prompted today)")
            }
            return
        }
        defaults.set(day, forKey: lastPromptDayKey)

        if !screen {
            // One-shot API prompt, then open Settings so user can flip the right row.
            if !defaults.bool(forKey: askedScreenKey) {
                defaults.set(true, forKey: askedScreenKey)
                _ = CGRequestScreenCaptureAccess()
            }
            openScreenRecordingSettings()
        }

        if !ax {
            // Prefer Settings over AX prompt dialog (less noisy, same result).
            if !defaults.bool(forKey: askedAXKey) {
                defaults.set(true, forKey: askedAXKey)
                let options = [
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                ] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(options)
            }
            openAccessibilitySettings()
        }
    }

    static func summaryLine() -> String {
        let screen = CGPreflightScreenCaptureAccess() ? "on" : "OFF"
        let accessibility = AXIsProcessTrusted() ? "on" : "OFF"
        return "  perms : ScreenRec=\(screen)  Accessibility=\(accessibility)"
    }

    /// Reset local "already asked" flags (does not clear system TCC).
    static func resetPromptCooldown() {
        let d = UserDefaults.standard
        d.removeObject(forKey: askedScreenKey)
        d.removeObject(forKey: askedAXKey)
        d.removeObject(forKey: lastPromptDayKey)
    }

    // MARK: - Settings deep links

    private static func dayStamp() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func openScreenRecordingSettings() {
        // macOS 13+ privacy pane
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        ]
        openFirstAvailable(urls)
    }

    private static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        openFirstAvailable(urls)
    }

    private static func openFirstAvailable(_ candidates: [String]) {
        for s in candidates {
            if let u = URL(string: s), NSWorkspace.shared.open(u) { return }
        }
    }
}
