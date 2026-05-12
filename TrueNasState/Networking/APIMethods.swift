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
        try await call(
            "app.query",
            params: [[], ["select": ["id", "name", "state", "upgrade_available", "metadata"]]],
            as: [TNApp].self
        )
    }

    /// Starts an app upgrade and returns the TrueNAS job id; the upgrade itself
    /// runs asynchronously and completion is reported via `subscribeJobs()`.
    @discardableResult
    func upgradeApp(name: String) async throws -> Int {
        let raw = try await callRaw(method: "app.upgrade", params: [name])
        guard let jobID = raw.intValue else {
            throw TrueNASClientError.unexpectedMessage
        }
        return jobID
    }

    /// Returns true when TrueNAS reports a system upgrade is available.
    /// `update.check_available` queries the upstream update server, so this
    /// is meant for occasional checks (connect / manual refresh), not polling.
    func fetchSystemUpdateAvailable() async throws -> Bool {
        let raw = try await callRaw(method: "update.check_available", params: [])
        return raw.objectValue?["status"]?.stringValue == "AVAILABLE"
    }

    /// Returns a `catalogName -> icon URL` map gathered from `catalog.apps`,
    /// which is the only TrueNAS surface that exposes per-app icons.
    func fetchCatalogIcons() async throws -> [String: URL] {
        let raw = try await callRaw(
            method: "catalog.apps",
            params: [["cache": true, "retrieve_all_trains": true]]
        )
        var result: [String: URL] = [:]
        for (_, trainValue) in raw.objectValue ?? [:] {
            for (appName, appValue) in trainValue.objectValue ?? [:] {
                if let urlString = appValue.objectValue?["icon_url"]?.stringValue,
                   let url = URL(string: urlString) {
                    result[appName] = url
                }
            }
        }
        return result
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

    /// TrueNAS only emits a delta payload per event; consumers re-fetch via `app.query`.
    func subscribeApps() async throws -> AsyncStream<JSONValue> {
        try await subscribe(event: "app.query")
    }

    /// Live updates from `core.get_jobs`. Reads `id` and `state` straight off the
    /// raw `JSONValue` so a busy server doesn't pay decode cost on every frame.
    func subscribeJobs() async throws -> AsyncStream<TNJob> {
        let raw = try await subscribe(event: "core.get_jobs")
        return AsyncStream { continuation in
            Task {
                for await value in raw {
                    guard let fields = value.objectValue?["fields"]?.objectValue,
                          let id = fields["id"]?.intValue else { continue }
                    let state = fields["state"]?.stringValue.flatMap(TNJobState.init(rawValue:))
                    continuation.yield(TNJob(id: id, state: state))
                }
                continuation.finish()
            }
        }
    }

    /// `app.stats` is published as a stream once subscribed (2 s default interval).
    func subscribeAppStats() async throws -> AsyncStream<[AppLiveStat]> {
        let raw = try await subscribe(event: "app.stats")
        return AsyncStream { continuation in
            Task {
                for await value in raw {
                    if let stats = AppLiveStat.parse(value) {
                        continuation.yield(stats)
                    }
                }
                continuation.finish()
            }
        }
    }
}
