import Foundation

/// High-level, typed wrappers over the JSON-RPC surface that the dashboard uses.
extension TrueNASClient {
    func fetchSystemInfo() async throws -> SystemInfo {
        try await call("system.info", as: SystemInfo.self)
    }

    func fetchPools() async throws -> [Pool] {
        try await call(
            "pool.query",
            params: [[], ["select": ["id", "name", "status", "healthy", "size", "allocated"]]],
            as: [Pool].self
        )
    }

    func fetchAlerts() async throws -> [TNAlert] {
        try await call("alert.list", as: [TNAlert].self)
    }

    func fetchApps() async throws -> [TNApp] {
        try await call("app.query", params: [[], ["select": ["id", "name", "state", "upgrade_available"]]], as: [TNApp].self)
    }

    /// `reporting.realtime` is published as a stream of stat snapshots once subscribed.
    func subscribeRealtime() async throws -> AsyncStream<RealtimeStats> {
        let raw = try await subscribe(event: "reporting.realtime")
        return AsyncStream { continuation in
            Task {
                for await value in raw {
                    if let stats = RealtimeStats(jsonValue: value) {
                        continuation.yield(stats)
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Subscribe to alert changes so the badge count stays live.
    func subscribeAlerts() async throws -> AsyncStream<JSONValue> {
        try await subscribe(event: "alert.list")
    }
}
