import Foundation

enum TrueNASClientError: Error, LocalizedError {
    case invalidEndpoint
    case notConnected
    case unexpectedMessage
    case authenticationFailed(String)
    case decodingFailed(Error)
    case rpcFailed(JSONRPCError)
    case transport(Error)
    case serverClosed(code: Int, reason: String)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Endpoint must be a valid http:// or https:// URL."
        case .notConnected: return "Not connected to TrueNAS."
        case .unexpectedMessage: return "Received an unexpected message from TrueNAS."
        case .authenticationFailed(let m): return "Authentication failed: \(m)"
        case .decodingFailed(let e): return "Response could not be parsed: \(e.localizedDescription)"
        case .rpcFailed(let e): return e.errorDescription
        case .transport(let e): return "Connection error: \(e.localizedDescription)"
        case .serverClosed(let code, let reason):
            return reason.isEmpty
                ? "Server closed the WebSocket (code \(code))."
                : "Server closed the WebSocket: \(reason) (code \(code))."
        }
    }
}

/// JSON-RPC 2.0 client for the TrueNAS Scale WebSocket API at `wss://<host>/api/current`.
/// Waits for the WebSocket open handshake before sending any frames; surfaces close-codes
/// and upgrade failures (e.g. wrong path, TLS error) instead of opaque ENOTCONN errors.
actor TrueNASClient {
    let endpoint: URL
    let webSocketURL: URL
    private let apiKey: String
    private let delegate = WSDelegate()
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var nextId: Int = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var subscribers: [String: [UUID: AsyncStream<JSONValue>.Continuation]] = [:]
    private var openContinuation: CheckedContinuation<Void, Error>?
    private var isOpen = false

    init(endpoint: URL, apiKey: String) throws {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.webSocketURL = try Self.makeWebSocketURL(from: endpoint)
    }

    // MARK: - Connection

    func connect() async throws {
        delegate.onEvent = { [weak self] event in
            Task { await self?.handleDelegate(event: event) }
        }

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let task = session.webSocketTask(with: webSocketURL)
        self.session = session
        self.task = task

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.openContinuation = cont
            task.resume()
        }

        isOpen = true
        startReceiveLoop()
        try await authenticate()
    }

    func disconnect() {
        receiveLoop?.cancel()
        receiveLoop = nil
        delegate.onEvent = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        isOpen = false
        failAll(with: .notConnected, finishStreams: true)
    }

    // MARK: - Public API

    func call<T: Decodable>(_ method: String, params: [Any] = [], as type: T.Type = T.self) async throws -> T {
        let raw = try await callRaw(method: method, params: params)
        do {
            let data = try JSONSerialization.data(withJSONObject: raw.asAny())
            return try JSONDecoder.truenas.decode(T.self, from: data)
        } catch {
            throw TrueNASClientError.decodingFailed(error)
        }
    }

    func callRaw(method: String, params: [Any] = []) async throws -> JSONValue {
        guard isOpen, let task else { throw TrueNASClientError.notConnected }
        let id = nextId
        nextId += 1
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "method": method,
            "params": params
        ]
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw TrueNASClientError.decodingFailed(error)
        }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<JSONValue, Error>) in
            pending[id] = cont
            Task {
                do {
                    try await task.send(.string(String(data: data, encoding: .utf8) ?? ""))
                } catch {
                    self.failPending(id: id, with: .transport(error))
                }
            }
        }
    }

    private func failPending(id: Int, with error: TrueNASClientError) {
        if let cont = pending.removeValue(forKey: id) {
            cont.resume(throwing: error)
        }
    }

    /// `deliveryKey` lets the caller subscribe to a parameterized event name
    /// (e.g. `"app.stats:{\"interval\":5}"`) while receiving notifications under
    /// the canonical collection (`"app.stats"`).
    func subscribe(event: String, deliveryKey: String? = nil) async throws -> AsyncStream<JSONValue> {
        do {
            _ = try await callRaw(method: "core.subscribe", params: [event])
        } catch {
            print("[core.subscribe \(event)] failed: \(error)")
            throw error
        }
        let key = deliveryKey ?? event
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: JSONValue.self)
        subscribers[key, default: [:]][id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(event: key, id: id) }
        }
        return stream
    }

    private func removeSubscriber(event: String, id: UUID) {
        subscribers[event]?.removeValue(forKey: id)
        if subscribers[event]?.isEmpty == true { subscribers.removeValue(forKey: event) }
    }

    // MARK: - Auth

    private func authenticate() async throws {
        let result = try await callRaw(method: "auth.login_with_api_key", params: [apiKey])
        switch result {
        case .bool(true): return
        case .object(let obj) where obj["token"] != nil || obj["response_type"] != nil: return
        case .bool(false):
            throw TrueNASClientError.authenticationFailed("API key was rejected by the server.")
        default:
            return
        }
    }

    // MARK: - Delegate routing

    private func handleDelegate(event: WSDelegate.Event) {
        switch event {
        case .opened:
            if let cont = openContinuation {
                cont.resume()
                openContinuation = nil
            }
        case .closed(let code, let reason):
            let text = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            failAll(with: .serverClosed(code: code.rawValue, reason: text), finishStreams: true)
        case .completed(let error):
            // Some failure modes (TLS error, DNS, HTTP upgrade rejection) come only through here.
            let mapped: TrueNASClientError = error.map { .transport($0) } ?? .notConnected
            failAll(with: mapped, finishStreams: true)
        }
    }

    private func failAll(with error: TrueNASClientError, finishStreams: Bool) {
        isOpen = false
        if let cont = openContinuation {
            cont.resume(throwing: error)
            openContinuation = nil
        }
        for (_, cont) in pending { cont.resume(throwing: error) }
        pending.removeAll()
        if finishStreams {
            for (_, group) in subscribers { for (_, c) in group { c.finish() } }
            subscribers.removeAll()
        }
    }

    // MARK: - Receive loop

    private func startReceiveLoop() {
        receiveLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let shouldContinue = await self.receiveOne()
                if !shouldContinue { return }
            }
        }
    }

    private func receiveOne() async -> Bool {
        guard let task else { return false }
        do {
            let message = try await task.receive()
            handle(message: message)
            return true
        } catch {
            // The delegate will normally beat us to the punch with a clearer cause,
            // but make sure we don't leave pending continuations hanging if it doesn't.
            failAll(with: .transport(error), finishStreams: false)
            return false
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }

        let envelope: JSONRPCEnvelope
        do {
            envelope = try JSONDecoder.truenas.decode(JSONRPCEnvelope.self, from: data)
        } catch {
            return
        }

        if let id = envelope.id, let cont = pending.removeValue(forKey: id) {
            if let error = envelope.error {
                cont.resume(throwing: TrueNASClientError.rpcFailed(error))
            } else {
                cont.resume(returning: envelope.result ?? .null)
            }
            return
        }

        if let method = envelope.method {
            deliverNotification(method: method, params: envelope.params)
        }
    }

    private func deliverNotification(method: String, params: JSONValue?) {
        let collection = params?.objectValue?["collection"]?.stringValue
        let key = collection ?? method
        guard let group = subscribers[key] else { return }
        let payload = params ?? .null
        for (_, c) in group { c.yield(payload) }
    }

    // MARK: - URL construction

    static func makeWebSocketURL(from endpoint: URL) throws -> URL {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw TrueNASClientError.invalidEndpoint
        }
        switch components.scheme?.lowercased() {
        case "https", "wss": components.scheme = "wss"
        case "http", "ws": components.scheme = "ws"
        default: throw TrueNASClientError.invalidEndpoint
        }
        components.path = "/api/current"
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw TrueNASClientError.invalidEndpoint }
        return url
    }
}

// MARK: - URLSession delegate

private final class WSDelegate: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
    enum Event {
        case opened
        case closed(URLSessionWebSocketTask.CloseCode, Data?)
        case completed(Error?)
    }

    var onEvent: ((Event) -> Void)?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onEvent?(.opened)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onEvent?(.closed(closeCode, reason))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onEvent?(.completed(error))
    }
}

// MARK: - JSONValue helpers

extension JSONValue {
    func asAny() -> Any {
        switch self {
        case .null: return NSNull()
        case .bool(let v): return v
        case .int(let v): return v
        case .double(let v): return v
        case .string(let v): return v
        case .array(let v): return v.map { $0.asAny() }
        case .object(let v): return v.mapValues { $0.asAny() }
        }
    }
}

extension JSONDecoder {
    static let truenas: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()
}
