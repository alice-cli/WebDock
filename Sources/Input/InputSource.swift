import AppKit
import Carbon
import ScreenCaptureKit

/// Korean / Latin keyboard input-source switching.
///
/// Never inject Escape on IME switch — KakaoTalk / chat apps treat Escape as
/// "close window". TISSelect alone is enough; client Hangul compose doesn't
/// need Mac compose-cancel either.
enum InputSource {
    struct State {
        let isKorean: Bool
        var label: String { isKorean ? "한" : "A" }
    }

    private static let lock = NSLock()
    private static var desiredKorean: Bool?

    static func currentState() -> State {
        State(isKorean: isKorean())
    }

    static func noteDesiredKorean(_ want: Bool) {
        lock.lock()
        desiredKorean = want
        lock.unlock()
    }

    static func desiredKoreanOrNil() -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return desiredKorean
    }

    @discardableResult
    static func toggle(focusing window: SCWindow?) -> State {
        let next = !isKorean()
        noteDesiredKorean(next)
        return setKorean(next, focusing: window)
    }

    @discardableResult
    static func setKorean(_ wantKorean: Bool, focusing window: SCWindow?) -> State {
        noteDesiredKorean(wantKorean)

        // Already correct → do nothing (re-select mid-type can reset compose).
        if isKorean() == wantKorean {
            return currentState()
        }

        // Soft focus only if target is covered — never Escape, never force-close paths.
        if let window, let pid = window.owningApplication?.processID {
            if !WindowFocus.isRecentlyFocused(pid: pid, windowID: window.windowID),
               !WindowFocus.isTopmostOnScreen(windowID: window.windowID) {
                WindowFocus.ensureFocused(
                    pid: pid,
                    windowID: window.windowID,
                    title: window.title,
                    force: false
                )
            }
        }

        let work = { () -> State in
            if wantKorean {
                _ = selectKorean()
            } else {
                _ = selectLatin()
            }
            usleep(12_000)
            var st = currentState()
            if st.isKorean != wantKorean {
                if wantKorean { _ = selectKorean() } else { _ = selectLatin() }
                usleep(12_000)
                st = currentState()
            }
            return st
        }

        if Thread.isMainThread { return work() }
        return DispatchQueue.main.sync(execute: work)
    }

    /// Disabled: typing-path heal caused more 자모 분리 than it fixed.
    @discardableResult
    static func autoHealIfNeeded(focusing window: SCWindow?, isLetterKey: Bool) -> State? {
        _ = window
        _ = isLetterKey
        return nil
    }

    /// Manual / explicit recovery only (client imeHeal hard). No Escape.
    @discardableResult
    static func hardHeal(wantKorean: Bool, focusing window: SCWindow?) -> State {
        print("IME hard-heal → \(wantKorean ? "한" : "A")")
        noteDesiredKorean(wantKorean)

        if let window, let pid = window.owningApplication?.processID {
            WindowFocus.ensureFocused(
                pid: pid,
                windowID: window.windowID,
                title: window.title,
                force: true
            )
        }
        usleep(8_000)
        // Force flip even if already correct (bypass early-return via select).
        let work = { () -> State in
            if wantKorean {
                _ = selectLatin()
                usleep(12_000)
                _ = selectKorean()
            } else {
                _ = selectKorean()
                usleep(12_000)
                _ = selectLatin()
            }
            usleep(12_000)
            return currentState()
        }
        if Thread.isMainThread { return work() }
        return DispatchQueue.main.sync(execute: work)
    }

    // MARK: - Select

    @discardableResult
    private static func selectKorean() -> Bool {
        let preferred = [
            "com.apple.inputmethod.Korean.2SetKorean",
            "com.apple.inputmethod.Korean.3SetKorean",
            "com.apple.inputmethod.Korean",
            "com.apple.inputmethod.Korean.390Sebulshik",
        ]
        if selectByIDs(preferred) { return true }
        for source in allKeyboardSources() {
            if isKoreanSourceID(sourceID(source)) {
                return select(source)
            }
        }
        print("IME: no Korean input source found")
        return false
    }

    @discardableResult
    private static func selectLatin() -> Bool {
        let preferred = [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US",
            "com.apple.keylayout.British",
        ]
        if selectByIDs(preferred) { return true }
        if let ascii = TISCopyCurrentASCIICapableKeyboardInputSource()?.takeRetainedValue() {
            let id = sourceID(ascii)
            if !isKoreanSourceID(id), select(ascii) { return true }
        }
        for source in allKeyboardSources() {
            let id = sourceID(source)
            if isLatinSourceID(id), !isKoreanSourceID(id) {
                return select(source)
            }
        }
        return false
    }

    private static func selectByIDs(_ ids: [String]) -> Bool {
        let sources = allKeyboardSources()
        for want in ids {
            if let match = sources.first(where: {
                let id = sourceID($0)
                return id == want || id.hasPrefix(want)
            }) {
                if select(match) { return true }
            }
        }
        return false
    }

    @discardableResult
    private static func select(_ source: TISInputSource) -> Bool {
        TISEnableInputSource(source)
        let err = TISSelectInputSource(source)
        if err != noErr {
            print("IME: TISSelectInputSource failed \(err) for \(sourceID(source))")
            return false
        }
        return true
    }

    // MARK: - Query

    private static func isKorean() -> Bool {
        let read = {
            isKoreanSourceID(sourceID(TISCopyCurrentKeyboardInputSource().takeRetainedValue()))
        }
        if Thread.isMainThread { return read() }
        return DispatchQueue.main.sync(execute: read)
    }

    private static func sourceID(_ source: TISInputSource) -> String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private static func allKeyboardSources() -> [TISInputSource] {
        let filter = [
            kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as Any
        ] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue(),
              let sources = list as? [TISInputSource]
        else { return [] }
        return sources
    }

    private static func isKoreanSourceID(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower.contains("korean")
            || lower.contains("hangul")
            || lower.contains("2set")
            || lower.contains("3set")
            || lower.contains("dubeolsik")
            || lower.contains("sebeolsik")
    }

    private static func isLatinSourceID(_ id: String) -> Bool {
        id.hasPrefix("com.apple.keylayout.")
            || id.contains("ABC")
            || id.contains(".US")
            || id.contains("British")
    }
}
