import Foundation

/// Disk cache for the `catalog.apps` icon map.
///
/// `catalog.apps` returns the whole catalog — megabytes — and its contents only move
/// when apps are added or updated upstream. Persisting the derived
/// `catalogName -> icon URL` map lets a cold launch paint icons immediately instead of
/// waiting on that fetch, and lets the fetch be skipped entirely while every installed
/// app is already covered.
enum AppIconCache {
    static func load(host: String) -> [String: URL] {
        guard let url = fileURL(host: host),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return raw.compactMapValues(URL.init(string:))
    }

    static func save(_ icons: [String: URL], host: String) {
        guard let url = fileURL(host: host),
              let data = try? JSONEncoder().encode(icons.mapValues(\.absoluteString))
        else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    static func clear(host: String) {
        guard let url = fileURL(host: host) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// One file per host, so pointing the app at a different server can't surface the
    /// previous catalog's icons.
    private static func fileURL(host: String) -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return support
            .appendingPathComponent("TrueStats", isDirectory: true)
            .appendingPathComponent("icons-\(sanitized(host)).json")
    }

    /// Hosts can carry characters that don't belong in a path component.
    static func sanitized(_ host: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return String(host.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
    }
}
