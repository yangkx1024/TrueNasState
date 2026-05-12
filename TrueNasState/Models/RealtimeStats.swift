import Foundation

/// Snapshot built from one `reporting.realtime` notification frame.
/// Schema reference: TrueNAS 26 docs — event `reporting.realtime` →
/// `fields.cpu`, `fields.memory.{physical_memory_total, physical_memory_available, arc_size, …}`.
/// Frames are sometimes partial, so the view model merges successive snapshots.
struct RealtimeStats: Equatable {
    var cpuUsagePercent: Double?
    var memoryUsedBytes: Int64?
    var memoryTotalBytes: Int64?

    var memoryFraction: Double? {
        guard let used = memoryUsedBytes, let total = memoryTotalBytes, total > 0 else { return nil }
        return Double(used) / Double(total)
    }

    var formattedMemory: String? {
        guard let used = memoryUsedBytes, let total = memoryTotalBytes else { return nil }
        let u = ByteCountFormatter.string(fromByteCount: used, countStyle: .memory)
        let t = ByteCountFormatter.string(fromByteCount: total, countStyle: .memory)
        return "\(u) / \(t)"
    }

    init(cpuUsagePercent: Double? = nil,
         memoryUsedBytes: Int64? = nil,
         memoryTotalBytes: Int64? = nil) {
        self.cpuUsagePercent = cpuUsagePercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
    }

    /// Overlay non-nil fields from `other` onto `self`.
    mutating func merge(_ other: RealtimeStats) {
        if let v = other.cpuUsagePercent { cpuUsagePercent = v }
        if let v = other.memoryUsedBytes { memoryUsedBytes = v }
        if let v = other.memoryTotalBytes { memoryTotalBytes = v }
    }

    /// Parse a raw `params` value from a `reporting.realtime` notification.
    /// The notification wraps the snapshot in `fields`. Returns nil if no known field decoded.
    init?(jsonValue: JSONValue) {
        let fields: [String: JSONValue]
        if let obj = jsonValue.objectValue, let nested = obj["fields"]?.objectValue {
            fields = nested
        } else if let obj = jsonValue.objectValue {
            fields = obj
        } else {
            return nil
        }

        // CPU schema (TrueNAS 26 middleware/reporting/realtime_reporting/cpu.py):
        //   fields.cpu = { "cpu": {"usage": x, "temp": y}, "cpu0": {...}, "cpu1": {...}, ... }
        // The aggregate sits at `cpu.cpu.usage`. If that's null while netdata warms up,
        // fall back to averaging the per-core `cpuN.usage` values.
        let cpu = fields["cpu"]?.objectValue
        let cpuUsage: Double? = {
            if let v = cpu?["cpu"]?.objectValue?["usage"]?.doubleValue { return v }
            // Older / alternate shapes seen in the wild:
            if let v = cpu?["usage"]?.doubleValue { return v }
            if let v = cpu?["average"]?.objectValue?["usage"]?.doubleValue { return v }
            // Per-core average fallback.
            guard let cpu else { return nil }
            let coreUsages = cpu.compactMap { key, value -> Double? in
                guard key.hasPrefix("cpu"), key != "cpu" else { return nil }
                return value.objectValue?["usage"]?.doubleValue
            }
            guard !coreUsages.isEmpty else { return nil }
            return coreUsages.reduce(0, +) / Double(coreUsages.count)
        }()

        // Memory: TrueNAS 26 publishes `memory.physical_memory_total` and
        // `memory.physical_memory_available` (bytes). `used = total - available`.
        let memory = fields["memory"]?.objectValue
        let total = memory?["physical_memory_total"]?.intValue.map(Int64.init)
        let available = memory?["physical_memory_available"]?.intValue.map(Int64.init)
        let used: Int64? = {
            if let total, let available { return max(total - available, 0) }
            return nil
        }()

        guard cpuUsage != nil || used != nil || total != nil else { return nil }

        self.cpuUsagePercent = cpuUsage
        self.memoryUsedBytes = used
        self.memoryTotalBytes = total
    }
}
