import Foundation

/// Exclusive multi-browser input on a single macOS GUI session.
///
/// While peer A is actively injecting (mouse/keys), peer B is **rejected**
/// (not delayed). When A is idle past a short grace period, anyone may take over.
enum InputArbitration {
    private static let lock = NSLock()
    private static var owner: ObjectIdentifier?
    private static var ownerLabel: String = ""
    private static var ownerUntil: CFAbsoluteTime = 0

    /// How long after the last event the owner keeps the seat (seconds).
    private static let idleGrace: CFAbsoluteTime = 0.85
    /// While holding mouse button / scrolling, keep seat a bit longer.
    private static let activeGrace: CFAbsoluteTime = 2.0

    enum Kind: String {
        case down, move, up, scroll, key, text
    }

    enum Decision: Sendable {
        case allowed
        /// Another peer is mid-input; `label` is best-effort (IP / "다른 클라이언트").
        case busy(label: String)
    }

    /// Try to use input. Owner renews on each allowed event; others are busy until idle.
    static func acquire(_ peer: ObjectIdentifier, kind: Kind, label: String) -> Decision {
        lock.lock()
        defer { lock.unlock() }

        let now = CFAbsoluteTimeGetCurrent()
        if owner != nil, now > ownerUntil {
            owner = nil
            ownerLabel = ""
        }

        if let current = owner, current != peer {
            return .busy(label: ownerLabel.isEmpty ? "다른 클라이언트" : ownerLabel)
        }

        // Free, or we already own — take / renew.
        owner = peer
        if !label.isEmpty { ownerLabel = label }
        ownerUntil = now + grace(for: kind)
        return .allowed
    }

    static func release(_ peer: ObjectIdentifier) {
        lock.lock()
        defer { lock.unlock() }
        if owner == peer {
            owner = nil
            ownerLabel = ""
            ownerUntil = 0
        }
    }

    static func currentOwnerLabel() -> String? {
        lock.lock()
        defer { lock.unlock() }
        let now = CFAbsoluteTimeGetCurrent()
        guard owner != nil, now <= ownerUntil else { return nil }
        return ownerLabel.isEmpty ? "다른 클라이언트" : ownerLabel
    }

    private static func grace(for kind: Kind) -> CFAbsoluteTime {
        switch kind {
        case .down, .move, .scroll:
            return activeGrace
        case .up, .key, .text:
            return idleGrace
        }
    }
}
