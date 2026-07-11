import AppKit
import Foundation
import ScreenCaptureKit
import CoreImage
import CoreMedia
import CoreVideo
import CoreGraphics
import QuartzCore

/// Multi-target capture: one SCStream per window **or** display route ID.
/// Frames are delivered as `(routeID, jpegData)` so the server can fan out per client.
///
/// Display routes use reserved IDs (`0xE0000000 | displayID`) so the lock screen /
/// full desktop can be shared when individual windows are unavailable.
final class CaptureManager: NSObject, SCStreamOutput, SCStreamDelegate {
    /// High bit pattern reserved for display (not real CGWindowIDs).
    static let displayRouteMask: CGWindowID = 0xE000_0000

    private let stateLock = NSLock()
    private let lifecycleQueue = DispatchQueue(label: "webdock.capture.lifecycle")

    private let ciContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .highQualityDownsample: true,
        .cacheIntermediates: false,
    ])
    private var _jpegQuality: Double = 0.92
    private var _format: CaptureImageFormat = .jpeg
    /// Target capture FPS (SCStream minimumFrameInterval).
    private var _targetFPS: Int = 30
    /// Max encoded edge length (long side) before downscale.
    private var _maxEdge: Int = 4096
    /// PNG is heavy — drop every other frame unless broadcast profile.
    private var _pngHalfRate = true
    private var _pngDropToggle = false
    /// Pixel density for SCStream output. `0` = auto (screen backingScaleFactor, usually 2 on Retina).
    /// 1 = point size (softer, less bandwidth). 2–3 = sharper.
    private var _scale = 0
    private var _presetName = "balanced"

    /// routeID → active session (window or display)
    private var sessions: [CGWindowID: Session] = [:]
    /// SCStream identity → routeID
    private var streamKeys: [ObjectIdentifier: CGWindowID] = [:]
    private var restartWorks: [CGWindowID: DispatchWorkItem] = [:]
    private var startGenerations: [CGWindowID: UInt64] = [:]
    /// Per-route H.264 encoders (broadcast mode).
    private var h264Encoders: [CGWindowID: H264Encoder] = [:]
    /// Last encoded pixel size per route (for encoder recreate).
    private var lastEncodeSize: [CGWindowID: (Int, Int)] = [:]
    /// In-flight H.264 encodes per route (allow 2 for smoother cadence).
    private var h264EncodeInFlight: [CGWindowID: Int] = [:]
    private let h264MaxInFlight = 2
    /// Adaptive bitrate target shared by all H.264 routes.
    private var _h264Bitrate = 4_000_000
    private var _adaptLevel = 0 // 0=full … 3=most reduced

    private enum Target {
        case window(SCWindow)
        case display(SCDisplay)
    }

    private struct Session {
        let stream: SCStream
        let target: Target
        let width: Int
        let height: Int
    }

    var jpegQuality: Double {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _jpegQuality }
        set { stateLock.lock(); _jpegQuality = newValue; stateLock.unlock() }
    }

    /// `.jpeg` (default, quality slider applies) or `.png` (lossless, larger).
    var imageFormat: CaptureImageFormat {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _format }
        set { stateLock.lock(); _format = newValue; stateLock.unlock() }
    }

    var targetFPS: Int {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _targetFPS }
        set {
            stateLock.lock()
            _targetFPS = max(10, min(60, newValue))
            stateLock.unlock()
        }
    }

    var presetName: String {
        stateLock.lock(); defer { stateLock.unlock() }
        return _presetName
    }

    var scale: Int {
        get { stateLock.lock(); defer { stateLock.unlock() }; return _scale }
        set { stateLock.lock(); _scale = max(0, min(3, newValue)); stateLock.unlock() }
    }

    /// fast | balanced | broadcast — restarts streams so FPS / max resolution apply.
    func applyPreset(_ name: String) {
        stateLock.lock()
        switch name.lowercased() {
        case "fast", "low":
            _presetName = "fast"
            _format = .jpeg
            _jpegQuality = 0.62
            _targetFPS = 20
            _maxEdge = 2560
            _pngHalfRate = true
        case "broadcast", "high", "live", "h264":
            // H.264: prioritize smooth low-latency over raw resolution.
            // 60fps@Retina floods encoder/WS/decoder → stutter. 30fps @ ≤1600px is stable on LAN.
            _presetName = "broadcast"
            _format = .h264
            _jpegQuality = 1.0
            _targetFPS = 30
            _maxEdge = 1600
            _pngHalfRate = false
            _scale = 1 // points, not Retina 2× (¼ the pixels)
        default:
            _presetName = "balanced"
            _format = .jpeg
            _jpegQuality = 0.92
            _targetFPS = 30
            _maxEdge = 4096
            _pngHalfRate = true
        }
        stateLock.unlock()
        print("capture preset: \(presetName) format=\(imageFormat.rawValue) fps=\(targetFPS) maxEdge=\(_maxEdge)")
        scheduleRestart()
    }

    /// Ask encoders to emit a keyframe (e.g. when a browser selects a window).
    func requestKeyframe(windowID: CGWindowID) {
        stateLock.lock()
        let enc = h264Encoders[windowID]
        stateLock.unlock()
        enc?.forceKeyFrame()
    }

    /// Client/network feedback: 0=comfortable … 3=heavy. Adjusts H.264 bitrate live.
    func applyNetworkPressure(_ level: Int) {
        let clamped = max(0, min(3, level))
        stateLock.lock()
        guard _format == .h264 else {
            stateLock.unlock()
            return
        }
        if clamped == _adaptLevel {
            stateLock.unlock()
            return
        }
        _adaptLevel = clamped
        let br: Int
        switch clamped {
        case 0: br = 4_500_000
        case 1: br = 2_800_000
        case 2: br = 1_600_000
        default: br = 900_000
        }
        _h264Bitrate = br
        let encoders = Array(h264Encoders.values)
        stateLock.unlock()
        for e in encoders { e.updateBitrate(br) }
        print("capture adaptive: pressure=\(clamped) bitrate=\(br / 1000)kbps")
    }

    /// Effective capture scale: auto uses max Retina factor across screens (typically 2).
    private func resolvedScale() -> Int {
        stateLock.lock()
        let configured = _scale
        stateLock.unlock()
        if configured >= 1 { return min(3, configured) }
        let factor = NSScreen.screens.map(\.backingScaleFactor).max()
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0
        return max(1, min(3, Int(factor.rounded(.toNearestOrAwayFromZero))))
    }

    /// Still image frame (JPEG/PNG raw bytes) for a route.
    var onFrame: ((CGWindowID, Data) -> Void)?
    /// H.264 config (avcC) when encoder starts or SPS/PPS change.
    var onH264Config: ((CGWindowID, Data, String, Int, Int) -> Void)?
    /// H.264 sample: route, AVCC payload, keyframe, pts µs.
    var onH264Sample: ((CGWindowID, Data, Bool, Int64) -> Void)?
    /// Legacy alias.
    var onJPEG: ((CGWindowID, Data) -> Void)? {
        get { onFrame }
        set { onFrame = newValue }
    }

    /// First window session (legacy IME fallback). Display-only sessions ignored.
    var selectedWindow: SCWindow? {
        stateLock.lock(); defer { stateLock.unlock() }
        for session in sessions.values {
            if case .window(let w) = session.target { return w }
        }
        return nil
    }

    func window(for id: CGWindowID) -> SCWindow? {
        stateLock.lock(); defer { stateLock.unlock() }
        guard let session = sessions[id], case .window(let w) = session.target else { return nil }
        return w
    }

    /// Whether this route is a full-display (lock-screen capable) stream.
    static func isDisplayRoute(_ id: CGWindowID) -> Bool {
        (id & 0xF000_0000) == displayRouteMask
    }

    static func routeID(forDisplayID displayID: CGDirectDisplayID) -> CGWindowID {
        displayRouteMask | (CGWindowID(displayID) & 0x0FFF_FFFF)
    }

    static func displayID(fromRoute id: CGWindowID) -> CGDirectDisplayID? {
        guard isDisplayRoute(id) else { return nil }
        return CGDirectDisplayID(id & 0x0FFF_FFFF)
    }

    // MARK: - Catalog

    private static let systemAppBlocklist: Set<String> = [
        "Dock", "Window Server", "WindowServer", "Wallpaper", "WallpaperAgent",
        "Control Center", "Notification Center", "Spotlight", "WindowManager",
        "Menubar", "Screenshot", "coreautha", "universalaccessd",
    ]

    static func listWindows() async -> [SCWindow] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        ) else { return [] }

        let myPID = ProcessInfo.processInfo.processIdentifier
        return content.windows
            .filter { window in
                let name = window.owningApplication?.applicationName ?? ""
                return !name.isEmpty
                    && window.frame.width > 40
                    && window.frame.height > 40
                    && window.windowLayer == 0
                    && !systemAppBlocklist.contains(name)
                    && window.owningApplication?.processID != myPID
            }
            .sorted { a, b in
                let an = a.owningApplication?.applicationName ?? ""
                let bn = b.owningApplication?.applicationName ?? ""
                return an == bn ? (a.title ?? "") < (b.title ?? "") : an < bn
            }
    }

    /// List displays. Pass `wake: true` only when starting capture / client already connected —
    /// not on the idle window-list poll (that would keep the panel awake forever).
    static func listDisplays(wake: Bool = false) async -> [SCDisplay] {
        if wake {
            DisplayPower.wakeNow()
        }
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                if wake { DisplayPower.wakeNow() }
            }
            guard let content = try? await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            ) else { continue }
            if content.displays.isEmpty { continue }
            let mainID = CGMainDisplayID()
            return content.displays.sorted { a, b in
                if a.displayID == mainID { return true }
                if b.displayID == mainID { return false }
                return a.displayID < b.displayID
            }
        }
        return []
    }

    // MARK: - Public lifecycle

    /// Ensure a stream is running for this route (window or display).
    func ensureStreaming(windowID: CGWindowID) {
        lifecycleQueue.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let already = self.sessions[windowID] != nil
            let gen = (self.startGenerations[windowID] ?? 0) &+ 1
            self.startGenerations[windowID] = gen
            self.stateLock.unlock()
            if already { return }
            Task { await self.startSession(routeID: windowID, generation: gen) }
        }
    }

    func stopStreaming(windowID: CGWindowID) {
        lifecycleQueue.async { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            self.startGenerations[windowID] = (self.startGenerations[windowID] ?? 0) &+ 1
            let session = self.sessions.removeValue(forKey: windowID)
            if let session {
                self.streamKeys.removeValue(forKey: ObjectIdentifier(session.stream))
            }
            let enc = self.h264Encoders.removeValue(forKey: windowID)
            self.lastEncodeSize.removeValue(forKey: windowID)
            self.h264EncodeInFlight.removeValue(forKey: windowID)
            self.stateLock.unlock()
            enc?.invalidate()
            if let session {
                Task { try? await session.stream.stopCapture() }
                print("capture: stopped route \(windowID)")
            }
        }
    }

    func scheduleRestart(windowID: CGWindowID) {
        lifecycleQueue.async { [weak self] in
            guard let self else { return }
            self.restartWorks[windowID]?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.stopStreaming(windowID: windowID)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.ensureStreaming(windowID: windowID)
                }
            }
            self.restartWorks[windowID] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }
    }

    func requestStart(windowID: CGWindowID) {
        ensureStreaming(windowID: windowID)
    }

    func scheduleRestart() {
        stateLock.lock()
        let ids = Array(sessions.keys)
        stateLock.unlock()
        for id in ids { scheduleRestart(windowID: id) }
    }

    func stop() async {
        let all: [SCStream] = await withCheckedContinuation { cont in
            lifecycleQueue.async {
                self.stateLock.lock()
                let streams = self.sessions.values.map(\.stream)
                let encoders = Array(self.h264Encoders.values)
                self.sessions.removeAll()
                self.streamKeys.removeAll()
                self.h264Encoders.removeAll()
                self.lastEncodeSize.removeAll()
                self.h264EncodeInFlight.removeAll()
                self.stateLock.unlock()
                for e in encoders { e.invalidate() }
                cont.resume(returning: streams)
            }
        }
        for s in all { try? await s.stopCapture() }
    }

    // MARK: - Start one session

    private func startSession(routeID: CGWindowID, generation: UInt64) async {
        if Self.isDisplayRoute(routeID) {
            await startDisplaySession(routeID: routeID, generation: generation)
        } else {
            await startWindowSession(windowID: routeID, generation: generation)
        }
    }

    private func startWindowSession(windowID: CGWindowID, generation: UInt64) async {
        guard let window = await Self.listWindows().first(where: { $0.windowID == windowID }) else {
            print("capture: window \(windowID) not found")
            return
        }
        guard isCurrent(windowID, generation) else { return }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        // SCWindow.frame is in points — multiply by Retina scale for sharp pixels.
        let px = resolvedScale()
        let config = makeConfig(
            width: max(2, Int(window.frame.width.rounded(.up)) * px),
            height: max(2, Int(window.frame.height.rounded(.up)) * px)
        )
        await installStream(
            routeID: windowID,
            generation: generation,
            filter: filter,
            config: config,
            target: .window(window),
            label: window.owningApplication?.applicationName ?? "?",
            width: config.width,
            height: config.height
        )
    }

    private func startDisplaySession(routeID: CGWindowID, generation: UInt64) async {
        guard let displayID = Self.displayID(fromRoute: routeID) else {
            print("capture: bad display route \(routeID)")
            return
        }
        // Must be awake before ScreenCaptureKit can bind a display stream.
        DisplayPower.wakeHard()
        try? await Task.sleep(nanoseconds: 250_000_000)

        let listed = await Self.listDisplays(wake: true)
        let display = listed.first(where: { $0.displayID == displayID }) ?? listed.first
        guard let display else {
            print("capture: display \(displayID) not found (screen may still be off)")
            return
        }
        guard isCurrent(routeID, generation) else { return }

        // Full display — includes lock screen chrome when the session is locked.
        let filter = SCContentFilter(display: display, excludingWindows: [])
        // SCDisplay size is points; scale up for Retina output pixels.
        let px = resolvedScale()
        let w = max(2, Int(CGFloat(display.width).rounded(.up)) * px)
        let h = max(2, Int(CGFloat(display.height).rounded(.up)) * px)
        let config = makeConfig(width: w, height: h)
        await installStream(
            routeID: routeID,
            generation: generation,
            filter: filter,
            config: config,
            target: .display(display),
            label: "display \(displayID)",
            width: config.width,
            height: config.height
        )
    }

    private func makeConfig(width: Int, height: Int) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        stateLock.lock()
        let maxEdge = _maxEdge
        let fps = _targetFPS
        stateLock.unlock()

        var w = width
        var h = height
        if w > maxEdge || h > maxEdge {
            let s = min(Double(maxEdge) / Double(w), Double(maxEdge) / Double(h))
            w = max(2, Int((Double(w) * s).rounded()))
            h = max(2, Int((Double(h) * s).rounded()))
        }
        config.width = w
        config.height = h
        // Higher FPS = smoother “broadcast” feel (encode must keep up).
        let timescale = Int32(max(10, min(60, fps)))
        config.minimumFrameInterval = CMTime(value: 1, timescale: timescale)
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = fps >= 50 ? 5 : 3
        config.showsCursor = true
        if #available(macOS 14.0, *) {
            config.capturesAudio = false
        }
        print("capture: config \(w)×\(h) scale=\(resolvedScale()) fps=\(fps) maxEdge=\(maxEdge)")
        return config
    }

    private func installStream(
        routeID: CGWindowID,
        generation: UInt64,
        filter: SCContentFilter,
        config: SCStreamConfiguration,
        target: Target,
        label: String,
        width: Int,
        height: Int
    ) async {
        do {
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "webdock.capture.\(routeID)")
            )
            try await stream.startCapture()
            guard isCurrent(routeID, generation) else {
                try? await stream.stopCapture()
                return
            }
            lifecycleQueue.async {
                self.stateLock.lock()
                if let old = self.sessions[routeID] {
                    self.streamKeys.removeValue(forKey: ObjectIdentifier(old.stream))
                    Task { try? await old.stream.stopCapture() }
                }
                let oldEnc = self.h264Encoders.removeValue(forKey: routeID)
                self.sessions[routeID] = Session(
                    stream: stream,
                    target: target,
                    width: width,
                    height: height
                )
                self.streamKeys[ObjectIdentifier(stream)] = routeID
                self.lastEncodeSize[routeID] = (width, height)
                let useH264 = self._format == .h264
                let fps = self._targetFPS
                let maxEdge = self._maxEdge
                self.stateLock.unlock()
                oldEnc?.invalidate()

                if useH264 {
                    let enc = self.makeH264Encoder(routeID: routeID, width: width, height: height, fps: fps, maxEdge: maxEdge)
                    self.stateLock.lock()
                    self.h264Encoders[routeID] = enc
                    self.stateLock.unlock()
                    enc.forceKeyFrame()
                }
                print("capture: streaming \(label) route=\(routeID) \(width)×\(height) h264=\(useH264)")
            }
        } catch {
            print("capture start error \(routeID): \(error)")
        }
    }

    private func makeH264Encoder(
        routeID: CGWindowID,
        width: Int,
        height: Int,
        fps: Int,
        maxEdge: Int
    ) -> H264Encoder {
        var w = width
        var h = height
        if w > maxEdge || h > maxEdge {
            let s = min(Double(maxEdge) / Double(w), Double(maxEdge) / Double(h))
            w = max(2, Int((Double(w) * s).rounded()) & ~1)
            h = max(2, Int((Double(h) * s).rounded()) & ~1)
        }
        w &= ~1
        h &= ~1
        stateLock.lock()
        let br = _h264Bitrate
        stateLock.unlock()
        let enc = H264Encoder()
        enc.onConfig = { [weak self] avcC, codec, cw, ch in
            self?.onH264Config?(routeID, avcC, codec, cw, ch)
        }
        enc.onSample = { [weak self] data, key, us in
            self?.onH264Sample?(routeID, data, key, us)
        }
        enc.onEncodeFinished = { [weak self] in
            guard let self else { return }
            self.stateLock.lock()
            let n = (self.h264EncodeInFlight[routeID] ?? 1) - 1
            self.h264EncodeInFlight[routeID] = max(0, n)
            self.stateLock.unlock()
        }
        enc.ensure(width: w, height: h, fps: fps, bitrate: br)
        return enc
    }

    private func isCurrent(_ routeID: CGWindowID, _ generation: UInt64) -> Bool {
        lifecycleQueue.sync { startGenerations[routeID] == generation }
    }

    // MARK: - SCStreamOutput

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }

        stateLock.lock()
        let routeID = streamKeys[ObjectIdentifier(stream)]
        let quality = _jpegQuality
        let format = _format
        let pngHalf = _pngHalfRate
        let enc = routeID.flatMap { h264Encoders[$0] }
        let fps = _targetFPS
        if format == .png && pngHalf {
            _pngDropToggle.toggle()
            if _pngDropToggle {
                stateLock.unlock()
                return
            }
        }
        stateLock.unlock()
        guard let routeID else { return }

        // H.264 path: allow a few in-flight encodes; drop only when saturated.
        if format == .h264 {
            guard let enc else { return }
            stateLock.lock()
            let inflight = h264EncodeInFlight[routeID] ?? 0
            if inflight >= h264MaxInFlight {
                stateLock.unlock()
                return
            }
            h264EncodeInFlight[routeID] = inflight + 1
            stateLock.unlock()
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let t = pts.isValid
                ? pts
                : CMTime(value: CMTimeValue(CACurrentMediaTime() * 1_000_000), timescale: 1_000_000)
            if !enc.encode(pixelBuffer: pixelBuffer, presentationTime: t) {
                stateLock.lock()
                let n = (h264EncodeInFlight[routeID] ?? 1) - 1
                h264EncodeInFlight[routeID] = max(0, n)
                stateLock.unlock()
            }
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        if let data = FrameEncoder.encode(
            ciImage,
            format: format,
            quality: CGFloat(quality),
            context: ciContext
        ) {
            onFrame?(routeID, data)
        }
        _ = fps
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("capture stopped: \(error)")
        stateLock.lock()
        if let rid = streamKeys.removeValue(forKey: ObjectIdentifier(stream)) {
            sessions.removeValue(forKey: rid)
        }
        stateLock.unlock()
    }
}
