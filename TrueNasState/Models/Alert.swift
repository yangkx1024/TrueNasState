import Foundation

/// Mirrors the TrueNAS 26 `alert.list` method/event schema (docs at
/// `/api/docs/current/api_methods_alert.list.html`). Fields are decoded
/// defensively because some optional fields appear as `null`.
struct TNAlert: Decodable, Identifiable, Equatable {
    let id: String
    let level: String?
    let formatted: String?
    let text: String?
    let dismissed: Bool?
    let datetime: Date?

    enum CodingKeys: String, CodingKey {
        case uuid
        case altId = "id"
        case level
        case formatted
        case text
        case dismissed
        case datetime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The API exposes both `uuid` and a string `id` — prefer the stable uuid.
        if let s = try? c.decode(String.self, forKey: .uuid) {
            self.id = s
        } else if let s = try? c.decode(String.self, forKey: .altId) {
            self.id = s
        } else {
            self.id = UUID().uuidString
        }
        self.level = try? c.decode(String.self, forKey: .level)
        self.formatted = try? c.decode(String.self, forKey: .formatted)
        self.text = try? c.decode(String.self, forKey: .text)
        self.dismissed = try? c.decode(Bool.self, forKey: .dismissed)
        self.datetime = TNAlert.decodeDate(c)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func decodeDate(_ c: KeyedDecodingContainer<CodingKeys>) -> Date? {
        if let s = try? c.decode(String.self, forKey: .datetime) {
            if let d = isoFormatter.date(from: s) { return d }
            let plain = ISO8601DateFormatter()
            if let d = plain.date(from: s) { return d }
        }
        // Legacy: some older builds returned `{"$date": <ms>}` or a number of ms.
        if let ms = try? c.decode(Double.self, forKey: .datetime) {
            return Date(timeIntervalSince1970: ms / 1000.0)
        }
        if let nested = try? c.decode([String: Double].self, forKey: .datetime),
           let ms = nested["$date"] {
            return Date(timeIntervalSince1970: ms / 1000.0)
        }
        return nil
    }

    var displayText: String { formatted ?? text ?? String(localized: "(no description)") }
    var isActive: Bool { dismissed != true }
}
