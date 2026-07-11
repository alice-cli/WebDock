import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo
import CoreGraphics
import QuartzCore

/// Low-latency H.264 encoder (VideoToolbox) for broadcast-style streaming.
/// Output: AVCC length-prefixed access units + avcC config for WebCodecs.
final class H264Encoder {
    struct Config: Equatable {
        var width: Int
        var height: Int
        var fps: Int
        var bitrate: Int
    }

    private let lock = NSLock()
    private var session: VTCompressionSession?
    private var config: Config?
    private var frameIndex: Int64 = 0
    private var lastForceKey: CFAbsoluteTime = 0
    private var forceNextKey = false

    private(set) var avcC: Data?
    private(set) var codecString: String = "avc1.64001F"
    private(set) var codedWidth: Int = 0
    private(set) var codedHeight: Int = 0

    /// avcC box for WebCodecs `description`.
    var onConfig: ((Data, String, Int, Int) -> Void)?
    /// Encoded AU (AVCC), keyframe flag, PTS microseconds.
    var onSample: ((Data, Bool, Int64) -> Void)?
    /// Always invoked when an encode attempt finishes (success, drop, or error) — for backpressure.
    var onEncodeFinished: (() -> Void)?

    deinit { invalidate() }

    func invalidate() {
        lock.lock()
        let s = session
        session = nil
        config = nil
        avcC = nil
        frameIndex = 0
        forceNextKey = false
        lock.unlock()
        if let s {
            VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(s)
        }
    }

    func ensure(width: Int, height: Int, fps: Int, bitrate: Int) {
        let w = max(2, width & ~1)
        let h = max(2, height & ~1)
        let f = max(10, min(60, fps))
        let br = max(500_000, bitrate)
        let next = Config(width: w, height: h, fps: f, bitrate: br)

        lock.lock()
        let same = session != nil && config == next
        lock.unlock()
        if same { return }
        recreate(next)
    }

    func forceKeyFrame() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastForceKey > 0.25 else { return }
        lastForceKey = now
        lock.lock()
        forceNextKey = true
        lock.unlock()
    }

    /// Live bitrate tweak without recreating the session (adaptive streaming).
    func updateBitrate(_ bitrate: Int) {
        let br = max(400_000, min(12_000_000, bitrate))
        lock.lock()
        guard let session else {
            lock.unlock()
            return
        }
        if var cfg = config {
            cfg.bitrate = br
            config = cfg
        }
        lock.unlock()
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AverageBitRate,
            value: br as CFNumber
        )
        let bytesPerSecond = max(br / 8, 50_000)
        let limits: [CFNumber] = [bytesPerSecond as CFNumber, 1 as CFNumber]
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_DataRateLimits,
            value: limits as CFArray
        )
    }

    @discardableResult
    func encode(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) -> Bool {
        lock.lock()
        guard let session else {
            lock.unlock()
            return false
        }
        let force = forceNextKey
        forceNextKey = false
        lock.unlock()

        var flags = VTEncodeInfoFlags()
        var frameProps: CFDictionary?
        if force {
            frameProps = [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue!] as CFDictionary
        }

        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTime,
            duration: .invalid,
            frameProperties: frameProps,
            infoFlagsOut: &flags,
            outputHandler: { [weak self] status, infoFlags, sampleBuffer in
                defer { self?.onEncodeFinished?() }
                guard let self, status == noErr, let sampleBuffer else {
                    if status != noErr {
                        print("H264 output status: \(status)")
                    }
                    return
                }
                self.handleEncoded(sampleBuffer: sampleBuffer, infoFlags: infoFlags)
            }
        )
        if status != noErr {
            print("H264 encode error: \(status)")
            onEncodeFinished?()
            return false
        }
        return true
    }

    // MARK: - Session

    private func recreate(_ cfg: Config) {
        invalidate()

        var sessionOut: VTCompressionSession?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: cfg.width,
            kCVPixelBufferHeightKey as String: cfg.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]

        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(cfg.width),
            height: Int32(cfg.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: [
                kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true
            ] as CFDictionary,
            imageBufferAttributes: attrs as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &sessionOut
        )
        guard status == noErr, let sessionOut else {
            print("H264 session create failed: \(status)")
            return
        }

        VTSessionSetProperty(sessionOut, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(sessionOut, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        // Main is enough for desktop UI and encodes faster than High on some machines.
        VTSessionSetProperty(
            sessionOut,
            key: kVTCompressionPropertyKey_ProfileLevel,
            value: kVTProfileLevel_H264_Main_AutoLevel
        )
        VTSessionSetProperty(
            sessionOut,
            key: kVTCompressionPropertyKey_AverageBitRate,
            value: cfg.bitrate as CFNumber
        )
        VTSessionSetProperty(
            sessionOut,
            key: kVTCompressionPropertyKey_ExpectedFrameRate,
            value: cfg.fps as CFNumber
        )
        // Short GOP for lower latency after packet loss / new client.
        let gop = max(cfg.fps, min(cfg.fps * 2, 60))
        VTSessionSetProperty(
            sessionOut,
            key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: gop as CFNumber
        )
        VTSessionSetProperty(
            sessionOut,
            key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration,
            value: 1.0 as CFNumber
        )
        // Prefer speed over tiny quality gains (reduces stutter under load).
        VTSessionSetProperty(
            sessionOut,
            key: kVTCompressionPropertyKey_Quality,
            value: 0.55 as CFNumber
        )
        let bytesPerSecond = max(cfg.bitrate / 8, 80_000)
        let limits: [CFNumber] = [(bytesPerSecond) as CFNumber, 1 as CFNumber]
        VTSessionSetProperty(
            sessionOut,
            key: kVTCompressionPropertyKey_DataRateLimits,
            value: limits as CFArray
        )

        VTCompressionSessionPrepareToEncodeFrames(sessionOut)

        lock.lock()
        session = sessionOut
        config = cfg
        codedWidth = cfg.width
        codedHeight = cfg.height
        frameIndex = 0
        lock.unlock()

        print("H264 encoder \(cfg.width)×\(cfg.height) @\(cfg.fps)fps br=\(cfg.bitrate / 1000)kbps")
    }

    // MARK: - Output

    private func handleEncoded(sampleBuffer: CMSampleBuffer, infoFlags: VTEncodeInfoFlags) {
        if infoFlags.contains(.frameDropped) { return }
        let isKey = isKeyframe(sampleBuffer)

        if let format = CMSampleBufferGetFormatDescription(sampleBuffer) {
            maybeEmitConfig(from: format)
        }

        guard let data = copySampleData(sampleBuffer), !data.isEmpty else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let us: Int64
        if pts.isValid && pts.timescale != 0 {
            us = Int64((Double(pts.value) / Double(pts.timescale)) * 1_000_000.0)
        } else {
            us = Int64(CACurrentMediaTime() * 1_000_000.0)
        }
        onSample?(data, isKey, us)
    }

    private func isKeyframe(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard
            let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
            ) as? [[CFString: Any]],
            let first = attachments.first
        else { return true }
        if let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
            return !notSync
        }
        return true
    }

    private func maybeEmitConfig(from format: CMFormatDescription) {
        guard let box = Self.makeAvcC(from: format) else { return }
        let codec = Self.codecString(fromAvcC: box) ?? "avc1.64001F"
        lock.lock()
        let changed = avcC != box
        if changed {
            avcC = box
            codecString = codec
        }
        let w = codedWidth
        let h = codedHeight
        lock.unlock()
        if changed {
            onConfig?(box, codec, w, h)
        }
    }

    private func copySampleData(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        let len = CMBlockBufferGetDataLength(block)
        guard len > 0 else { return nil }
        var out = Data(count: len)
        let copyStatus = out.withUnsafeMutableBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: len, destination: base)
        }
        guard copyStatus == kCMBlockBufferNoErr else { return nil }
        return out
    }

    // MARK: - avcC

    static func makeAvcC(from format: CMFormatDescription) -> Data? {
        var spsPtr: UnsafePointer<UInt8>?
        var spsSize = 0
        var ppsPtr: UnsafePointer<UInt8>?
        var ppsSize = 0
        var nalSize: Int32 = 0

        var status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format,
            parameterSetIndex: 0,
            parameterSetPointerOut: &spsPtr,
            parameterSetSizeOut: &spsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: &nalSize
        )
        guard status == noErr, let spsPtr, spsSize >= 4 else { return nil }

        status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format,
            parameterSetIndex: 1,
            parameterSetPointerOut: &ppsPtr,
            parameterSetSizeOut: &ppsSize,
            parameterSetCountOut: nil,
            nalUnitHeaderLengthOut: nil
        )
        guard status == noErr, let ppsPtr, ppsSize > 0 else { return nil }

        var avcC = Data()
        avcC.append(1)
        avcC.append(spsPtr[1])
        avcC.append(spsPtr[2])
        avcC.append(spsPtr[3])
        avcC.append(0xFF)
        avcC.append(0xE1)
        avcC.append(UInt8((spsSize >> 8) & 0xFF))
        avcC.append(UInt8(spsSize & 0xFF))
        avcC.append(Data(bytes: spsPtr, count: spsSize))
        avcC.append(1)
        avcC.append(UInt8((ppsSize >> 8) & 0xFF))
        avcC.append(UInt8(ppsSize & 0xFF))
        avcC.append(Data(bytes: ppsPtr, count: ppsSize))
        return avcC
    }

    static func codecString(fromAvcC avcC: Data) -> String? {
        guard avcC.count >= 4 else { return nil }
        return String(format: "avc1.%02X%02X%02X", avcC[1], avcC[2], avcC[3])
    }
}
