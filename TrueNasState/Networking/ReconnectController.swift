import Foundation
import Network

/// Drives reconnect attempts with exponential backoff while watching
/// `NWPathMonitor`. Resets backoff and cancels a pending sleep when the
/// network path transitions to `.satisfied` so we reconnect immediately on
/// Wi-Fi return instead of waiting out the current interval.
@MainActor
final class ReconnectController {
    enum Event {
        case willEnterReconnecting
        case authFailure(Error)
    }

    var attemptConnect: (() async throws -> Void)?
    var onEvent: ((Event) -> Void)?

    private static let backoff: [Duration] = [
        .seconds(2), .seconds(4), .seconds(8), .seconds(16), .seconds(30)
    ]

    private let monitorQueue = DispatchQueue(
        label: "net.yangkx.truestate.pathmonitor", qos: .utility
    )
    private var monitor: NWPathMonitor?
    private var retryTask: Task<Void, Never>?
    private var sleepTask: Task<Void, Never>?
    private var attempt: Int = 0
    private var lastPathSatisfied = false

    func start() {
        guard retryTask == nil else { return }
        startMonitorIfNeeded()
        retryTask = Task { [weak self] in await self?.runLoop() }
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        sleepTask?.cancel()
        sleepTask = nil
        monitor?.cancel()
        monitor = nil
        attempt = 0
        lastPathSatisfied = false
    }

    /// Resets backoff and kicks an immediate attempt. Used when a mid-session
    /// drop is detected so the user doesn't wait out a stale backoff.
    func resetAndRetryNow() {
        attempt = 0
        if retryTask == nil {
            startMonitorIfNeeded()
            retryTask = Task { [weak self] in await self?.runLoop() }
        } else {
            sleepTask?.cancel()
        }
    }

    private func runLoop() async {
        while !Task.isCancelled {
            do {
                try await attemptConnect?()
                attempt = 0
                retryTask = nil
                return
            } catch {
                if Task.isCancelled { return }
                if !isRetriable(error) {
                    onEvent?(.authFailure(error))
                    retryTask = nil
                    return
                }
                if attempt == 0 { onEvent?(.willEnterReconnecting) }
                let delay = Self.backoff[min(attempt, Self.backoff.count - 1)]
                await interruptibleSleep(delay)
                attempt += 1
            }
        }
        retryTask = nil
    }

    private func isRetriable(_ error: Error) -> Bool {
        guard let e = error as? TrueNASClientError else { return true }
        if case .authenticationFailed = e { return false }
        return true
    }

    private func interruptibleSleep(_ duration: Duration) async {
        let task = Task { _ = try? await Task.sleep(for: duration) }
        sleepTask = task
        await task.value
        sleepTask = nil
    }

    private func startMonitorIfNeeded() {
        guard monitor == nil else { return }
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.handlePathUpdate(satisfied: satisfied) }
        }
        m.start(queue: monitorQueue)
        monitor = m
    }

    private func handlePathUpdate(satisfied: Bool) {
        defer { lastPathSatisfied = satisfied }
        guard satisfied, !lastPathSatisfied else { return }
        attempt = 0
        sleepTask?.cancel()
    }
}
