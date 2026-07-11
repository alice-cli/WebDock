import Foundation
import Security

/// Persistent WebDock settings (INI under Application Support).
struct AppConfig: Equatable {
    var serverEnabled: Bool = true
    var port: UInt16 = 8080
    /// Bind on all interfaces (LAN). When false, loopback only.
    var allowLAN: Bool = false
    /// Shared secret for WebSocket auth. Empty = no token required.
    var token: String = ""
    /// Allowed Origin / Host domain names (e.g. `myhost.local`). Empty = same-host / loopback rules only.
    var allowedDomains: [String] = []
    /// When true, only `allowedIPs` may connect (plus loopback always).
    var ipAllowlistEnabled: Bool = false
    var allowedIPs: [String] = []

    var hasToken: Bool { !token.isEmpty }

    // MARK: - Paths

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("WebDock", isDirectory: true)
    }

    static var iniURL: URL {
        supportDirectory.appendingPathComponent("config.ini")
    }

    static var exists: Bool {
        FileManager.default.fileExists(atPath: iniURL.path)
    }

    // MARK: - Token

    static func generateToken(bytes: Int = 24) -> String {
        var buf = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
        let data = Data(buf)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Load / Save

    static func load() -> AppConfig? {
        guard exists,
              let text = try? String(contentsOf: iniURL, encoding: .utf8)
        else { return nil }
        return parse(ini: text)
    }

    /// Load file if present, else defaults (does not create file).
    static func loadOrDefault() -> AppConfig {
        load() ?? AppConfig()
    }

    @discardableResult
    func save() throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: Self.supportDirectory, withIntermediateDirectories: true)
        let text = serialize()
        try text.write(to: Self.iniURL, atomically: true, encoding: .utf8)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.iniURL.path)
        return Self.iniURL
    }

    // MARK: - Connection URLs (for UI)

    func connectionURLs(lanAddresses: [String]) -> [String] {
        var urls: [String] = []
        let tokenQuery = hasToken ? "?token=\(token)" : ""
        urls.append("http://127.0.0.1:\(port)/\(tokenQuery.hasPrefix("?") ? "" : "")")
        // page URL without embedding token in path messily
        urls = ["http://127.0.0.1:\(port)"]
        if allowLAN {
            for ip in lanAddresses {
                urls.append("http://\(ip):\(port)")
            }
        }
        return urls
    }

    func websocketHint(for host: String) -> String {
        if hasToken {
            return "ws://\(host):\(port)/ws?token=\(token)"
        }
        return "ws://\(host):\(port)/ws"
    }

    // MARK: - Access checks

    func isDomainAllowed(_ host: String) -> Bool {
        let h = host.lowercased()
        let loopbacks: Set<String> = ["localhost", "127.0.0.1", "::1"]
        if loopbacks.contains(h) { return true }
        if allowedDomains.isEmpty {
            // No list → only loopback unless LAN; Peer still checks same-host Origin.
            return true
        }
        return allowedDomains.contains { $0.lowercased() == h }
            || allowedDomains.contains { hostMatchesPattern(h, pattern: $0.lowercased()) }
    }

    func isIPAllowed(_ ip: String) -> Bool {
        let normalized = Self.normalizeIP(ip)
        let loopbacks: Set<String> = ["127.0.0.1", "::1", "localhost"]
        if loopbacks.contains(normalized) || normalized.hasPrefix("127.") { return true }
        guard ipAllowlistEnabled else { return true }
        if allowedIPs.isEmpty { return false }
        return allowedIPs.contains { Self.normalizeIP($0) == normalized }
    }

    // MARK: - INI

    private static func parse(ini: String) -> AppConfig {
        var cfg = AppConfig()
        var section = ""
        for raw in ini.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).lowercased()
                continue
            }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            switch (section, key) {
            case ("server", "enabled"): cfg.serverEnabled = parseBool(value)
            case ("server", "port"):
                if let p = UInt16(value) { cfg.port = p }
            case ("server", "allow_lan"): cfg.allowLAN = parseBool(value)
            case ("auth", "token"): cfg.token = value
            case ("access", "ip_allowlist_enabled"): cfg.ipAllowlistEnabled = parseBool(value)
            case ("access", "domains"): cfg.allowedDomains = parseList(value)
            case ("access", "ips"): cfg.allowedIPs = parseList(value)
            default: break
            }
        }
        return cfg
    }

    private func serialize() -> String {
        func list(_ items: [String]) -> String {
            items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
        }
        return """
        # WebDock configuration — do not share this file (contains token).
        # Path: \(Self.iniURL.path)

        [server]
        enabled = \(serverEnabled ? "true" : "false")
        port = \(port)
        allow_lan = \(allowLAN ? "true" : "false")

        [auth]
        token = \(token)

        [access]
        ip_allowlist_enabled = \(ipAllowlistEnabled ? "true" : "false")
        domains = \(list(allowedDomains))
        ips = \(list(allowedIPs))
        """
    }

    private static func parseBool(_ s: String) -> Bool {
        ["1", "true", "yes", "on"].contains(s.lowercased())
    }

    private static func parseList(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func normalizeIP(_ ip: String) -> String {
        var s = ip.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.hasPrefix("::ffff:") { s = String(s.dropFirst(7)) }
        return s
    }

    private func hostMatchesPattern(_ host: String, pattern: String) -> Bool {
        // Simple suffix match: "*.example.com" or "example.com"
        if pattern.hasPrefix("*.") {
            let suffix = String(pattern.dropFirst(1)) // ".example.com"
            return host.hasSuffix(suffix) || host == String(pattern.dropFirst(2))
        }
        return host == pattern
    }
}
