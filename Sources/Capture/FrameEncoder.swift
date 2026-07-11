import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import CoreImage

enum CaptureImageFormat: String, Sendable {
    case jpeg
    case png
    /// Hardware H.264 (broadcast). Not still-image encoded via FrameEncoder.
    case h264
}

enum FrameEncoder {
    /// Encode frame as JPEG (lossy, `quality` 0…1) or PNG (lossless; quality ignored).
    static func encode(
        _ image: CIImage,
        format: CaptureImageFormat,
        quality: CGFloat,
        context: CIContext
    ) -> Data? {
        switch format {
        case .jpeg:
            return encodeJPEG(image, quality: quality, context: context)
        case .png:
            return encodePNG(image, context: context)
        case .h264:
            return nil // handled by H264Encoder
        }
    }

    // MARK: - JPEG

    private static func encodeJPEG(_ image: CIImage, quality: CGFloat, context: CIContext) -> Data? {
        let q = min(1, max(0, quality))
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let data = context.jpegRepresentation(
            of: image,
            colorSpace: space,
            options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: q]
           ) {
            return data
        }
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return encodeCG(cg, type: .jpeg, quality: q)
    }

    // MARK: - PNG

    private static func encodePNG(_ image: CIImage, context: CIContext) -> Data? {
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let data = context.pngRepresentation(of: image, format: .RGBA8, colorSpace: space) {
            return data
        }
        guard let cg = context.createCGImage(image, from: image.extent) else { return nil }
        return encodeCG(cg, type: .png, quality: 1)
    }

    private static func encodeCG(_ image: CGImage, type: UTType, quality: CGFloat) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out,
            type.identifier as CFString,
            1,
            nil
        ) else { return nil }

        var props: [CFString: Any] = [:]
        if type == .jpeg {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
