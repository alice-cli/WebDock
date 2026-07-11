import Foundation

/// App / web brand images (from `MacRemote.png` → `Assets/` → app Resources).
enum BrandIcons {
    /// PNG bytes from the app bundle Resources folder.
    static func resourcePNG(_ name: String) -> Data? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: name, withExtension: "png"),
            Bundle.main.resourceURL?.appendingPathComponent("\(name).png"),
            // Dev: next to executable when not packaged
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(name).png"),
        ]
        for url in candidates {
            guard let url, FileManager.default.fileExists(atPath: url.path) else { continue }
            if let data = try? Data(contentsOf: url), !data.isEmpty { return data }
        }
        return nil
    }

    static var faviconPNG: Data? { resourcePNG("favicon") ?? resourcePNG("favicon-32") }
    static var appleTouchPNG: Data? { resourcePNG("apple-touch-icon") }
    static var favicon192PNG: Data? { resourcePNG("favicon-192") }

    /// HTTP body + content-type for known icon paths, or nil.
    static func httpAsset(path: String) -> (Data, String)? {
        let p = path.lowercased()
        switch p {
        case "/favicon.ico", "/favicon.png", "/favicon-32.png":
            if let d = faviconPNG { return (d, "image/png") }
        case "/apple-touch-icon.png", "/apple-touch-icon":
            if let d = appleTouchPNG { return (d, "image/png") }
        case "/favicon-192.png":
            if let d = favicon192PNG ?? appleTouchPNG { return (d, "image/png") }
        default:
            break
        }
        return nil
    }
}
