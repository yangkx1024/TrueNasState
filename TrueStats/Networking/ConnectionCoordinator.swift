import Foundation

/// Owns the live `TrueNASClient` and the reconnect policy around it, so the view model
/// only deals with "a client became available" and "we dropped and are retrying".
@MainActor
final class ConnectionCoordinator {
    /// Runs before every attempt so the caller can tear down whatever was bound to the
    /// previous client — subscription tasks, in-flight operation state.
    var onWillConnect: (() async -> Void)?
    /// A fresh, authenticated client.
    var onConnected: ((TrueNASClient) async -> Void)?
    /// The first failure of a retry sequence.
    var onReconnecting: (() -> Void)?
    /// The credentials themselves were rejected; retrying can't help.
    var onAuthFailure: ((Error) -> Void)?

    private(set) var client: TrueNASClient?
    private var credentials: Credentials?
    private var retryController: ReconnectController?

    /// A single attempt that surfaces its error. The login screen needs a bad host or a
    /// rejected key reported immediately rather than hidden behind a silent retry loop.
    func connect(credentials: Credentials) async throws {
        self.credentials = credentials
        try await establish(credentials)
    }

    /// Connects with backoff, for a connection that isn't established yet — app launch
    /// with saved credentials.
    func connectWithRetry(credentials: Credentials) {
        self.credentials = credentials
        startRetrying()
    }

    /// A live connection dropped: reset backoff and retry now. Cheap to call more than
    /// once, since several subscriptions notice the drop independently.
    func reconnect() {
        startRetrying()
    }

    func stop() async {
        stopRetrying()
        credentials = nil
        await releaseClient()
    }

    private func establish(_ credentials: Credentials) async throws {
        await onWillConnect?()
        await releaseClient()
        let client = try TrueNASClient(endpoint: credentials.endpoint, apiKey: credentials.apiKey)
        try await client.connect()
        self.client = client
        await onConnected?(client)
    }

    private func startRetrying() {
        guard let credentials else { return }
        if let retryController {
            retryController.resetAndRetryNow()
            return
        }
        let controller = ReconnectController()
        controller.attemptConnect = { [weak self] in
            guard let self else { throw CancellationError() }
            try await establish(credentials)
        }
        controller.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case .willEnterReconnecting:
                onReconnecting?()
            case .authFailure(let error):
                stopRetrying()
                onAuthFailure?(error)
            }
        }
        retryController = controller
        controller.start()
    }

    private func stopRetrying() {
        retryController?.stop()
        retryController = nil
    }

    private func releaseClient() async {
        await client?.disconnect()
        client = nil
    }
}
