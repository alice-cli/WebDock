import Foundation

enum JSONMessage {
    static func encode(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func imeState(isKorean: Bool, label: String) -> String? {
        encode([
            "type": "ime",
            "korean": isKorean,
            "label": label,
        ])
    }
}
