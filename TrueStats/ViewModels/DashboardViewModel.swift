import Foundation
import Observation

/// Presentation state for the popover: what the screens read, and the user intents
/// they trigger.
///
/// Connection policy lives in `ConnectionCoordinator`, in-flight app operations in
/// `AppOperationTracker`, and demo data in `DemoMode`. What's left here is mapping
/// TrueNAS streams onto observable state.
@MainActor
@Observable
final class DashboardViewModel {
    private(set) var authState: AuthState = .loggedOut(error: nil)
    private(set) var systemInfo: SystemInfo?
    private(set) var pools: [Pool] = []
    private(set) var apps: [TNApp] = []
    private(set) var alerts: [TNAlert] = []
    private(set) var stats: RealtimeStats?
    private(set) var appStats: [String: AppLiveStat] = [:]
    private(set) var appIcons: [String: URL] = [:]
    private(set) var systemUpdateAvailable = false
    private(set) var lastUpdated: Date?
    private(set) var screen: Screen = .dashboard
    private(set) var endpoint: URL?

    enum Screen: Equatable { case dashboard, appList, settings }

    private let credentials = CredentialStore.shared
    private let connection = ConnectionCoordinator()
    private let operations = AppOperationTracker()
    private var workers: [Task<Void, Never>] = []
    private var didBootstrap = false
    private var demoTickerTask: Task<Void, Never>?
    private var didFetchCatalogIcons = false

    private var client: TrueNASClient? { connection.client }

    init() {
        connection.onWillConnect = { [weak self] in await self?.teardownSession() }
        connection.onConnected = { [weak self] client in await self?.sessionDidConnect(client) }
        connection.onReconnecting = { [weak self] in
            guard let self, authState == .connecting else { return }
            authState = .reconnecting
        }
        connection.onAuthFailure = { [weak self] error in
            guard let self else { return }
            credentials.clear()
            authState = .loggedOut(error: error.localizedDescription)
        }
        operations.onFinish = { [weak self] _ in
            // togglingApps just cleared, so a fresh fetch is no longer filtered by the
            // merge step. Covers the case where the state didn't change and no
            // app.query event will fire.
            Task { [weak self] in await self?.refreshApps() }
        }
        // The menu-bar popover is rebuilt on every click, so .task would re-fire login.
        Task { [weak self] in await self?.bootstrap() }
    }

    // MARK: - Derived state

    var activeAlertCount: Int { alerts.filter { $0.isActive }.count }

    func isUpgrading(_ appID: String) -> Bool { operations.isUpgrading(appID) }
    func isToggling(_ appID: String) -> Bool { operations.isToggling(appID) }

    func navigate(to screen: Screen) {
        self.screen = screen
    }

    // MARK: - Session lifecycle

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        guard let saved = credentials.load() else {
            authState = .loggedOut(error: nil)
            return
        }
        if DemoMode.matches(endpoint: saved.endpoint, apiKey: saved.apiKey) {
            await enterDemoMode(endpoint: saved.endpoint, apiKey: saved.apiKey, persistOnSuccess: false)
            return
        }
        authState = .connecting
        endpoint = saved.endpoint
        connection.connectWithRetry(credentials: saved)
    }

    func login(endpointString: String, apiKey: String) async {
        guard let url = Self.normalizeEndpoint(endpointString) else {
            authState = .loggedOut(error: String(localized: "Endpoint must be a valid https:// URL."))
            return
        }
        if url.scheme?.lowercased() != "https" {
            authState = .loggedOut(error: String(localized: "Only https:// endpoints are supported."))
            return
        }
        await connect(endpoint: url, apiKey: apiKey, persistOnSuccess: true)
    }

    func logout() async {
        await stop()
        if let host = endpoint?.host { AppIconCache.clear(host: host) }
        credentials.clear()
        didFetchCatalogIcons = false
        systemInfo = nil
        pools = []
        apps = []
        alerts = []
        stats = nil
        appStats = [:]
        appIcons = [:]
        systemUpdateAvailable = false
        lastUpdated = nil
        endpoint = nil
        screen = .dashboard
        didBootstrap = true
        authState = .loggedOut(error: nil)
    }

    private func connect(endpoint: URL, apiKey: String, persistOnSuccess: Bool) async {
        if DemoMode.matches(endpoint: endpoint, apiKey: apiKey) {
            await enterDemoMode(endpoint: endpoint, apiKey: apiKey, persistOnSuccess: persistOnSuccess)
            return
        }
        authState = .connecting
        self.endpoint = endpoint
        let creds = Credentials(endpoint: endpoint, apiKey: apiKey)
        do {
            try await connection.connect(credentials: creds)
        } catch {
            authState = .loggedOut(error: error.localizedDescription)
            return
        }
        if persistOnSuccess {
            try? credentials.save(creds)
        }
    }

    /// Post-connect setup: load what the dashboard shows, then start the streams that
    /// keep it fresh.
    private func sessionDidConnect(_ client: TrueNASClient) async {
        authState = .loggedIn
        loadCachedCatalogIcons()
        async let snapshot: Void = loadSnapshot()
        async let updateStatus: Void = loadSystemUpdateStatus()
        _ = await (snapshot, updateStatus)
        startSubscriptions(client: client)
        startPeriodicRefresh()
        // Deliberately not awaited: the catalog fetch must not hold up subscriptions.
        workers.append(Task { [weak self] in await self?.refreshCatalogIconsIfNeeded() })
    }

    /// Tears down everything bound to a client without touching the client itself, so
    /// it can run before a reconnect attempt as well as on a full stop.
    private func teardownSession() async {
        for task in workers { task.cancel() }
        workers.removeAll()
        operations.reset()
        demoTickerTask?.cancel()
        demoTickerTask = nil
    }

    private func stop() async {
        await teardownSession()
        await connection.stop()
    }

    private func notifyConnectionLost() {
        guard authState == .loggedIn else { return }
        authState = .reconnecting
        connection.reconnect()
    }

    // MARK: - App operations

    func upgradeApp(_ app: TNApp) async {
        guard let client, !operations.isUpgrading(app.id) else { return }
        operations.beginUpgrade(app.id)
        do {
            let jobID = try await client.upgradeApp(name: app.id)
            operations.bind(jobID: jobID, to: app.id)
            // Surface RUNNING → DEPLOYING before the job stream fires.
            await loadSnapshot()
        } catch {
            operations.cancel(app.id)
            Log.dashboard.error(
                "upgrade \(app.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startApp(_ app: TNApp) async { await toggleApp(app, action: .start) }
    func stopApp(_ app: TNApp)  async { await toggleApp(app, action: .stop) }

    private enum AppToggleAction { case start, stop }

    private func toggleApp(_ app: TNApp, action: AppToggleAction) async {
        guard !operations.isToggling(app.id) else { return }
        guard let idx = apps.firstIndex(where: { $0.id == app.id }) else { return }
        guard let client else {
            // Demo mode: flip the row locally so reviewers see the buttons working.
            apps[idx].state = (action == .start) ? .running : .stopped
            return
        }
        let originalState = apps[idx].state
        operations.beginToggle(app.id)
        // Surface STOPPING / DEPLOYING immediately — TrueNAS sometimes jumps
        // straight to the terminal state on fast operations and never publishes
        // the transitional snapshot.
        apps[idx].state = (action == .start) ? .deploying : .stopping
        do {
            let jobID: Int
            switch action {
            case .start: jobID = try await client.startApp(name: app.id)
            case .stop:  jobID = try await client.stopApp(name: app.id)
            }
            operations.bind(jobID: jobID, to: app.id)
        } catch {
            operations.cancel(app.id)
            if let idx = apps.firstIndex(where: { $0.id == app.id }) {
                apps[idx].state = originalState
            }
            Log.dashboard.error(
                "toggle \(app.id, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Loading

    /// Seeds icons from the on-disk cache so the app list paints immediately on a cold
    /// launch rather than waiting on the catalog fetch.
    private func loadCachedCatalogIcons() {
        guard appIcons.isEmpty, let host = endpoint?.host else { return }
        let cached = AppIconCache.load(host: host)
        if !cached.isEmpty { appIcons = cached }
    }

    /// Pulls `catalog.apps` at most once per session, and only when an installed app
    /// isn't already covered by the cached map — the payload is megabytes.
    private func refreshCatalogIconsIfNeeded() async {
        guard let client, let host = endpoint?.host, !didFetchCatalogIcons else { return }
        guard apps.contains(where: { appIcons[$0.catalogName ?? $0.name] == nil }) else { return }
        didFetchCatalogIcons = true
        guard let icons = try? await client.fetchCatalogIcons(), !icons.isEmpty else { return }
        if icons != appIcons { appIcons = icons }
        AppIconCache.save(icons, host: host)
    }

    private func loadSystemUpdateStatus() async {
        guard let client else { return }
        // Coalesce probe error to false so a stale `true` doesn't persist if the
        // upstream update server becomes unreachable after a previous success.
        let available = (try? await client.fetchSystemUpdateAvailable()) ?? false
        if available != systemUpdateAvailable {
            systemUpdateAvailable = available
        }
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

    /// Fetches `app.query` and assigns, keeping the optimistic transitional
    /// state for any app with an operation in flight (TrueNAS may briefly
    /// echo the pre-action state before the job terminates).
    private func refreshApps() async {
        guard let client, let updated = try? await client.fetchApps() else { return }
        let merged: [TNApp] = updated.map { fetched in
            guard operations.isToggling(fetched.id),
                  let existing = apps.first(where: { $0.id == fetched.id })
            else { return fetched }
            var copy = fetched
            copy.state = existing.state
            return copy
        }
        if merged != apps {
            apps = merged
            lastUpdated = Date()
        }
    }

    // MARK: - Subscriptions

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

    private func startSubscriptions(client: TrueNASClient) {
        let statsTask = Task { [weak self] in
            guard let stream = try? await client.subscribeRealtime() else {
                if !Task.isCancelled { self?.notifyConnectionLost() }
                return
            }
            for await snapshot in stream {
                if Task.isCancelled { return }
                guard let self else { return }
                // TrueNAS emits partial frames (CPU only, then memory only); merge so a
                // later frame doesn't blank out previously-seen fields.
                var merged = stats ?? RealtimeStats()
                merged.merge(snapshot)
                if merged != stats {
                    stats = merged
                    lastUpdated = Date()
                }
            }
            if !Task.isCancelled { self?.notifyConnectionLost() }
        }
        workers.append(statsTask)

        workers.append(refetchOnEvent(
            subscribe: { try await client.subscribeAlerts() },
            fetch: { try await client.fetchAlerts() },
            keyPath: \.alerts
        ))

        let appsTask = Task { [weak self] in
            guard let stream = try? await client.subscribeApps() else {
                if !Task.isCancelled { self?.notifyConnectionLost() }
                return
            }
            for await _ in stream {
                if Task.isCancelled { return }
                await self?.refreshApps()
                try? await Task.sleep(for: .milliseconds(250))
            }
            if !Task.isCancelled { self?.notifyConnectionLost() }
        }
        workers.append(appsTask)

        let jobsTask = Task { [weak self] in
            guard let stream = try? await client.subscribeJobs() else { return }
            for await job in stream {
                if Task.isCancelled { return }
                guard let self else { return }
                operations.note(job)
            }
        }
        workers.append(jobsTask)
    }

    /// Subscribes to a TrueNAS collection event and re-fetches via `fetch` on each
    /// frame. The trailing sleep throttles bursts (e.g. an upgrade-all transitions
    /// every app through DEPLOYING → RUNNING in quick succession) so the loop
    /// caps at ~4 fetches/sec instead of one fetch per delta event.
    private func refetchOnEvent<T: Equatable>(
        subscribe: @escaping () async throws -> AsyncStream<JSONValue>,
        fetch: @escaping () async throws -> T,
        keyPath: ReferenceWritableKeyPath<DashboardViewModel, T>
    ) -> Task<Void, Never> {
        Task { [weak self] in
            guard let stream = try? await subscribe() else {
                if !Task.isCancelled { self?.notifyConnectionLost() }
                return
            }
            for await _ in stream {
                if Task.isCancelled { return }
                if let updated = try? await fetch() {
                    if Task.isCancelled { return }
                    guard let self else { return }
                    if updated != self[keyPath: keyPath] {
                        self[keyPath: keyPath] = updated
                        lastUpdated = Date()
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
            if !Task.isCancelled { self?.notifyConnectionLost() }
        }
    }

    /// Streams `app.stats` for as long as the caller's task lives. `AppListView` drives
    /// this from `.task`, so the subscription is tied to the screen actually being on
    /// screen rather than to a side effect of navigating.
    func streamAppStats() async {
        defer { appStats = [:] }
        guard let client, let stream = try? await client.subscribeAppStats() else { return }
        for await frame in stream {
            let next = Dictionary(uniqueKeysWithValues: frame.map { ($0.appName, $0) })
            if next != appStats { appStats = next }
        }
    }

    // MARK: - Demo mode

    private func enterDemoMode(endpoint: URL, apiKey: String, persistOnSuccess: Bool) async {
        authState = .connecting
        await stop()
        self.endpoint = endpoint
        apply(DemoMode.snapshot())
        authState = .loggedIn
        if persistOnSuccess {
            try? credentials.save(Credentials(endpoint: endpoint, apiKey: apiKey))
        }
        startDemoTicker()
    }

    private func apply(_ demo: DemoSnapshot) {
        systemInfo = demo.systemInfo
        pools = demo.pools
        apps = demo.apps
        alerts = demo.alerts
        stats = demo.stats
        appIcons = [:]
        systemUpdateAvailable = false
        lastUpdated = Date()
    }

    private func startDemoTicker() {
        demoTickerTask?.cancel()
        demoTickerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                stats = DemoMode.nextStats(after: stats)
                lastUpdated = Date()
            }
        }
    }

    // MARK: - Endpoint

    static func normalizeEndpoint(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: withScheme) else { return nil }
        // Strip trailing slashes / path so we can append /api/current ourselves.
        components.stripPathQueryAndFragment()
        guard components.host?.isEmpty == false else { return nil }
        return components.url
    }
}
