import AppKit
import Foundation

enum AppsCatalog {
    static let searchDirectories: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        NSHomeDirectory() + "/Applications",
    ]

    struct AppEntry {
        let name: String
        let path: String
    }

    /// Scan standard Application folders for `.app` bundles (deduped by name).
    static func listInstalledApps() -> [AppEntry] {
        let fileManager = FileManager.default
        var entries: [AppEntry] = []
        var seen = Set<String>()

        for directory in searchDirectories {
            guard let items = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for item in items where item.hasSuffix(".app") {
                let name = String(item.dropLast(4))
                guard seen.insert(name).inserted else { continue }
                entries.append(AppEntry(name: name, path: directory + "/" + item))
            }
        }

        return entries.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Only allow launching bundles that resolve under known Applications directories.
    static func isAllowedLaunchPath(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard standardized.hasSuffix(".app") else { return false }
        // Reject path traversal tricks after standardization.
        guard !standardized.contains("/../") else { return false }
        for directory in searchDirectories {
            let dir = URL(fileURLWithPath: directory).resolvingSymlinksInPath().path
            if standardized == dir { continue }
            if standardized.hasPrefix(dir.hasSuffix("/") ? dir : dir + "/") {
                return true
            }
        }
        return false
    }

    static func jsonMessage(includingIcons: Bool = true) -> String? {
        let list: [[String: String]] = listInstalledApps().map { entry in
            var row: [String: String] = ["name": entry.name, "path": entry.path]
            if includingIcons, let icon = IconCache.shared.dataURL(forFilePath: entry.path) {
                row["icon"] = icon
            }
            return row
        }
        return JSONMessage.encode(["type": "apps", "list": list])
    }
}
