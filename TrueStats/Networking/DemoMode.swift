import Foundation

/// Hardcoded demo account for App Store review. Entering the matching
/// endpoint + API key on the login screen bypasses the real WebSocket
/// and populates the dashboard with mock data so reviewers can see all
/// the app's screens without a reachable TrueNAS instance.
///
/// The `.example` TLD (RFC 2606) is reserved and never resolves, so
/// there's no risk of the demo host accidentally hitting a real server.
enum DemoMode {
    static let endpointHost = "demo.truenas.example"
    static let apiKey = "demo"

    static func matches(endpoint: URL, apiKey: String) -> Bool {
        endpoint.host?.lowercased() == endpointHost && apiKey == Self.apiKey
    }

    @MainActor
    static func populate(_ vm: DashboardViewModel) {
        vm.systemInfo = SystemInfo(
            version: "TrueNAS-SCALE-24.10.1",
            hostname: "demo-nas",
            uptimeSeconds: 3_600 * 24 * 5 + 3_600 * 7,
            physicalMemory: 32 * 1024 * 1024 * 1024,
            systemProduct: "Demo NAS",
            loadAverages: [1.2, 1.1, 0.9]
        )
        vm.pools = [
            Pool(id: 1, name: "tank", status: "ONLINE", healthy: true,
                 size: 4 * 1_000_000_000_000,
                 allocated: 1_800_000_000_000,
                 free: 2_200_000_000_000),
            Pool(id: 2, name: "backup", status: "ONLINE", healthy: true,
                 size: 2 * 1_000_000_000_000,
                 allocated: 500_000_000_000,
                 free: 1_500_000_000_000),
        ]
        vm.apps = [
            TNApp(id: "plex", name: "Plex", version: "1.40.0",
                  state: .running, upgradeAvailable: false, catalogName: "plex"),
            TNApp(id: "nextcloud", name: "Nextcloud", version: "28.0.3",
                  state: .running, upgradeAvailable: true, catalogName: "nextcloud"),
            TNApp(id: "jellyfin", name: "Jellyfin", version: "10.8.13",
                  state: .stopped, upgradeAvailable: false, catalogName: "jellyfin"),
        ]
        vm.alerts = [
            TNAlert(id: "demo-alert-1", level: "WARNING",
                    formatted: "Scrub of pool 'tank' finished with 0 errors.",
                    text: nil, dismissed: false,
                    datetime: Date().addingTimeInterval(-3_600)),
        ]
        vm.stats = RealtimeStats(
            cpuUsagePercent: 12.0,
            memoryUsedBytes: 8 * 1024 * 1024 * 1024,
            memoryTotalBytes: 32 * 1024 * 1024 * 1024
        )
        vm.appIcons = [:]
        vm.systemUpdateAvailable = false
        vm.lastUpdated = Date()
    }
}
