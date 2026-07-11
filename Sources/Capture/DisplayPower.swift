import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// Display wake / no-sleep for remote sessions.
///
/// Policy (user preference):
/// - Server idle → monitor may sleep normally (no always-on).
/// - Authenticated web client connects → wake once (IOPM + optional cursor nudge).
/// - While ≥1 remote client session is active → keep panel from sleeping.
/// - Last client leaves → release; monitor can sleep again.
enum DisplayPower {
    private static let lock = NSLock()
    private static var noSleepID: IOPMAssertionID = 0
    private static var userActivityID: IOPMAssertionID = 0
    private static var holdCount = 0
    private static var lastJiggleAt: CFAbsoluteTime = 0

    /// Begin a remote session (authenticated client). Wakes display + holds no-sleep.
    /// Pair with `release()` when that session ends.
    static func retain(reason: String = "WebDock remote session") {
        lock.lock()
        defer { lock.unlock() }
        holdCount += 1
        if holdCount == 1 {
            createNoSleep(reason: reason)
            print("display: session retain (clients active)")
        }
        // Always try to wake when a session starts / joins.
        wakeNowUnlocked(jiggle: true, forceJiggle: holdCount == 1)
    }

    static func release() {
        lock.lock()
        defer { lock.unlock() }
        holdCount = max(0, holdCount - 1)
        if holdCount == 0 {
            clearNoSleep()
            print("display: session release (no clients — sleep allowed)")
        }
    }

    /// Soft wake (IOPM only, no cursor). Safe if needed mid-session.
    static func wakeNow() {
        lock.lock()
        defer { lock.unlock() }
        wakeNowUnlocked(jiggle: false, forceJiggle: false)
    }

    /// Strong wake for display capture / lock screen (cursor nudge at most ~15s).
    static func wakeHard() {
        lock.lock()
        defer { lock.unlock() }
        wakeNowUnlocked(jiggle: true, forceJiggle: false)
    }

    /// One-shot wake for a successful token login (HTTP) before WebSocket.
    /// Does not retain no-sleep (WS open will retain).
    static func wakeOnAuthenticatedAccess() {
        lock.lock()
        defer { lock.unlock() }
        // No active session → monitor may be off → force cursor nudge once.
        // Already in a session → soft path (avoid jiggle on every page reload).
        let mayBeAsleep = holdCount == 0
        wakeNowUnlocked(jiggle: true, forceJiggle: mayBeAsleep)
    }

    // MARK: - Private

    private static func createNoSleep(reason: String) {
        guard noSleepID == 0 else { return }
        var id: IOPMAssertionID = 0
        let kr = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        if kr == kIOReturnSuccess {
            noSleepID = id
            print("display: NoDisplaySleep assertion on")
        } else {
            let kr2 = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &id
            )
            if kr2 == kIOReturnSuccess {
                noSleepID = id
                print("display: PreventUserIdleDisplaySleep assertion on")
            } else {
                print("display: assertion failed \(kr)/\(kr2)")
            }
        }
    }

    private static func clearNoSleep() {
        if noSleepID != 0 {
            IOPMAssertionRelease(noSleepID)
            noSleepID = 0
            print("display: sleep assertion released")
        }
        if userActivityID != 0 {
            IOPMAssertionRelease(userActivityID)
            userActivityID = 0
        }
    }

    private static func wakeNowUnlocked(jiggle: Bool, forceJiggle: Bool) {
        var activity: IOPMAssertionID = 0
        let kr = IOPMAssertionDeclareUserActivity(
            "WebDock wake display" as CFString,
            kIOPMUserActiveLocal,
            &activity
        )
        if kr == kIOReturnSuccess {
            if userActivityID != 0 {
                IOPMAssertionRelease(userActivityID)
            }
            userActivityID = activity
        }

        guard jiggle else { return }
        let now = CFAbsoluteTimeGetCurrent()
        // forceJiggle: first client / token login — always nudge (monitor off).
        // otherwise: cooldown so capture retries don't spam cursor.
        if !forceJiggle, now - lastJiggleAt < 15 {
            return
        }
        lastJiggleAt = now
        jiggleCursor()
    }

    /// Small cursor move — wakes some panels / clamshell when IOPM alone is not enough.
    private static func jiggleCursor() {
        let loc = CGEvent(source: nil)?.location ?? .zero
        if let move = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: CGPoint(x: loc.x + 1, y: loc.y),
            mouseButton: .left
        ) {
            move.post(tap: .cghidEventTap)
        }
        if let back = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: loc,
            mouseButton: .left
        ) {
            back.post(tap: .cghidEventTap)
        }
    }
}
