import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    var authState: AuthState = .loggedOut(error: nil)
    var systemInfo: SystemInfo?
    var pools: [Pool] = []
    var apps: [TNApp] = []
    var alerts: [TNAlert] = []
    var stats: RealtimeStats?
    var lastUpdated: Date?
    private(set) var screen: Screen = .dashboard
    private(set) var endpoint: URL?

    enum Screen: Equatable { case dashboard, appList }

    private let credentials = CredentialStore.shared
    private var client: TrueNASClient?
    private var workers: [Task<Void, Never>] = []
    private var didBootstrap = false

    init() {
        // The menu-bar popover is rebuilt on every click, so .task would re-fire login.
        Task { [weak self] in await self?.bootstrap() }
    }

    var activeAlertCount: Int { alerts.filter { $0.isActive }.count }

    func navigate(to screen: Screen) { self.screen = screen }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        guard let saved = credentials.load() else {
            authState = .loggedOut(error: nil)
            return
        }
        await connect(endpoint: saved.endpoint, apiKey: saved.apiKey, persistOnSuccess: false)
    }

    func login(endpointString: String, apiKey: String) async {
        guard let url = Self.normalizeEndpoint(endpointString) else {
            authState = .loggedOut(error: "Endpoint must be a valid https:// URL.")
            return
        }
        if url.scheme?.lowercased() != "https" {
            authState = .loggedOut(error: "Only https:// endpoints are supported.")
            return
        }
        await connect(endpoint: url, apiKey: apiKey, persistOnSuccess: true)
    }

    func logout() async {
        await stop()
        credentials.clear()
        systemInfo = nil
        pools = []
        apps = []
        alerts = []
        stats = nil
        lastUpdated = nil
        endpoint = nil
        screen = .dashboard
        didBootstrap = true
        authState = .loggedOut(error: nil)
    }

    func refresh() async { await loadSnapshot() }

    // MARK: - Internals

    private func connect(endpoint: URL, apiKey: String, persistOnSuccess: Bool) async {
        await stop()
        authState = .connecting

        let client: TrueNASClient
        do {
            client = try TrueNASClient(endpoint: endpoint, apiKey: apiKey)
            try await client.connect()
        } catch {
            self.client = nil
            authState = .loggedOut(error: error.localizedDescription)
            return
        }

        self.client = client
        self.endpoint = endpoint
        authState = .loggedIn

        if persistOnSuccess {
            try? credentials.save(Credentials(endpoint: endpoint, apiKey: apiKey))
        }

        await loadSnapshot()
        startSubscriptions()
        startPeriodicRefresh()
    }

    private func loadSnapshot() async {
        guard let client else { return }
        async let info = try? client.fetchSystemInfo()
        async let poolsTask = try? client.fetchPools()
        async let appsTask = try? client.fetchApps()
        async let alertsTask = try? client.fetchAlerts()
        let (i, p, ap, a) = await (info, poolsTask, appsTask, alertsTask)
        if let i, i != systemInfo { systemInfo = i }
        if let p, p != pools { pools = p }
        if let ap, ap != apps { apps = ap }
        if let a, a != alerts { alerts = a }
        lastUpdated = Date()
    }

    private func startPeriodicRefresh() {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { return }
                await self?.loadSnapshot()
            }
        }
        workers.append(task)
    }

    private func startSubscriptions() {
        guard let client else { return }

        let statsTask = Task { [weak self] in
            guard let stream = try? await client.subscribeRealtime() else { return }
            for await snapshot in stream {
                if Task.isCancelled { return }
                await MainActor.run {
                    guard let self else { return }
                    // TrueNAS emits partial frames (CPU only, then memory only); merge so a
                    // later frame doesn't blank out previously-seen fields.
                    let merged: RealtimeStats = {
                        if var current = self.stats { current.merge(snapshot); return current }
                        return snapshot
                    }()
                    if merged != self.stats {
                        self.stats = merged
                        self.lastUpdated = Date()
                    }
                }
            }
        }
        workers.append(statsTask)

        let alertsTask = Task { [weak self] in
            guard let stream = try? await client.subscribeAlerts() else { return }
            for await _ in stream {
                if Task.isCancelled { return }
                if let updated = try? await client.fetchAlerts() {
                    await MainActor.run {
                        guard let self else { return }
                        if updated != self.alerts {
                            self.alerts = updated
                            self.lastUpdated = Date()
                        }
                    }
                }
            }
        }
        workers.append(alertsTask)
    }

    private func stop() async {
        for task in workers { task.cancel() }
        workers.removeAll()
        await client?.disconnect()
        client = nil
    }

    static func normalizeEndpoint(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: withScheme) else { return nil }
        // Strip trailing slashes / path so we can append /api/current ourselves.
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard components.host?.isEmpty == false else { return nil }
        return components.url
    }
}
