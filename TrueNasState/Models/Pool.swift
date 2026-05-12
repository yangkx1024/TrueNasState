import Foundation

struct Pool: Decodable, Identifiable, Equatable {
    let id: Int
    let name: String
    let status: String?
    let healthy: Bool?
    let size: Int64?
    let allocated: Int64?
    let free: Int64?

    enum CodingKeys: String, CodingKey {
        case id, name, status, healthy, size, allocated, free
    }

    init(id: Int, name: String, status: String?, healthy: Bool?,
         size: Int64?, allocated: Int64?, free: Int64?) {
        self.id = id
        self.name = name
        self.status = status
        self.healthy = healthy
        self.size = size
        self.allocated = allocated
        self.free = free
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? c.decode(Int.self, forKey: .id)) ?? 0
        self.name = (try? c.decode(String.self, forKey: .name)) ?? "unknown"
        self.status = try? c.decode(String.self, forKey: .status)
        self.healthy = try? c.decode(Bool.self, forKey: .healthy)
        self.size = Pool.decodeNumber(c, key: .size)
        self.allocated = Pool.decodeNumber(c, key: .allocated)
        self.free = Pool.decodeNumber(c, key: .free)
    }

    private static func decodeNumber(_ c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Int64? {
        if let i = try? c.decode(Int64.self, forKey: key) { return i }
        if let s = try? c.decode(String.self, forKey: key) { return Int64(s) }
        return nil
    }

    var usageFraction: Double? {
        guard let size, let allocated, size > 0 else { return nil }
        return Double(allocated) / Double(size)
    }

    var formattedUsage: String? {
        guard let allocated, let size else { return nil }
        let used = ByteCountFormatter.string(fromByteCount: allocated, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "\(used) / \(total)"
    }

    var displayStatus: String { status ?? (healthy == true ? "ONLINE" : "UNKNOWN") }
    var isHealthy: Bool { healthy ?? (status?.uppercased() == "ONLINE") }
}
