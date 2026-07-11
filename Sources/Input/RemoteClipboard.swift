import AppKit
import Foundation

/// Read the Mac pasteboard for remote → browser clipboard sync.
enum RemoteClipboard {
    static let maxChars = 512_000

    /// Snapshot of current general pasteboard change count (main-thread safe).
    static func changeCount() -> Int {
        let work = { NSPasteboard.general.changeCount }
        if Thread.isMainThread { return work() }
        return DispatchQueue.main.sync(execute: work)
    }

    /// Best-effort plain text from the general pasteboard.
    static func readString() -> String? {
        let work = { () -> String? in
            let pb = NSPasteboard.general
            // Prefer plain string; fall back to common UTI names.
            let types: [NSPasteboard.PasteboardType] = [
                .string,
                NSPasteboard.PasteboardType("public.utf8-plain-text"),
                NSPasteboard.PasteboardType("public.utf16-external-plain-text"),
                .rtf,
            ]
            for type in types {
                if type == .rtf {
                    if let rtf = pb.string(forType: .rtf),
                       let data = rtf.data(using: .utf8),
                       let attr = try? NSAttributedString(
                        data: data,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                       ) {
                        let s = attr.string
                        if !s.isEmpty { return clip(s) }
                    }
                    continue
                }
                if let s = pb.string(forType: type), !s.isEmpty {
                    return clip(s)
                }
            }
            // Last resort: any string-like item
            if let items = pb.pasteboardItems {
                for item in items {
                    for t in item.types {
                        if let s = item.string(forType: t), !s.isEmpty,
                           (t.rawValue.contains("text") || t == .string) {
                            return clip(s)
                        }
                    }
                }
            }
            return nil
        }
        if Thread.isMainThread { return work() }
        return DispatchQueue.main.sync(execute: work)
    }

    /// After a copy shortcut, wait until pasteboard changeCount moves (or timeout).
    static func readStringAfterChange(from previous: Int, timeoutMs: Int = 800) -> String? {
        let deadline = CFAbsoluteTimeGetCurrent() + Double(timeoutMs) / 1000.0
        while CFAbsoluteTimeGetCurrent() < deadline {
            let now = changeCount()
            if now != previous {
                // Small settle for multi-type writes
                usleep(30_000)
                if let s = readString(), !s.isEmpty { return s }
            }
            usleep(25_000)
        }
        // Timeout: still try current contents (copy may have replaced same text)
        return readString()
    }

    private static func clip(_ s: String) -> String {
        if s.count > maxChars { return String(s.prefix(maxChars)) }
        return s
    }
}
