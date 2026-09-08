import Foundation
import Observation

/// Bookkeeping for in-flight `app.start` / `app.stop` / `app.upgrade` operations.
///
/// TrueNAS reports completion through a `core.get_jobs` event keyed by job id, but the
/// id only comes back from the RPC that started the work — so a fast operation's
/// terminal event can arrive before there is anything to match it against. This type
/// resolves that ordering itself, by parking a terminal job id until `bind` claims it,
/// so no caller has to poll the job back to compensate.
@MainActor
@Observable
final class AppOperationTracker {
    /// Backstop for a terminal job event that never arrives at all (a frame dropped on
    /// a still-live subscription). Without it the optimistic state would be pinned
    /// until the next reconnect. Settable so tests don't have to wait two minutes.
    var watchdogTimeout: Duration = .seconds(120)

    /// Called on the main actor whenever an operation ends, however it ended.
    var onFinish: ((String) -> Void)?

    private(set) var upgrading: Set<String> = []
    private(set) var toggling: Set<String> = []
    private var jobIDToAppID: [Int: String] = [:]
    private var watchdogs: [String: Task<Void, Never>] = [:]

    /// Operations that have started but whose job id hasn't come back yet.
    private var awaitingBinding: Set<String> = []
    /// Jobs that reported a terminal state before anything was bound to them. Only
    /// populated while `awaitingBinding` is non-empty — otherwise every job on the
    /// server (scrubs, snapshots, replication) would accumulate here.
    private var terminalBeforeBinding: Set<Int> = []

    func isUpgrading(_ appID: String) -> Bool { upgrading.contains(appID) }
    func isToggling(_ appID: String) -> Bool { toggling.contains(appID) }
    func isPending(_ appID: String) -> Bool { isUpgrading(appID) || isToggling(appID) }

    func beginUpgrade(_ appID: String) {
        upgrading.insert(appID)
        awaitingBinding.insert(appID)
        startWatchdog(for: appID)
    }

    func beginToggle(_ appID: String) {
        toggling.insert(appID)
        awaitingBinding.insert(appID)
        startWatchdog(for: appID)
    }

    /// Ties the job the server just handed back to the app it belongs to.
    ///
    /// If that job already reported a terminal state while we were still waiting for
    /// its id — what a fast `app.stop` does — the operation completes right here rather
    /// than waiting for an event that has already been and gone.
    func bind(jobID: Int, to appID: String) {
        awaitingBinding.remove(appID)
        let alreadyFinished = terminalBeforeBinding.remove(jobID) != nil
        if !alreadyFinished { jobIDToAppID[jobID] = appID }
        discardParkedJobsIfIdle()
        if alreadyFinished { finish(appID) }
    }

    /// Every `core.get_jobs` event goes through here, whether or not it belongs to us.
    func note(_ job: TNJob) {
        guard job.isTerminal else { return }
        if let appID = jobIDToAppID[job.id] {
            finish(appID)
        } else if !awaitingBinding.isEmpty {
            terminalBeforeBinding.insert(job.id)
        }
    }

    /// Forgets `appID` without notifying — for when the RPC itself failed and the
    /// caller is rolling its own state back.
    func cancel(_ appID: String) {
        upgrading.remove(appID)
        toggling.remove(appID)
        awaitingBinding.remove(appID)
        watchdogs.removeValue(forKey: appID)?.cancel()
        jobIDToAppID = jobIDToAppID.filter { $0.value != appID }
        discardParkedJobsIfIdle()
    }

    /// Completes `appID` and notifies. A second terminal event for the same app is a
    /// no-op, so `bind`, `note` and the watchdog can all route through here.
    private func finish(_ appID: String) {
        guard isPending(appID) else { return }
        cancel(appID)
        onFinish?(appID)
    }

    /// Drops everything. A reconnect must not leak bindings whose terminal events were
    /// swallowed along with the dropped subscription.
    func reset() {
        upgrading = []
        toggling = []
        jobIDToAppID = [:]
        awaitingBinding = []
        terminalBeforeBinding = []
        for (_, watchdog) in watchdogs { watchdog.cancel() }
        watchdogs.removeAll()
    }

    /// Nothing is waiting for an id, so any parked job belongs to no operation of ours.
    private func discardParkedJobsIfIdle() {
        if awaitingBinding.isEmpty { terminalBeforeBinding.removeAll() }
    }

    private func startWatchdog(for appID: String) {
        watchdogs[appID]?.cancel()
        let timeout = watchdogTimeout
        watchdogs[appID] = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled, let self, isPending(appID) else { return }
            Log.dashboard.warning(
                "job for \(appID, privacy: .public) never reported a terminal state; clearing")
            finish(appID)
        }
    }
}
