import Foundation

struct SystemInfo: Decodable, Equatable {
    let version: String?
    let hostname: String?
    let uptimeSeconds: Double?
    let physicalMemory: Int64?
    let systemProduct: String?
    /// `loadavg` is an array of three numbers: 1m, 5m, 15m. The `reporting.realtime`
    /// event does NOT carry load average, so this is the only place to surface it.
    let loadAverages: [Double]?

    enum CodingKeys: String, CodingKey {
        case version
        case hostname
        case uptimeSeconds = "uptime_seconds"
        case physicalMemory = "physmem"
        case systemProduct = "system_product"
        case loadAverages = "loadavg"
    }

    init(version: String?, hostname: String?, uptimeSeconds: Double?,
         physicalMemory: Int64?, systemProduct: String?, loadAverages: [Double]?) {
        self.version = version
        self.hostname = hostname
        self.uptimeSeconds = uptimeSeconds
        self.physicalMemory = physicalMemory
        self.systemProduct = systemProduct
        self.loadAverages = loadAverages
    }

    var loadAverage1m: Double? { loadAverages?.first }

    var formattedUptime: String? {
        guard let u = uptimeSeconds, u > 0 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: u)
    }
}
