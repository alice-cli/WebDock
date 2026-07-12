import AppKit
import CoreGraphics
import ScreenCaptureKit
import Foundation

enum MouseInjection {
    enum Phase: String {
        case down, move, up
    }

    private static let injectLock = NSLock()

    /// Private source so synthetic drag is not tied to physical mouse button state.
    /// (`.hidSystemState` reads real mouse = not pressed → Terminal ignores drag.)
    private static let eventSource = CGEventSource(stateID: .privateState)

    static func withInputLock(_ body: () -> Void) {
        injectLock.lock()
        defer { injectLock.unlock() }
        body()
    }

    static func inject(
        phase: Phase,
        xFraction: Double,
        yFraction: Double,
        button: Int,
        clickCount: Int,
        window: SCWindow
    ) {
        guard let pid = window.owningApplication?.processID else { return }
        let right = button == 2
        let count = max(1, min(3, clickCount))

        injectLock.lock()
        defer { injectLock.unlock() }

        // Resolve click point first — raise must put *this* window on top of that pixel.
        let point = WindowGeometry.globalPoint(
            xFraction: xFraction,
            yFraction: yFraction,
            windowID: window.windowID,
            fallback: window.frame
        )

        // CGEvent is hit-tested by z-order at `point`. If another app covers that
        // pixel, the event is ignored by the target — always raise first.
        if phase == .down {
            let ready = WindowFocus.isReadyForInput(
                pid: pid,
                windowID: window.windowID,
                at: point
            )
            if !ready || count <= 1 {
                _ = WindowFocus.ensureFocused(
                    pid: pid,
                    windowID: window.windowID,
                    title: window.title,
                    force: true,
                    at: point
                )
            }
        }

        postMouse(
            phase: phase,
            point: point,
            isRight: right,
            clickCount: count
        )
    }

    static func injectDisplay(
        phase: Phase,
        xFraction: Double,
        yFraction: Double,
        button: Int,
        clickCount: Int,
        displayID: CGDirectDisplayID
    ) {
        let right = button == 2
        injectLock.lock()
        defer { injectLock.unlock() }

        let point = DisplayGeometry.globalPoint(
            xFraction: xFraction,
            yFraction: yFraction,
            displayID: displayID
        )
        postMouse(phase: phase, point: point, isRight: right, clickCount: max(1, clickCount))
    }

    static func click(xFraction: Double, yFraction: Double, window: SCWindow) {
        inject(phase: .down, xFraction: xFraction, yFraction: yFraction, button: 0, clickCount: 1, window: window)
        usleep(20_000)
        inject(phase: .up, xFraction: xFraction, yFraction: yFraction, button: 0, clickCount: 1, window: window)
    }

    static func clickDisplay(xFraction: Double, yFraction: Double, displayID: CGDirectDisplayID) {
        injectDisplay(phase: .down, xFraction: xFraction, yFraction: yFraction, button: 0, clickCount: 1, displayID: displayID)
        usleep(20_000)
        injectDisplay(phase: .up, xFraction: xFraction, yFraction: yFraction, button: 0, clickCount: 1, displayID: displayID)
    }

    static func scroll(
        deltaX: Double,
        deltaY: Double,
        xFraction: Double,
        yFraction: Double,
        window: SCWindow
    ) {
        guard let pid = window.owningApplication?.processID else { return }

        injectLock.lock()
        defer { injectLock.unlock() }

        let point = WindowGeometry.globalPoint(
            xFraction: xFraction,
            yFraction: yFraction,
            windowID: window.windowID,
            fallback: window.frame
        )
        if !WindowFocus.isReadyForInput(pid: pid, windowID: window.windowID, at: point) {
            _ = WindowFocus.ensureFocused(
                pid: pid,
                windowID: window.windowID,
                title: window.title,
                force: true,
                at: point
            )
        }
        postScroll(deltaX: deltaX, deltaY: deltaY, point: point)
    }

    static func scrollDisplay(
        deltaX: Double,
        deltaY: Double,
        xFraction: Double,
        yFraction: Double,
        displayID: CGDirectDisplayID
    ) {
        injectLock.lock()
        defer { injectLock.unlock() }

        let point = DisplayGeometry.globalPoint(
            xFraction: xFraction,
            yFraction: yFraction,
            displayID: displayID
        )
        postScroll(deltaX: deltaX, deltaY: deltaY, point: point)
    }

    // MARK: - Low level

    /// Last posted cursor point — skip redundant mouseMoved that breaks multi-click.
    private static var lastCursorPoint: CGPoint = .init(x: -1, y: -1)
    private static let cursorEpsilon: CGFloat = 0.5

    private static func postMouse(
        phase: Phase,
        point: CGPoint,
        isRight: Bool,
        clickCount: Int
    ) {
        let type: CGEventType
        switch phase {
        case .down: type = isRight ? .rightMouseDown : .leftMouseDown
        case .up:   type = isRight ? .rightMouseUp : .leftMouseUp
        case .move: type = isRight ? .rightMouseDragged : .leftMouseDragged
        }
        let button: CGMouseButton = isRight ? .right : .left
        let source = eventSource
        let count = max(1, min(3, clickCount))

        // Place cursor before down only when it actually moved.
        // mouseMoved between double-click halves resets AppKit multi-click.
        if phase == .down {
            let dx = abs(point.x - lastCursorPoint.x)
            let dy = abs(point.y - lastCursorPoint.y)
            if dx > cursorEpsilon || dy > cursorEpsilon || lastCursorPoint.x < 0 {
                if let moved = CGEvent(
                    mouseEventSource: source,
                    mouseType: .mouseMoved,
                    mouseCursorPosition: point,
                    mouseButton: button
                ) {
                    moved.post(tap: .cghidEventTap)
                }
            }
        }

        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else { return }

        event.setIntegerValueField(.mouseEventButtonNumber, value: Int64(isRight ? 1 : 0))
        // 1=single, 2=double, 3=triple — down AND up must match for Finder/Dock.
        event.setIntegerValueField(.mouseEventClickState, value: Int64(count))
        event.setDoubleValueField(.mouseEventPressure, value: phase == .up ? 0 : 1)

        event.post(tap: .cghidEventTap)
        lastCursorPoint = point
    }

    private static func postScroll(deltaX: Double, deltaY: Double, point: CGPoint) {
        let source = eventSource
        if let move = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) {
            move.post(tap: .cghidEventTap)
        }
        let wheelY = Int32(max(-1200, min(1200, -deltaY)))
        let wheelX = Int32(max(-1200, min(1200, -deltaX)))
        if let wheel = CGEvent(
            scrollWheelEvent2Source: source,
            units: .pixel,
            wheelCount: 2,
            wheel1: wheelY,
            wheel2: wheelX,
            wheel3: 0
        ) {
            wheel.post(tap: .cghidEventTap)
        }
    }
}
