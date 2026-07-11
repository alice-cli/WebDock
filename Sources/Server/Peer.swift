import CryptoKit
import Foundation
import Network

/// One HTTP / WebSocket client connection.
/// All mutable state and I/O completions are confined to `peerQueue`.
final class Peer {
    private let connection: NWConnection
    private unowned let server: Server
    private let peerQueue = DispatchQueue(label: "webdock.peer")

    private var buffer = Data()
    private var isUpgraded = false
    private var isFinished = false
    private var sendChain: [(Data, (() -> Void)?)] = []
    private var isSending = false
    /// In-flight + queued binary video frames (H.264 / large images). Used for backpressure.
    private var pendingBinaryCount = 0
    private var isAuthenticated = false

    /// Icon cache keys already delivered to this client.
    private(set) var knownIconKeys = Set<String>()

    /// Last known remote IP (best-effort).
    private var cachedRemoteIP: String = "?"
    /// Window this browser last selected (for presence list; capture is still shared).
    private var viewingWindowID: Int?
    private var viewingAppName: String = ""
    private var viewingTitle: String = ""

    var isWebSocket: Bool {
        peerQueue.sync { isUpgraded }
    }

    init(connection: NWConnection, server: Server) {
        self.connection = connection
        self.server = server
        // No token configured → local-trust mode (still Origin-checked for browsers).
        self.isAuthenticated = (server.authToken == nil)
        self.cachedRemoteIP = Self.ipString(from: connection) ?? "?"
    }

    /// Snapshot for the "connected clients" UI.
    func clientPresence() -> [String: Any] {
        peerQueue.sync {
            var row: [String: Any] = [
                "ip": cachedRemoteIP,
                "app": viewingAppName,
                "title": viewingTitle,
            ]
            if let id = viewingWindowID { row["windowId"] = id }
            return row
        }
    }

    func setViewing(windowId: Int?, app: String, title: String) {
        peerQueue.sync {
            self.viewingWindowID = windowId
            self.viewingAppName = app
            self.viewingTitle = title
        }
    }

    /// Currently selected window for this browser (nil if none).
    func currentViewingWindowID() -> Int? {
        peerQueue.sync { viewingWindowID }
    }

    /// Best-effort client address for input-busy messages.
    func clientIP() -> String {
        peerQueue.sync { cachedRemoteIP }
    }

    /// When true, after remote Cmd+C/X push pasteboard text to this browser.
    private var clipAutoPull = true

    func setClipAutoPull(_ on: Bool) {
        peerQueue.sync { clipAutoPull = on }
    }

    func wantsClipAutoPull() -> Bool {
        peerQueue.sync { clipAutoPull }
    }

    private static func ipString(from connection: NWConnection) -> String? {
        if let path = connection.currentPath,
           let endpoint = path.remoteEndpoint,
           case .hostPort(let host, _) = endpoint {
            return normalizeIP("\(host)")
        }
        if case .hostPort(let host, _) = connection.endpoint {
            return normalizeIP("\(host)")
        }
        return nil
    }

    /// Prefer proxy/tunnel headers (Cloudflare etc.) over the socket peer (often 127.0.0.1).
    private static func clientIP(from headers: [String: String], connection: NWConnection) -> String {
        if let cf = headers["cf-connecting-ip"], !cf.isEmpty {
            return normalizeIP(cf)
        }
        if let real = headers["x-real-ip"], !real.isEmpty {
            return normalizeIP(real)
        }
        if let xff = headers["x-forwarded-for"], !xff.isEmpty {
            // Left-most is the original client (Cloudflare / common proxies).
            let first = xff.split(separator: ",").first.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? xff
            if !first.isEmpty { return normalizeIP(first) }
        }
        if let trueClient = headers["true-client-ip"], !trueClient.isEmpty {
            return normalizeIP(trueClient)
        }
        return ipString(from: connection) ?? "?"
    }

    private static func normalizeIP(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip IPv6 brackets: [::1]
        if s.hasPrefix("["), let end = s.firstIndex(of: "]") {
            s = String(s[s.index(after: s.startIndex)..<end])
        }
        // Strip :port for IPv4 host:port
        if s.filter({ $0 == ":" }).count == 1, let colon = s.firstIndex(of: ":") {
            let host = String(s[..<colon])
            if host.contains(".") { s = host }
        }
        if s.hasPrefix("::ffff:") { s = String(s.dropFirst(7)) }
        return s
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.peerQueue.async {
                switch state {
                case .ready:
                    if let ip = Self.ipString(from: self.connection) {
                        self.cachedRemoteIP = ip
                    }
                    if !self.server.isRemoteIPAllowed(self.connection) {
                        print("connection denied (IP allowlist)")
                        self.finish()
                        return
                    }
                case .failed, .cancelled:
                    self.finish()
                default:
                    break
                }
            }
        }
        connection.start(queue: peerQueue)
        receive()
    }

    // MARK: - Public send API (hop onto peerQueue)

    func sendText(_ text: String) {
        enqueueSend(Self.makeFrame(opcode: 0x1, payload: Data(text.utf8)))
    }

    func sendBinary(_ data: Data) {
        enqueueSend(Self.makeFrame(opcode: 0x2, payload: data))
    }

    /// Video/binary with backpressure: drop delta frames when the socket is backed up.
    /// Keyframes always enqueue (and may clear older non-key video to limit lag).
    func sendBinaryVideo(_ data: Data, isKeyframe: Bool) {
        peerQueue.async {
            // >2 pending → client/network can't keep up; skip non-keyframes.
            if self.pendingBinaryCount >= 2 && !isKeyframe {
                return
            }
            // Extreme backlog: drop older queued binary frames (keep control text).
            if isKeyframe && self.pendingBinaryCount >= 3 {
                self.sendChain.removeAll { item in
                    // WS binary opcode frame starts with 0x82
                    item.0.first == 0x82
                }
                self.pendingBinaryCount = self.isSending ? 1 : 0
            }
            self.pendingBinaryCount += 1
            self.enqueueSend(Self.makeFrame(opcode: 0x2, payload: data)) { [weak self] in
                guard let self else { return }
                self.peerQueue.async {
                    self.pendingBinaryCount = max(0, self.pendingBinaryCount - 1)
                }
            }
        }
    }

    /// Snapshot for adaptive streaming.
    func outboundPressure() -> Int {
        peerQueue.sync { pendingBinaryCount + sendChain.count }
    }

    func updateKnownIconKeys(_ keys: Set<String>) {
        peerQueue.async { self.knownIconKeys = keys }
    }

    func withKnownIconKeys(_ body: (inout Set<String>) -> Void) {
        peerQueue.sync {
            body(&knownIconKeys)
        }
    }

    // MARK: - Lifecycle

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        connection.cancel()
        server.remove(self)
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            // Already on peerQueue (connection started with peerQueue).
            if let data, !data.isEmpty {
                if self.buffer.count + data.count > Self.maxBufferBytes {
                    self.closeProtocol(code: 1009, reason: "buffer overflow")
                    return
                }
                self.buffer.append(data)
                if self.isUpgraded {
                    self.parseWebSocketFrames()
                } else {
                    self.parseHTTP()
                }
            }
            if isComplete || error != nil {
                self.finish()
                return
            }
            if !self.isFinished { self.receive() }
        }
    }

    // MARK: - Limits

    private static let maxBufferBytes = 8 * 1024 * 1024
    private static let maxHeaderBytes = 64 * 1024
    private static let maxFramePayload = 4 * 1024 * 1024
    private static let maxControlPayload = 125

    // MARK: - HTTP

    private func parseHTTP() {
        guard let headerEnd = indexOfCRLFCRLF() else {
            if buffer.count > Self.maxHeaderBytes {
                connection.cancel()
                finish()
            }
            return
        }

        let headerData = buffer.subdata(in: 0..<headerEnd)
        buffer.removeSubrange(0..<(headerEnd + 4))

        guard let header = String(data: headerData, encoding: .utf8) else {
            connection.cancel()
            finish()
            return
        }

        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            connection.cancel()
            finish()
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        let method = (parts.first ?? "GET").uppercased()
        let rawPath = parts.count >= 2 ? parts[1] : "/"
        let headers = parseHeaders(Array(lines.dropFirst()))
        var (path, query) = Self.splitPathAndQuery(rawPath)

        // POST form body (token gate) — merge into query map (body wins over URL).
        if method == "POST" {
            let contentLength = Int(headers["content-length"] ?? "0") ?? 0
            if contentLength > 0 {
                if buffer.count < contentLength {
                    // Put headers back and wait for full body (re-parse next receive).
                    buffer.insert(contentsOf: headerData, at: 0)
                    buffer.insert(contentsOf: Data([13, 10, 13, 10]), at: headerData.count)
                    return
                }
                let bodyData = buffer.prefix(contentLength)
                buffer.removeSubrange(0..<contentLength)
                if let body = String(data: bodyData, encoding: .utf8) {
                    let form = Self.parseFormBody(body)
                    for (k, v) in form { query[k] = v }
                }
            }
        }

        // Cloudflare / reverse-proxy: real client IP lives in headers, not the TCP peer.
        let resolvedIP = Self.clientIP(from: headers, connection: connection)
        cachedRemoteIP = resolvedIP

        // Host / domain gate for every request when configured.
        if let hostHeader = headers["host"], !hostHeader.isEmpty {
            let hostName = hostHeader.split(separator: ":").first.map(String.init) ?? hostHeader
            if !server.isDomainAllowed(hostName) {
                sendHTTPError(403, "Forbidden host")
                return
            }
        }

        if headers["upgrade"]?.lowercased() == "websocket",
           let key = headers["sec-websocket-key"] {
            if !validateWebSocketHandshake(headers: headers, path: path, query: query) {
                sendHTTPError(403, "Forbidden")
                return
            }
            acceptWebSocket(key: key)
            // Presence list: refresh IPs for all browsers after this client joins.
            server.broadcastClients()
            if !buffer.isEmpty {
                parseWebSocketFrames()
            }
            return
        }

        serveStatic(path: path, headers: headers, query: query, method: method)
    }

    /// Extract token from query/form, custom header, or Cookie.
    /// Prefer explicit form/query over cookie so a bad retry is not mixed with an old cookie.
    private func providedToken(query: [String: String], headers: [String: String]) -> String? {
        if let t = query["token"]?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        if let t = headers["x-webdock-token"]?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t
        }
        if let cookie = headers["cookie"] {
            for part in cookie.split(separator: ";") {
                let kv = part.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if kv.count == 2, kv[0] == "webdock_token", !kv[1].isEmpty {
                    return kv[1].removingPercentEncoding ?? kv[1]
                }
            }
        }
        return nil
    }

    /// Returns true only if auth is off, or the provided token matches exactly.
    private func isValidToken(query: [String: String], headers: [String: String]) -> Bool {
        guard let required = server.authToken else { return true }
        guard let provided = providedToken(query: query, headers: headers) else { return false }
        // Exact match only — never concatenate query + cookie.
        guard provided.count == required.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(provided.utf8, required.utf8) { diff |= a ^ b }
        return diff == 0
    }

    private func validateWebSocketHandshake(
        headers: [String: String],
        path: String,
        query: [String: String]
    ) -> Bool {
        // WebSocket only on /ws
        guard path == "/ws" else { return false }

        guard let hostHeader = headers["host"], !hostHeader.isEmpty else { return false }
        let hostName = hostHeader.split(separator: ":").first.map(String.init) ?? hostHeader
        if !server.isDomainAllowed(hostName) { return false }

        if let origin = headers["origin"], !origin.isEmpty {
            guard let originHost = URL(string: origin)?.host else { return false }
            let o = originHost.lowercased()
            let h = hostName.lowercased()
            let loopbacks: Set<String> = ["localhost", "127.0.0.1", "::1"]
            let same = o == h
            let loopPair = loopbacks.contains(o) && loopbacks.contains(h)
            let domainOK = server.isDomainAllowed(originHost)
            if !(same || loopPair || domainOK) { return false }
        }

        // Token required for upgrade when configured — wrong/missing → no access.
        guard isValidToken(query: query, headers: headers) else { return false }
        isAuthenticated = true
        return true
    }

    private func parseHeaders(_ lines: [String]) -> [String: String] {
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        return headers
    }

    private func acceptWebSocket(key: String) {
        let accept = Data(
            Insecure.SHA1.hash(
                data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)
            )
        ).base64EncodedString()

        let response =
            "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: \(accept)\r\n\r\n"

        enqueueSend(Data(response.utf8), priority: true)
        isUpgraded = true
        isAuthenticated = true
        server.onWebSocketOpen(self)
    }

    private func serveStatic(
        path: String,
        headers: [String: String],
        query: [String: String],
        method: String = "GET"
    ) {
        // Brand icons — public (no token) so gate page / tab icon work before login.
        if method == "GET" || method == "HEAD", let asset = BrandIcons.httpAsset(path: path) {
            sendBinary(asset.0, contentType: asset.1, cacheable: true)
            return
        }

        guard path == "/" || path.hasPrefix("/index") else {
            sendHTTPError(404, "Not Found")
            return
        }

        // Token configured → page itself is locked without a valid token.
        if server.authToken != nil {
            if !isValidToken(query: query, headers: headers) {
                let attempted = query["token"] != nil || headers["x-webdock-token"] != nil
                // Clear stale cookie so retries never become cookie+form mashups.
                sendGatePage(wrongToken: attempted || cookieToken(headers) != nil)
                return
            }
            // Valid token → wake monitor if asleep (no always-on; only on real access).
            server.onAuthenticatedHTTPAccess()
            // POST success → redirect to clean URL (no token in address bar / no re-POST).
            if method == "POST" {
                sendRedirectHome(token: providedToken(query: query, headers: headers))
                return
            }
        } else {
            // Auth off: loading the UI still counts as remote access for wake.
            server.onAuthenticatedHTTPAccess()
        }

        let body = Data(WebUI.indexHTML.utf8)
        var head =
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: text/html; charset=utf-8\r\n" +
            "Cache-Control: no-store\r\n" +
            "Content-Length: \(body.count)\r\n"
        // Persist auth for subsequent navigations (HttpOnly not usable by WS; still reduces URL sharing a bit).
        if let token = providedToken(query: query, headers: headers), server.authToken != nil {
            let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
            head += "Set-Cookie: webdock_token=\(encoded); Path=/; SameSite=Strict; Max-Age=604800\r\n"
        }
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        enqueueSend(out) { [weak self] in self?.finish() }
    }

    private func cookieToken(_ headers: [String: String]) -> String? {
        guard let cookie = headers["cookie"] else { return nil }
        for part in cookie.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            if kv.count == 2, kv[0] == "webdock_token", !kv[1].isEmpty {
                return kv[1].removingPercentEncoding ?? kv[1]
            }
        }
        return nil
    }

    /// 303 to `/` after POST login; set cookie so WS can authenticate without query mashups.
    private func sendRedirectHome(token: String?) {
        var head =
            "HTTP/1.1 303 See Other\r\n" +
            "Location: /\r\n" +
            "Cache-Control: no-store\r\n"
        if let token, !token.isEmpty {
            let encoded = token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token
            head += "Set-Cookie: webdock_token=\(encoded); Path=/; SameSite=Strict; Max-Age=604800\r\n"
        }
        head += "Content-Length: 0\r\nConnection: close\r\n\r\n"
        enqueueSend(Data(head.utf8)) { [weak self] in self?.finish() }
    }

    /// Minimal unlock form — no app UI without a correct token.
    private func sendGatePage(wrongToken: Bool) {
        let message = wrongToken
            ? "토큰이 올바르지 않습니다. 다시 입력하세요."
            : "이 서버는 토큰이 필요합니다."
        // POST + autocomplete off + clear cookie: prevents wrong+new token accumulation.
        let html = """
        <!doctype html><html lang="ko"><head>
        <meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>WebDock — 접근 거부</title>
        <link rel="icon" type="image/png" href="/favicon.png">
        <link rel="apple-touch-icon" href="/apple-touch-icon.png">
        <style>
          body{font-family:-apple-system,system-ui,sans-serif;background:#0a0b0d;color:#e8eef6;
               display:flex;min-height:100vh;align-items:center;justify-content:center;margin:0}
          .card{background:#16181c;border:1px solid #2c2e33;padding:24px;width:min(360px,92vw)}
          h1{font-size:16px;margin:0 0 8px} p{font-size:13px;color:#9a9da3;margin:0 0 16px}
          input{width:100%;box-sizing:border-box;padding:10px;border:1px solid #2c2e33;background:#0a0b0d;color:#fff;margin-bottom:10px}
          button{width:100%;padding:10px;border:0;background:#4f8cff;color:#fff;font-weight:600;cursor:pointer}
          .err{color:#f87171}
        </style></head><body><div class="card">
        <h1>WebDock</h1>
        <p class="\(wrongToken ? "err" : "")">\(message)</p>
        <form method="POST" action="/" autocomplete="off">
          <input name="token" type="password" value="" placeholder="접속 토큰"
                 autocomplete="off" autocapitalize="off" spellcheck="false" autofocus required>
          <button type="submit">접속</button>
        </form>
        </div></body></html>
        """
        let body = Data(html.utf8)
        let head =
            "HTTP/1.1 401 Unauthorized\r\n" +
            "Content-Type: text/html; charset=utf-8\r\n" +
            "Cache-Control: no-store\r\n" +
            // Wipe any previous token cookie so the next attempt is clean.
            "Set-Cookie: webdock_token=; Path=/; Max-Age=0; SameSite=Strict\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        enqueueSend(out) { [weak self] in self?.finish() }
    }

    private func sendBinary(_ body: Data, contentType: String, cacheable: Bool) {
        let cache = cacheable
            ? "public, max-age=86400"
            : "no-store"
        let head =
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: \(contentType)\r\n" +
            "Cache-Control: \(cache)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        enqueueSend(out) { [weak self] in self?.finish() }
    }

    private func sendHTTPError(_ code: Int, _ reason: String) {
        let body = Data(reason.utf8)
        let head =
            "HTTP/1.1 \(code) \(reason)\r\n" +
            "Content-Length: \(body.count)\r\n" +
            "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        enqueueSend(out) { [weak self] in self?.finish() }
    }

    // MARK: - WebSocket framing

    private func parseWebSocketFrames() {
        while true {
            guard buffer.count >= 2 else { return }
            let b0 = buffer[0]
            let b1 = buffer[1]
            let fin = (b0 & 0x80) != 0
            let opcode = b0 & 0x0F
            let masked = (b1 & 0x80) != 0
            var index = 2

            // Clients must mask.
            if !masked {
                closeProtocol(code: 1002, reason: "client frames must be masked")
                return
            }

            // Extended length (use UInt64 to avoid Int overflow traps).
            let lengthBits = UInt64(b1 & 0x7F)
            let payloadLength: UInt64
            if lengthBits == 126 {
                guard buffer.count >= 4 else { return }
                payloadLength = (UInt64(buffer[2]) << 8) | UInt64(buffer[3])
                index = 4
            } else if lengthBits == 127 {
                guard buffer.count >= 10 else { return }
                var len: UInt64 = 0
                for i in 2..<10 {
                    len = (len << 8) | UInt64(buffer[i])
                }
                // Reject lengths that don't fit Int or exceed cap.
                payloadLength = len
                index = 10
            } else {
                payloadLength = lengthBits
            }

            let isControl = opcode >= 0x8
            let maxAllowed = isControl ? UInt64(Self.maxControlPayload) : UInt64(Self.maxFramePayload)
            if payloadLength > maxAllowed {
                closeProtocol(code: 1009, reason: "payload too large")
                return
            }

            // Fragmentation: reject non-FIN data frames (browsers send unfragmented).
            if !fin && !isControl {
                closeProtocol(code: 1003, reason: "fragmentation not supported")
                return
            }

            guard buffer.count >= index + 4 else { return }
            let mask = [buffer[index], buffer[index + 1], buffer[index + 2], buffer[index + 3]]
            index += 4

            let payloadStart = index
            let payloadEnd = index + Int(payloadLength)
            guard buffer.count >= payloadEnd else { return }

            var payload = [UInt8](buffer[payloadStart..<payloadEnd])
            for i in 0..<payload.count { payload[i] ^= mask[i % 4] }
            buffer.removeSubrange(0..<payloadEnd)

            switch opcode {
            case 0x1: // text
                handleTextPayload(payload)
            case 0x8: // close
                finish()
                return
            case 0x9: // ping → pong
                enqueueSend(Self.makeFrame(opcode: 0xA, payload: Data(payload)))
            case 0xA: // pong
                break
            default:
                // Ignore unknown / continuation after reject path.
                break
            }
        }
    }

    private func handleTextPayload(_ payload: [UInt8]) {
        guard let text = String(bytes: payload, encoding: .utf8),
              let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return }

        // Handshake already required a valid token (if configured). Never accept
        // late auth to open an unauthenticated socket.
        guard isAuthenticated else {
            closeProtocol(code: 1008, reason: "unauthorized")
            return
        }
        server.handleCommand(object, from: self)
    }

    private func closeProtocol(code: UInt16, reason: String) {
        var payload = Data()
        payload.append(UInt8(code >> 8))
        payload.append(UInt8(code & 0xFF))
        payload.append(contentsOf: reason.utf8.prefix(Self.maxControlPayload - 2))
        enqueueSend(Self.makeFrame(opcode: 0x8, payload: payload)) { [weak self] in
            self?.finish()
        }
    }

    // MARK: - Send queue (serialized)

    private func enqueueSend(_ data: Data, priority: Bool = false, done: (() -> Void)? = nil) {
        peerQueue.async {
            if priority {
                self.sendChain.insert((data, done), at: 0)
            } else {
                self.sendChain.append((data, done))
            }
            self.pumpSend()
        }
    }

    private func pumpSend() {
        // Must run on peerQueue.
        guard !isSending, let next = sendChain.first else { return }
        sendChain.removeFirst()
        isSending = true
        connection.send(content: next.0, completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            self.peerQueue.async {
                self.isSending = false
                next.1?()
                self.pumpSend()
            }
        })
    }

    private static func makeFrame(opcode: UInt8, payload: Data) -> Data {
        var frame = Data()
        frame.append(0x80 | opcode)
        let length = payload.count
        if length < 126 {
            frame.append(UInt8(length))
        } else if length <= 0xFFFF {
            frame.append(126)
            frame.append(UInt8(length >> 8))
            frame.append(UInt8(length & 0xFF))
        } else {
            frame.append(127)
            let len = UInt64(length)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((len >> UInt64(shift)) & 0xFF))
            }
        }
        frame.append(payload)
        return frame
    }

    // MARK: - Helpers

    private func indexOfCRLFCRLF() -> Int? {
        let marker = Data([13, 10, 13, 10])
        guard let range = buffer.range(of: marker) else { return nil }
        return range.lowerBound
    }

    private static func splitPathAndQuery(_ raw: String) -> (String, [String: String]) {
        guard let q = raw.firstIndex(of: "?") else { return (raw, [:]) }
        let path = String(raw[..<q])
        let queryString = String(raw[raw.index(after: q)...])
        return (path, parseFormBody(queryString))
    }

    /// application/x-www-form-urlencoded or query string. Last value wins (no concat).
    private static func parseFormBody(_ raw: String) -> [String: String] {
        var query: [String: String] = [:]
        for pair in raw.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].replacingOccurrences(of: "+", with: " ")
                    .removingPercentEncoding ?? parts[0]
                let val = parts[1].replacingOccurrences(of: "+", with: " ")
                    .removingPercentEncoding ?? parts[1]
                query[key] = val
            } else if parts.count == 1 {
                let key = parts[0].replacingOccurrences(of: "+", with: " ")
                    .removingPercentEncoding ?? parts[0]
                query[key] = ""
            }
        }
        return query
    }
}
