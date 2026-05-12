import Foundation

/// One entry from an `app.stats` notification's `fields` array.
/// Schema reference: TrueNAS 26 API event `app.stats`.
struct AppLiveStat: Equatable {
    let appName: String
    let cpuUsage: Double
    let memoryBytes: Int64

    var cpuText: String { "\(Int(cpuUsage.rounded()))%" }

    var memoryText: String {
        ByteCountFormatter.string(fromByteCount: memoryBytes, countStyle: .memory)
    }

    /// Parse the `fields` array out of a notification payload.
    /// Returns nil if the payload doesn't carry the expected shape.
    static func parse(_ jsonValue: JSONValue) -> [AppLiveStat]? {
        let fields: [JSONValue]?
        if let obj = jsonValue.objectValue {
            fields = obj["fields"]?.arrayValue ?? obj["data"]?.objectValue?["fields"]?.arrayValue
        } else {
            fields = nil
        }
        guard let entries = fields else { return nil }
        return entries.compactMap { entry in
            guard
                let obj = entry.objectValue,
                let name = obj["app_name"]?.stringValue,
                let cpu = obj["cpu_usage"]?.doubleValue,
                let mem = obj["memory"]?.intValue
            else { return nil }
            return AppLiveStat(appName: name, cpuUsage: cpu, memoryBytes: Int64(mem))
        }
    }
}
