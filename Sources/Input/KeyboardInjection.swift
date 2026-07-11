import AppKit
import CoreGraphics
import ScreenCaptureKit

enum KeyboardInjection {
    /// Unicode text (bottom box, paste, client Hangul). `replace` = Backspace count first.
    static func injectText(_ text: String, window: SCWindow, replace: Int = 0) {
        guard let pid = window.owningApplication?.processID else { return }
        let rep = max(0, replace)
        guard !text.isEmpty || rep > 0 else { return }

        MouseInjection.withInputLock {
            if !WindowFocus.isTopmostOnScreen(windowID: window.windowID) {
                WindowFocus.ensureFocused(
                    pid: pid,
                    windowID: window.windowID,
                    title: window.title,
                    force: true
                )
                usleep(8_000)
            }
            for _ in 0..<rep {
                postKey(keyCode: 51, command: false, shift: false, control: false, option: false)
                usleep(2_000)
            }
            if !text.isEmpty {
                postUnicodeString(text)
            }
        }
    }

    static func injectKey(
        code: String,
        command: Bool,
        shift: Bool,
        control: Bool,
        option: Bool,
        window: SCWindow
    ) {
        guard let pid = window.owningApplication?.processID,
              let keyCode = KeyCodes.code(for: code)
        else { return }

        MouseInjection.withInputLock {
            // 단축키일 때만 raise — 일반 타자 중 force focus는 조합/포커스를 깨뜨림.
            if command || control {
                if !WindowFocus.isTopmostOnScreen(windowID: window.windowID) {
                    WindowFocus.ensureFocused(
                        pid: pid,
                        windowID: window.windowID,
                        title: window.title,
                        force: true
                    )
                }
            }
            postKey(
                keyCode: keyCode,
                command: command,
                shift: shift,
                control: control,
                option: option
            )
        }
    }

    static func injectKeyGlobal(
        code: String,
        command: Bool,
        shift: Bool,
        control: Bool,
        option: Bool
    ) {
        guard let keyCode = KeyCodes.code(for: code) else { return }
        MouseInjection.withInputLock {
            postKey(
                keyCode: keyCode,
                command: command,
                shift: shift,
                control: control,
                option: option
            )
        }
    }

    static func injectTextGlobal(_ text: String, replace: Int = 0) {
        let rep = max(0, replace)
        guard !text.isEmpty || rep > 0 else { return }
        MouseInjection.withInputLock {
            for _ in 0..<rep {
                postKey(keyCode: 51, command: false, shift: false, control: false, option: false)
                usleep(2_000)
            }
            if !text.isEmpty {
                postUnicodeString(text)
            }
        }
    }

    // MARK: - Low-level

    private static func postUnicodeString(_ text: String) {
        // NFC Hangul syllables — inject as whole string chunks when possible.
        let normalized = text.precomposedStringWithCanonicalMapping
        // Post per Character (extended grapheme) so each Hangul syllable is one event.
        for ch in normalized {
            postUnicode(ch)
            usleep(1_500)
        }
    }

    private static func postUnicode(_ character: Character) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let utf16 = Array(String(character).utf16)
        guard !utf16.isEmpty else { return }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        keyDown?.flags = []
        keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyDown?.post(tap: .cgSessionEventTap)

        usleep(1_000)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        keyUp?.flags = []
        keyUp?.post(tap: .cgSessionEventTap)
    }

    private static func postKey(
        keyCode: CGKeyCode,
        command: Bool = false,
        shift: Bool = false,
        control: Bool = false,
        option: Bool = false
    ) {
        let isShortcut = command || control
        // privateState for synthetic keys is stable across apps; hidSystemState
        // can couple to real modifier state and break remote Hangul/latin typing.
        let source = CGEventSource(stateID: .privateState)
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        if option { flags.insert(.maskAlternate) }
        if control { flags.insert(.maskControl) }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.flags = flags
        keyDown?.post(tap: .cghidEventTap)

        usleep(isShortcut ? 5_000 : 3_000)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.flags = isShortcut ? [] : flags
        keyUp?.post(tap: .cghidEventTap)
    }
}

enum KeyCodes {
    static let v: CGKeyCode = 9

    static func code(for browserCode: String) -> CGKeyCode? {
        map[browserCode]
    }

    private static let map: [String: CGKeyCode] = [
        "KeyA": 0, "KeyS": 1, "KeyD": 2, "KeyF": 3, "KeyH": 4, "KeyG": 5,
        "KeyZ": 6, "KeyX": 7, "KeyC": 8, "KeyV": 9, "KeyB": 11,
        "KeyQ": 12, "KeyW": 13, "KeyE": 14, "KeyR": 15, "KeyY": 16, "KeyT": 17,
        "Digit1": 18, "Digit2": 19, "Digit3": 20, "Digit4": 21, "Digit6": 22, "Digit5": 23,
        "Equal": 24, "Digit9": 25, "Digit7": 26, "Minus": 27, "Digit8": 28, "Digit0": 29,
        "BracketRight": 30, "KeyO": 31, "KeyU": 32, "BracketLeft": 33, "KeyI": 34, "KeyP": 35,
        "Enter": 36, "Return": 36, "KeyL": 37, "KeyJ": 38, "Quote": 39, "KeyK": 40,
        "Semicolon": 41, "Backslash": 42, "Comma": 43, "Slash": 44, "KeyN": 45, "KeyM": 46,
        "Period": 47, "Tab": 48, "Space": 49, "Backquote": 50, "Backspace": 51, "Escape": 53,
        "CapsLock": 57,
        "Delete": 117, "ForwardDelete": 117, "Home": 115, "End": 119,
        "PageUp": 116, "PageDown": 121,
        "ArrowLeft": 123, "ArrowRight": 124, "ArrowDown": 125, "ArrowUp": 126,
        "Numpad0": 82, "Numpad1": 83, "Numpad2": 84, "Numpad3": 85, "Numpad4": 86,
        "Numpad5": 87, "Numpad6": 88, "Numpad7": 89, "Numpad8": 91, "Numpad9": 92,
        "NumpadDecimal": 65, "NumpadMultiply": 67, "NumpadAdd": 69,
        "NumpadDivide": 75, "NumpadEnter": 76, "NumpadSubtract": 78, "NumpadEqual": 81,
        "NumLock": 71,
    ]
}
