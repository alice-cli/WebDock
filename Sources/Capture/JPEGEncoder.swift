import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import CoreImage

enum JPEGEncoder {
    /// Prefer CIContext JPEG path; fall back to ImageIO via CGImage.
    static func encode(_ image: CIImage, quality: CGFloat, context: CIContext) -> Data? {
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
        return encode(cg, quality: q)
    }

    static func encode(_ image: CGImage, quality: CGFloat) -> Data? {
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(
            dest,
            image,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        )
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
