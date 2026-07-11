import AppKit
import Foundation
import ScreenCaptureKit

/// Lightweight window metadata for the web UI (plus optional icon keys).
struct WindowInfo: Sendable {
    let id: Int
    let pid: Int
    let name: String
    let title: String
    let width: Int
    let height: Int
    let path: String?
    let iconKey: String?
}

enum WindowSnapshot {
    static func capture() async -> [WindowInfo] {
        var infos: [WindowInfo] = []

        // Full-display targets first — usable while the lock screen hides app windows.
        // Do NOT wake/jiggle cursor here: this runs every ~2s for the window list.
        let displays = await CaptureManager.listDisplays()
        let locked = SessionState.isScreenLocked

        if displays.isEmpty {
            // Screen still waking / SCShareableContent empty — keep a synthetic
            // main-display entry so the UI still offers "전체 화면".
            let main = CGMainDisplayID()
            let bounds = CGDisplayBounds(main)
            let route = CaptureManager.routeID(forDisplayID: main)
            infos.append(WindowInfo(
                id: Int(route),
                pid: 0,
                name: "전체 화면",
                title: locked ? "잠금화면 · 화면 깨우는 중…" : "전체 화면 · 화면 깨우는 중…",
                width: max(2, Int(bounds.width)),
                height: max(2, Int(bounds.height)),
                path: nil,
                iconKey: "system:display"
            ))
        } else {
            for (index, display) in displays.enumerated() {
                let route = CaptureManager.routeID(forDisplayID: display.displayID)
                let label = displays.count == 1
                    ? (locked ? "잠금화면 · 암호 입력" : "전체 화면 · 잠금 해제용")
                    : (locked
                        ? "잠금화면 · 디스플레이 \(index + 1)"
                        : "전체 화면 · 디스플레이 \(index + 1)")
                infos.append(WindowInfo(
                    id: Int(route),
                    pid: 0,
                    name: "전체 화면",
                    title: label,
                    width: Int(display.width),
                    height: Int(display.height),
                    path: nil,
                    iconKey: "system:display"
                ))
            }
        }

        let windows = await CaptureManager.listWindows()
        infos.append(contentsOf: windows.map { window in
            let pid = window.owningApplication?.processID ?? 0
            var path: String?
            var iconKey: String?

            if pid != 0, let running = NSRunningApplication(processIdentifier: pid) {
                if let bundlePath = running.bundleURL?.path {
                    path = bundlePath
                    iconKey = bundlePath
                } else {
                    iconKey = "pid:\(pid)"
                }
            }

            return WindowInfo(
                id: Int(window.windowID),
                pid: Int(pid),
                name: window.owningApplication?.applicationName ?? "?",
                title: window.title ?? "",
                width: Int(window.frame.width),
                height: Int(window.frame.height),
                path: path,
                iconKey: iconKey
            )
        })
        return infos
    }

    /// Build a `windows` JSON payload. Icons are only attached for keys the peer has not seen yet.
    static func jsonMessage(
        for infos: [WindowInfo],
        knownIconKeys: inout Set<String>,
        forceIcons: Bool = false
    ) -> String? {
        let list: [[String: Any]] = infos.map { info in
            var row: [String: Any] = [
                "id": info.id,
                "pid": info.pid,
                "name": info.name,
                "title": info.title,
                "w": info.width,
                "h": info.height,
            ]
            if let path = info.path { row["path"] = path }

            if let key = info.iconKey {
                let needsIcon = forceIcons || !knownIconKeys.contains(key)
                if needsIcon, let icon = resolveIcon(key: key) {
                    row["icon"] = icon
                    knownIconKeys.insert(key)
                }
            }
            return row
        }
        return JSONMessage.encode(["type": "windows", "list": list])
    }

    private static func resolveIcon(key: String) -> String? {
        if key == "system:display" {
            // Generic display glyph via SF Symbol if available.
            if let image = NSImage(systemSymbolName: "display", accessibilityDescription: nil) {
                return IconCache.shared.dataURL(for: image, key: key)
            }
            return nil
        }
        if key.hasPrefix("pid:"),
           let pid = Int32(key.dropFirst(4)),
           let running = NSRunningApplication(processIdentifier: pid) {
            return IconCache.shared.dataURL(for: running.icon, key: key)
        }
        return IconCache.shared.dataURL(forFilePath: key)
    }
}
