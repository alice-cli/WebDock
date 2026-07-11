import CoreGraphics
import Foundation

/// Screen coordinates for full-display capture (lock screen / desktop).
enum DisplayGeometry {
    static func bounds(displayID: CGDirectDisplayID) -> CGRect {
        CGDisplayBounds(displayID)
    }

    /// Fractional (0…1) canvas coords → global point for CGEvent.
    /// Canvas origin is top-left of the captured frame.
    static func globalPoint(
        xFraction: Double,
        yFraction: Double,
        displayID: CGDirectDisplayID
    ) -> CGPoint {
        let frame = bounds(displayID: displayID)
        // Match the same mapping used for window capture (fractional into frame).
        return CGPoint(
            x: frame.origin.x + CGFloat(xFraction) * frame.width,
            y: frame.origin.y + CGFloat(yFraction) * frame.height
        )
    }
}
