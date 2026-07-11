import AppKit
import Foundation

/// Launch apps and open **new windows** without spawning a second process that
/// restores old Terminal sessions (which looked like “2 windows + old history”).
enum AppLauncher {
    /// - Parameter newWindow: if true, open an extra window (not a second app instance).
    static func open(path: String, newWindow: Bool) {
        guard AppsCatalog.isAllowedLaunchPath(path) else {
            print("launch denied: \(path)")
            return
        }
        let url = URL(fileURLWithPath: path)
        let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
        let name = url.deletingPathExtension().lastPathComponent

        DispatchQueue.main.async {
            if newWindow {
                openNewWindow(path: path, url: url, bundleID: bundleID, name: name)
            } else {
                activateOrLaunch(url: url)
            }
        }
    }

    // MARK: - Activate / first launch

    private static func activateOrLaunch(url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                print("launch failed: \(url.path) — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - New window (same process)

    private static func openNewWindow(path: String, url: URL, bundleID: String, name: String) {
        // Terminal: never use createsNewApplicationInstance — that restores old windows × N.
        if bundleID == "com.apple.Terminal" || name == "Terminal" {
            if runAppleScript("""
                tell application "Terminal"
                  activate
                  do script ""
                end tell
                """) {
                print("launch: Terminal new window via AppleScript")
                return
            }
        }

        if bundleID == "com.googlecode.iterm2" || name == "iTerm" || name == "iTerm2" {
            if runAppleScript("""
                tell application "iTerm"
                  create window with default profile
                  activate
                end tell
                """) {
                print("launch: iTerm new window via AppleScript")
                return
            }
        }

        // Already running → Cmd+N (new window/document). Not a second process.
        if isRunning(bundleID: bundleID, path: path) {
            activateOrLaunch(url: url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                KeyboardInjection.injectKeyGlobal(
                    code: "KeyN",
                    command: true,
                    shift: false,
                    control: false,
                    option: false
                )
                print("launch: Cmd+N for \(name)")
            }
            return
        }

        // Not running — first launch only (no new-instance flag).
        activateOrLaunch(url: url)
    }

    private static func isRunning(bundleID: String, path: String) -> Bool {
        let apps = NSWorkspace.shared.runningApplications
        if !bundleID.isEmpty, apps.contains(where: { $0.bundleIdentifier == bundleID }) {
            return true
        }
        let std = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return apps.contains { app in
            guard let b = app.bundleURL?.resolvingSymlinksInPath().path else { return false }
            return b == std
        }
    }

    @discardableResult
    private static func runAppleScript(_ source: String) -> Bool {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        _ = script.executeAndReturnError(&error)
        if let error {
            print("AppleScript error: \(error)")
            return false
        }
        return true
    }
}
