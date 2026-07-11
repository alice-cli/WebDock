import CoreGraphics
import Foundation

/// Login session / lock-screen helpers.
enum SessionState {
    /// True when the GUI session shows the lock screen (user still logged in).
    static var isScreenLocked: Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return false
        }
        if let v = dict["CGSSessionScreenIsLocked"] as? Bool { return v }
        if let v = dict["CGSSessionScreenIsLocked"] as? Int { return v != 0 }
        if let v = dict["CGSSessionScreenIsLocked"] as? NSNumber { return v.boolValue }
        return false
    }
}
