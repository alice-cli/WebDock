import AppKit
import Foundation
import Network
import CoreGraphics
import ScreenCaptureKit

/// HTTP + WebSocket server that streams a selected window and accepts remote input.
final class Server {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "webdock.server")
    private let commandQueue = DispatchQueue(label: "webdock.commands")
    private var peers: [ObjectIdentifier: Peer] = [:]
    private var pushTimer: DispatchSourceTimer?
    private var pushInFlight = false
    private var isRunning = false
    /// Rate-limit "input busy" notices per peer (seconds).
    private var lastBusyNotify: [ObjectIdentifier: CFAbsoluteTime] = [:]

    let capture = CaptureManager()
    private(set) var config: AppConfig

    var authToken: String? {
        config.hasToken ? config.token : nil
    }

    var allowLAN: Bool { config.allowLAN }

    init(config: AppConfig) throws {
        self.config = config
        let port = config.port

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let nwPort = NWEndpoint.Port(rawValue: port)!

        if config.allowLAN {
            listener = try NWListener(using: parameters, on: nwPort)
        } else {
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: nwPort
            )
            listener = try NWListener(using: parameters)
        }

        capture.onFrame = { [weak self] windowID, data in
            self?.sendFrame(windowID: windowID, data: data)
        }
        capture.onH264Config = { [weak self] windowID, avcC, codec, w, h in
            self?.sendH264Config(windowID: windowID, avcC: avcC, codec: codec, width: w, height: h)
        }
        capture.onH264Sample = { [weak self] windowID, data, key, us in
            self?.sendH264Sample(windowID: windowID, data: data, keyframe: key, ptsUs: us)
        }
    }

    /// Legacy convenience.
    convenience init(port: UInt16, allowLAN: Bool = false, authToken: String? = nil) throws {
        var cfg = AppConfig()
        cfg.port = port
        cfg.allowLAN = allowLAN
        cfg.token = authToken ?? ""
        try self.init(config: cfg)
    }

    /// Peers that already triggered session retain (one retain per WS client).
    private var sessionPowerPeers: Set<ObjectIdentifier> = []

    func start() {
        guard !isRunning else { return }
        isRunning = true
        // Do NOT keep the display awake just because the server is running.
        // Wake only when an authenticated client connects (see noteRemoteSession).

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            let peer = Peer(connection: connection, server: self)
            self.queue.async {
                self.peers[ObjectIdentifier(peer)] = peer
                // No wake here — TCP connect is unauthenticated.
            }
            peer.start()
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("listener failed: \(error)")
            }
        }
        listener.start(queue: queue)

        // Metrics every 1s. Window list / clients every 2s (only useful while clients exist).
        var tick = 0
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            tick += 1
            self.broadcastMetrics()
            if tick % 2 == 0 {
                self.pushWindows()
                self.broadcastClients()
            }
        }
        timer.resume()
        pushTimer = timer
    }

    func stop() {
        isRunning = false
        pushTimer?.cancel()
        pushTimer = nil
        listener.cancel()
        queue.async {
            // Release all session holds.
            let n = self.sessionPowerPeers.count
            self.sessionPowerPeers.removeAll()
            for _ in 0..<n { DisplayPower.release() }
            self.peers.removeAll()
        }
        Task { await capture.stop() }
    }

    func remove(_ peer: Peer) {
        queue.async {
            let id = ObjectIdentifier(peer)
            InputArbitration.release(id)
            self.lastBusyNotify[id] = nil
            if self.sessionPowerPeers.remove(id) != nil {
                DisplayPower.release()
            }
            let oldID = self.peers[id]?.currentViewingWindowID()
            self.peers[id] = nil
            if let oldID {
                self.releaseCaptureIfUnused(windowID: Self.routeID(from: oldID))
            }
            self.broadcastClients()
        }
    }

    /// HTTP login / page load with valid token — wake monitor once (no retain yet).
    func onAuthenticatedHTTPAccess() {
        DisplayPower.wakeOnAuthenticatedAccess()
    }

    /// Authenticated WebSocket session: wake + keep display on until disconnect.
    private func noteRemoteSession(_ peer: Peer) {
        let id = ObjectIdentifier(peer)
        queue.async {
            if self.sessionPowerPeers.insert(id).inserted {
                DisplayPower.retain(reason: "WebDock remote client")
            }
        }
    }

    /// Notify all browsers which IPs are connected and what they last selected.
    func broadcastClients() {
        queue.async {
            let list: [[String: Any]] = self.peers.values
                .filter(\.isWebSocket)
                .map { $0.clientPresence() }
            guard let message = JSONMessage.encode(["type": "clients", "list": list]) else { return }
            for (_, peer) in self.peers where peer.isWebSocket {
                peer.sendText(message)
            }
        }
    }

    func broadcastMetrics() {
        queue.async {
            guard let message = SystemMetrics.jsonMessage() else { return }
            for (_, peer) in self.peers where peer.isWebSocket {
                peer.sendText(message)
            }
        }
    }

    func isDomainAllowed(_ host: String) -> Bool {
        config.isDomainAllowed(host)
    }

    func isRemoteIPAllowed(_ connection: NWConnection) -> Bool {
        // TCP peer check only (headers not available yet at .ready).
        // Loopback is always allowed so Cloudflare tunnel (cloudflared → 127.0.0.1) works;
        // real client IP is applied later from CF-Connecting-IP / X-Forwarded-For for the UI list.
        guard config.ipAllowlistEnabled else { return true }
        guard let ip = Self.remoteIP(from: connection) else {
            return !config.allowLAN
        }
        if config.isIPAllowed(ip) { return true }
        // Tunnel local hop
        let n = ip.lowercased()
        if n == "127.0.0.1" || n == "::1" || n.hasPrefix("127.") { return true }
        return false
    }

    private static func remoteIP(from connection: NWConnection) -> String? {
        if let path = connection.currentPath,
           let endpoint = path.remoteEndpoint,
           case .hostPort(let host, _) = endpoint {
            return "\(host)"
        }
        if case .hostPort(let host, _) = connection.endpoint {
            return "\(host)"
        }
        return nil
    }

    // MARK: - Per-window frame fan-out

    /// Send still image (JPEG/PNG) only to browsers currently viewing this window.
    private func sendFrame(windowID: CGWindowID, data: Data) {
        let wid = Int(windowID)
        queue.async {
            for (_, peer) in self.peers where peer.isWebSocket {
                if peer.currentViewingWindowID() == wid {
                    peer.sendBinary(data)
                }
            }
        }
    }

    /// H.264 decoder config (JSON). Client configures WebCodecs VideoDecoder.
    private func sendH264Config(
        windowID: CGWindowID,
        avcC: Data,
        codec: String,
        width: Int,
        height: Int
    ) {
        let wid = Int(windowID)
        let b64 = avcC.base64EncodedString()
        guard let message = JSONMessage.encode([
            "type": "h264config",
            "windowId": wid,
            "codec": codec,
            "width": width,
            "height": height,
            "description": b64,
        ]) else { return }
        queue.async {
            for (_, peer) in self.peers where peer.isWebSocket {
                if peer.currentViewingWindowID() == wid {
                    peer.sendText(message)
                }
            }
        }
    }

    /// Binary H.264 sample packet:
    /// `[0]=0x01` type, `[1]=flags(key=1)`, `[2..9]=pts_us BE i64`, `[10..13]=len BE u32`, payload AVCC.
    private func sendH264Sample(windowID: CGWindowID, data: Data, keyframe: Bool, ptsUs: Int64) {
        let wid = Int(windowID)
        var packet = Data()
        packet.reserveCapacity(14 + data.count)
        packet.append(0x01)
        packet.append(keyframe ? 0x01 : 0x00)
        var pts = ptsUs.bigEndian
        withUnsafeBytes(of: &pts) { packet.append(contentsOf: $0) }
        var len = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &len) { packet.append(contentsOf: $0) }
        packet.append(data)
        queue.async {
            for (_, peer) in self.peers where peer.isWebSocket {
                if peer.currentViewingWindowID() == wid {
                    peer.sendBinaryVideo(packet, isKeyframe: keyframe)
                }
            }
        }
    }

    /// Stop capturing a window when no peer still has it selected.
    private func releaseCaptureIfUnused(windowID: CGWindowID) {
        let wid = Int(windowID)
        let stillNeeded = peers.values.contains {
            $0.isWebSocket && $0.currentViewingWindowID() == wid
        }
        if !stillNeeded {
            capture.stopStreaming(windowID: windowID)
        }
    }

    // MARK: - WebSocket lifecycle

    func onWebSocketOpen(_ peer: Peer) {
        // Token already validated at WS handshake (or auth disabled).
        noteRemoteSession(peer)
        Task {
            let infos = await WindowSnapshot.capture()
            self.queue.async {
                peer.withKnownIconKeys { keys in
                    if let message = WindowSnapshot.jsonMessage(
                        for: infos,
                        knownIconKeys: &keys,
                        forceIcons: true
                    ) {
                        peer.sendText(message)
                    }
                }
                self.sendIMEState(to: peer)
                self.broadcastClients()
                self.broadcastMetrics()
            }
        }
    }

    private func pushWindows() {
        queue.async {
            guard !self.pushInFlight else { return }
            self.pushInFlight = true
            Task {
                let infos = await WindowSnapshot.capture()
                self.queue.async {
                    for (_, peer) in self.peers where peer.isWebSocket {
                        peer.withKnownIconKeys { keys in
                            if let message = WindowSnapshot.jsonMessage(for: infos, knownIconKeys: &keys) {
                                peer.sendText(message)
                            }
                        }
                    }
                    self.pushInFlight = false
                }
            }
        }
    }

    private func sendIMEState(to peer: Peer) {
        let state = InputSource.currentState()
        if let message = JSONMessage.imeState(isKorean: state.isKorean, label: state.label) {
            peer.sendText(message)
        }
    }

    // MARK: - Commands

    func handleCommand(_ json: [String: Any], from peer: Peer) {
        commandQueue.async { [weak self] in
            self?.dispatchCommand(json, from: peer)
        }
    }

    private func dispatchCommand(_ json: [String: Any], from peer: Peer) {
        guard let type = json["type"] as? String else { return }
        // Per-browser target: window SCWindow and/or full-display route.
        let peerWindow = peerTargetWindow(peer)
        let displayID = peerTargetDisplayID(peer)

        switch type {
        case "select":
            if let id = jsonInt(json, "id") {
                let resolved = Self.routeID(from: id)
                let previous = peer.currentViewingWindowID().map { Self.routeID(from: $0) }
                // Bind this browser immediately so frames route correctly.
                peer.setViewing(windowId: id, app: "…", title: "")
                if CaptureManager.isDisplayRoute(resolved) {
                    DisplayPower.wakeHard()
                }
                capture.ensureStreaming(windowID: resolved)
                // New viewer → IDR so WebCodecs can start without waiting for GOP.
                capture.requestKeyframe(windowID: resolved)
                if let previous, previous != resolved {
                    queue.async { self.releaseCaptureIfUnused(windowID: previous) }
                }
                Task {
                    if CaptureManager.isDisplayRoute(resolved),
                       let did = CaptureManager.displayID(fromRoute: resolved) {
                        let locked = SessionState.isScreenLocked
                        peer.setViewing(
                            windowId: id,
                            app: "전체 화면",
                            title: locked ? "잠금화면" : "디스플레이 \(did)"
                        )
                    } else {
                        let windows = await CaptureManager.listWindows()
                        let match = windows.first { Int($0.windowID) == id }
                        let app = match?.owningApplication?.applicationName ?? "?"
                        let title = match?.title ?? ""
                        peer.setViewing(windowId: id, app: app, title: title)
                    }
                    self.broadcastClients()
                }
            }

        case "down", "move", "up":
            guard let phase = MouseInjection.Phase(rawValue: type),
                  let x = jsonDouble(json, "x"),
                  let y = jsonDouble(json, "y")
            else { return }
            let kind: InputArbitration.Kind = phase == .down ? .down : (phase == .up ? .up : .move)
            guard claimInput(peer, kind: kind) else { return }
            if let displayID {
                MouseInjection.injectDisplay(
                    phase: phase,
                    xFraction: x,
                    yFraction: y,
                    button: jsonInt(json, "button") ?? 0,
                    clickCount: jsonInt(json, "count") ?? 1,
                    displayID: displayID
                )
            } else if let peerWindow {
                MouseInjection.inject(
                    phase: phase,
                    xFraction: x,
                    yFraction: y,
                    button: jsonInt(json, "button") ?? 0,
                    clickCount: jsonInt(json, "count") ?? 1,
                    window: peerWindow
                )
            }

        case "click":
            if let x = jsonDouble(json, "x"), let y = jsonDouble(json, "y") {
                guard claimInput(peer, kind: .down) else { return }
                if let displayID {
                    MouseInjection.clickDisplay(xFraction: x, yFraction: y, displayID: displayID)
                } else if let peerWindow {
                    MouseInjection.click(xFraction: x, yFraction: y, window: peerWindow)
                }
                _ = claimInput(peer, kind: .up)
            }

        case "scroll":
            if let x = jsonDouble(json, "x"), let y = jsonDouble(json, "y") {
                guard claimInput(peer, kind: .scroll) else { return }
                if let displayID {
                    MouseInjection.scrollDisplay(
                        deltaX: jsonDouble(json, "dx") ?? 0,
                        deltaY: jsonDouble(json, "dy") ?? 0,
                        xFraction: x,
                        yFraction: y,
                        displayID: displayID
                    )
                } else if let peerWindow {
                    MouseInjection.scroll(
                        deltaX: jsonDouble(json, "dx") ?? 0,
                        deltaY: jsonDouble(json, "dy") ?? 0,
                        xFraction: x,
                        yFraction: y,
                        window: peerWindow
                    )
                }
            }

        case "text":
            if let value = json["value"] as? String {
                guard claimInput(peer, kind: .text) else { return }
                let replace = max(0, jsonInt(json, "replace") ?? 0)
                if displayID != nil {
                    // Lock screen often blocks paste — type unicode directly.
                    KeyboardInjection.injectTextGlobal(value, replace: replace)
                } else if let peerWindow {
                    KeyboardInjection.injectText(value, window: peerWindow, replace: replace)
                }
            }

        case "ime":
            // Absolute 한/영 from client when provided (avoids double-toggle races).
            let focus = peerWindow ?? capture.selectedWindow
            let state: InputSource.State
            if let want = json["korean"] as? Bool {
                state = InputSource.setKorean(want, focusing: focus)
            } else if let n = json["korean"] as? NSNumber {
                state = InputSource.setKorean(n.boolValue, focusing: focus)
            } else {
                state = InputSource.toggle(focusing: focus)
            }
            if let message = JSONMessage.imeState(isKorean: state.isKorean, label: state.label) {
                peer.sendText(message)
            }

        case "imeState":
            sendIMEState(to: peer)

        /// Client asks to re-apply expected IME (auto or manual heal).
        case "imeHeal":
            let want: Bool = {
                if let b = json["korean"] as? Bool { return b }
                if let n = json["korean"] as? NSNumber { return n.boolValue }
                return InputSource.desiredKoreanOrNil() ?? InputSource.currentState().isKorean
            }()
            let hard = (json["hard"] as? Bool) ?? (json["hard"] as? NSNumber)?.boolValue ?? false
            let focus = peerWindow ?? capture.selectedWindow
            let state = hard
                ? InputSource.hardHeal(wantKorean: want, focusing: focus)
                : InputSource.setKorean(want, focusing: focus)
            if let message = JSONMessage.imeState(isKorean: state.isKorean, label: state.label) {
                peer.sendText(message)
            }

        case "resize":
            // Display capture size follows the panel; only resize real windows.
            if let width = jsonInt(json, "w"), let height = jsonInt(json, "h"), let peerWindow {
                WindowResize.resize(peerWindow, width: Double(width), height: Double(height))
                capture.scheduleRestart(windowID: peerWindow.windowID)
            }

        case "key":
            if let code = json["code"] as? String {
                guard claimInput(peer, kind: .key) else { return }
                let command = json["meta"] as? Bool ?? false
                let control = json["ctrl"] as? Bool ?? false
                let shift = json["shift"] as? Bool ?? false
                let option = json["alt"] as? Bool ?? false
                // Track browser 한/A for UI only — never switch IME mid-key
                // (auto-heal was breaking Hangul composition → 자모 분리).
                if let expect = json["ime"] as? Bool {
                    InputSource.noteDesiredKorean(expect)
                } else if let n = json["ime"] as? NSNumber {
                    InputSource.noteDesiredKorean(n.boolValue)
                }
                if displayID != nil {
                    KeyboardInjection.injectKeyGlobal(
                        code: code,
                        command: command,
                        shift: shift,
                        control: control,
                        option: option
                    )
                } else if let peerWindow {
                    KeyboardInjection.injectKey(
                        code: code,
                        command: command,
                        shift: shift,
                        control: control,
                        option: option,
                        window: peerWindow
                    )
                } else {
                    KeyboardInjection.injectKeyGlobal(
                        code: code,
                        command: command,
                        shift: shift,
                        control: control,
                        option: option
                    )
                }
                // Cmd/Ctrl+C·X 후 원격 클립보드 → 브라우저 (자동 가져오기 ON일 때만)
                let isCopyShortcut =
                    (command || control)
                    && !shift && !option
                    && (code == "KeyC" || code == "KeyX")
                if isCopyShortcut, peer.wantsClipAutoPull() {
                    let before = RemoteClipboard.changeCount()
                    let peerRef = peer
                    DispatchQueue.global(qos: .userInitiated).async {
                        let text = RemoteClipboard.readStringAfterChange(from: before, timeoutMs: 900) ?? ""
                        guard peerRef.wantsClipAutoPull() else { return }
                        if let message = JSONMessage.encode([
                            "type": "clipboard",
                            "value": text,
                            "empty": text.isEmpty,
                            "force": false,
                        ]) {
                            peerRef.sendText(message)
                        }
                    }
                }
            }

        case "clipAuto":
            if let on = json["value"] as? Bool {
                peer.setClipAutoPull(on)
            } else if let n = json["value"] as? NSNumber {
                peer.setClipAutoPull(n.boolValue)
            }

        /// 수동: 현재 원격 클립보드만 읽어 브라우저로 전송 (Cmd+C 재실행 없음)
        case "clipboardGet":
            let peerRef = peer
            DispatchQueue.global(qos: .userInitiated).async {
                let text = RemoteClipboard.readString() ?? ""
                if let message = JSONMessage.encode([
                    "type": "clipboard",
                    "value": text,
                    "empty": text.isEmpty,
                    "force": true,
                ]) {
                    peerRef.sendText(message)
                }
            }

        case "quality":
            if let quality = jsonDouble(json, "value") {
                // JPEG only (PNG is lossless — quality ignored).
                capture.jpegQuality = min(1.0, max(0.2, quality))
            }

        case "format":
            // "jpeg" | "png" | "h264"
            if let raw = json["value"] as? String {
                switch raw.lowercased() {
                case "png":
                    capture.imageFormat = .png
                    print("capture format: PNG")
                case "h264", "avc", "video":
                    capture.imageFormat = .h264
                    capture.targetFPS = max(capture.targetFPS, 30)
                    capture.scheduleRestart()
                    print("capture format: H.264")
                default:
                    capture.imageFormat = .jpeg
                    print("capture format: JPEG")
                }
            }

        case "preset":
            // fast | balanced | broadcast (H.264)
            if let raw = json["value"] as? String {
                capture.applyPreset(raw)
            }

        case "keyframe":
            if let id = jsonInt(json, "id") {
                capture.requestKeyframe(windowID: Self.routeID(from: id))
            }

        /// Client playout stats → adaptive bitrate (stabilizes web streaming).
        /// `{type:"stats", fps:24, queue:1, drops:3, pressure:0..3}`
        case "stats":
            let pressure: Int
            if let p = jsonInt(json, "pressure") {
                pressure = p
            } else {
                // Derive from fps/queue/drops if client only sends raw counters.
                let fps = jsonDouble(json, "fps") ?? 30
                let queue = jsonInt(json, "queue") ?? 0
                let drops = jsonInt(json, "drops") ?? 0
                if queue >= 3 || drops > 10 || fps < 12 { pressure = 3 }
                else if queue >= 2 || drops > 4 || fps < 18 { pressure = 2 }
                else if queue >= 1 || fps < 24 { pressure = 1 }
                else { pressure = 0 }
            }
            // Also factor outbound socket pressure for this peer.
            let sock = peer.outboundPressure()
            let combined = min(3, pressure + (sock >= 3 ? 1 : 0))
            capture.applyNetworkPressure(combined)

        case "fps":
            if let fps = jsonInt(json, "value") {
                capture.targetFPS = fps
                capture.scheduleRestart()
            }

        case "apps":
            sendApps(to: peer)

        case "launch":
            if let path = json["path"] as? String {
                let newInstance = (json["newInstance"] as? Bool)
                    ?? (json["newInstance"] as? NSNumber)?.boolValue
                    ?? false
                launchApp(at: path, newInstance: newInstance)
            }

        /// Close one window (not the whole app). Terminal multi-window safe.
        case "close":
            if let id = jsonInt(json, "id") {
                let route = Self.routeID(from: id)
                guard !CaptureManager.isDisplayRoute(route) else { return }
                let pid = jsonInt(json, "pid").map { pid_t($0) }
                let title = json["title"] as? String
                closeWindow(windowID: route, pid: pid, title: title, peer: peer)
            }

        /// Force-quit entire process (all windows of that pid).
        case "quit":
            if let pid = jsonInt(json, "pid") {
                quitApp(pid: pid_t(pid))
            }

        case "refresh":
            onWebSocketOpen(peer)

        default:
            break
        }
    }

    /// Exclusive input seat. On busy, notify the peer (rate-limited).
    @discardableResult
    private func claimInput(_ peer: Peer, kind: InputArbitration.Kind) -> Bool {
        let id = ObjectIdentifier(peer)
        let label = peer.clientIP()
        switch InputArbitration.acquire(id, kind: kind, label: label) {
        case .allowed:
            return true
        case .busy(let who):
            notifyInputBusy(peer, who: who)
            return false
        }
    }

    private func notifyInputBusy(_ peer: Peer, who: String) {
        let id = ObjectIdentifier(peer)
        let now = CFAbsoluteTimeGetCurrent()
        if let last = lastBusyNotify[id], now - last < 1.0 { return }
        lastBusyNotify[id] = now
        let msg = "다른 곳에서 입력 중 (\(who)) — 잠시 후 다시 시도"
        if let encoded = JSONMessage.encode(["type": "inputBusy", "message": msg, "who": who]) {
            peer.sendText(encoded)
        }
    }

    /// Resolve SCWindow for this peer's selection (from active capture sessions).
    private func peerTargetWindow(_ peer: Peer) -> SCWindow? {
        guard let id = peer.currentViewingWindowID() else { return nil }
        let route = Self.routeID(from: id)
        guard !CaptureManager.isDisplayRoute(route) else { return nil }
        return capture.window(for: route)
    }

    /// Full-display / lock-screen target for this peer, if selected.
    private func peerTargetDisplayID(_ peer: Peer) -> CGDirectDisplayID? {
        guard let id = peer.currentViewingWindowID() else { return nil }
        return CaptureManager.displayID(fromRoute: Self.routeID(from: id))
    }

    /// JSON Int → CGWindowID (supports display routes above Int32.max).
    private static func routeID(from id: Int) -> CGWindowID {
        CGWindowID(UInt32(truncatingIfNeeded: id))
    }

    private func sendApps(to peer: Peer) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let message = AppsCatalog.jsonMessage() {
                peer.sendText(message)
            }
        }
    }

    private func launchApp(at path: String, newInstance: Bool = false) {
        // newInstance flag means "new window" (same process), not a second app instance.
        AppLauncher.open(path: path, newWindow: newInstance)
    }

    /// Close a single CGWindow via Accessibility (or Cmd+W). Does not terminate the app.
    private func closeWindow(
        windowID: CGWindowID,
        pid: pid_t?,
        title: String?,
        peer: Peer
    ) {
        Task {
            let windows = await CaptureManager.listWindows()
            guard let scWindow = windows.first(where: { $0.windowID == windowID }) else {
                print("close denied: window \(windowID) not in list")
                return
            }
            let resolvedPID = scWindow.owningApplication?.processID ?? pid ?? 0
            guard resolvedPID > 0 else {
                print("close denied: no pid for window \(windowID)")
                return
            }
            // Only allow closing windows that appear in the shareable list (same gate as quit).
            let ok = WindowClose.close(
                pid: resolvedPID,
                windowID: windowID,
                title: title ?? scWindow.title
            )
            if ok {
                // Drop capture for this window; other windows of same app keep streaming.
                capture.stopStreaming(windowID: windowID)
                if peer.currentViewingWindowID().map({ Self.routeID(from: $0) }) == windowID {
                    peer.setViewing(windowId: nil, app: "", title: "")
                }
                print("closed window \(windowID) pid \(resolvedPID)")
            } else {
                print("close failed: window \(windowID)")
            }
        }
    }

    private func quitApp(pid: pid_t) {
        Task {
            let windows = await CaptureManager.listWindows()
            let allowed = windows.contains { $0.owningApplication?.processID == pid }
            guard allowed else {
                print("quit denied: pid \(pid) not in window list")
                return
            }
            await MainActor.run {
                _ = NSRunningApplication(processIdentifier: pid)?.terminate()
            }
        }
    }

    private func jsonDouble(_ json: [String: Any], _ key: String) -> Double? {
        if let d = json[key] as? Double { return d }
        if let n = json[key] as? NSNumber { return n.doubleValue }
        if let i = json[key] as? Int { return Double(i) }
        return nil
    }

    private func jsonInt(_ json: [String: Any], _ key: String) -> Int? {
        if let i = json[key] as? Int { return i }
        if let n = json[key] as? NSNumber { return n.intValue }
        if let d = json[key] as? Double { return Int(d) }
        return nil
    }
}
