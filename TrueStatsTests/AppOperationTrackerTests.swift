import Foundation
import Testing
@testable import TrueStats

@Suite("in-flight app operations")
@MainActor
struct AppOperationTrackerTests {
    /// Records every completion so tests can assert on notification count, not just
    /// final state.
    private func makeTracker() -> (AppOperationTracker, () -> [String]) {
        let tracker = AppOperationTracker()
        let box = FinishBox()
        tracker.onFinish = { box.finished.append($0) }
        return (tracker, { box.finished })
    }

    @MainActor
    private final class FinishBox {
        var finished: [String] = []
    }

    @Test("tracks upgrade and toggle separately")
    func tracksKinds() {
        let (tracker, _) = makeTracker()
        tracker.beginUpgrade("plex")
        tracker.beginToggle("jellyfin")
        #expect(tracker.isUpgrading("plex"))
        #expect(!tracker.isToggling("plex"))
        #expect(tracker.isToggling("jellyfin"))
        #expect(tracker.isPending("plex") && tracker.isPending("jellyfin"))
        #expect(!tracker.isPending("nextcloud"))
    }

    @Test("a terminal event that lands before the job id is bound still completes it")
    func terminalBeforeBinding() {
        // The exact ordering that used to leave a row spinning: the operation starts,
        // the job finishes while the RPC returning its id is still in flight, and only
        // then is the id known.
        let (tracker, finished) = makeTracker()
        tracker.beginToggle("plex")
        tracker.note(TNJob(id: 42, state: .success))
        #expect(tracker.isPending("plex"))
        #expect(finished().isEmpty)

        tracker.bind(jobID: 42, to: "plex")

        #expect(!tracker.isPending("plex"))
        #expect(finished() == ["plex"])
    }

    @Test("a terminal event after binding completes the operation")
    func terminalAfterBinding() {
        let (tracker, finished) = makeTracker()
        tracker.beginToggle("plex")
        tracker.bind(jobID: 42, to: "plex")
        tracker.note(TNJob(id: 42, state: .success))
        #expect(!tracker.isPending("plex"))
        #expect(finished() == ["plex"])
    }

    @Test("a job that is still running completes nothing", arguments: [TNJobState.waiting, .running])
    func nonTerminalJobIgnored(state: TNJobState) {
        let (tracker, finished) = makeTracker()
        tracker.beginToggle("plex")
        tracker.bind(jobID: 42, to: "plex")
        tracker.note(TNJob(id: 42, state: state))
        #expect(tracker.isPending("plex"))
        #expect(finished().isEmpty)
    }

    @Test("jobs finishing while nothing awaits an id are not remembered")
    func unrelatedJobsAreNotParked() {
        // core.get_jobs carries the whole server's traffic — scrubs, snapshots,
        // replication. Parking those would grow without bound and could complete an
        // unrelated operation that later reuses the id.
        let (tracker, finished) = makeTracker()
        tracker.note(TNJob(id: 99, state: .success))

        tracker.beginToggle("plex")
        tracker.bind(jobID: 99, to: "plex")

        #expect(tracker.isPending("plex"))
        #expect(finished().isEmpty)
    }

    @Test("a parked job is dropped once its operation is cancelled")
    func parkedJobDiscardedAfterCancel() {
        let (tracker, finished) = makeTracker()
        tracker.beginToggle("plex")
        tracker.note(TNJob(id: 42, state: .success))
        tracker.cancel("plex")

        tracker.beginToggle("jellyfin")
        tracker.bind(jobID: 42, to: "jellyfin")

        #expect(tracker.isPending("jellyfin"))
        #expect(finished().isEmpty)
    }

    @Test("a duplicate terminal event notifies only once")
    func finishIsIdempotent() {
        let (tracker, finished) = makeTracker()
        tracker.beginToggle("plex")
        tracker.bind(jobID: 7, to: "plex")
        tracker.note(TNJob(id: 7, state: .success))
        tracker.note(TNJob(id: 7, state: .success))
        #expect(finished() == ["plex"])
    }

    @Test("a terminal event for a job we never started completes nothing")
    func unknownJobIsNoop() {
        let (tracker, finished) = makeTracker()
        tracker.note(TNJob(id: 1234, state: .success))
        #expect(finished().isEmpty)
    }

    @Test("cancel clears state without notifying")
    func cancelDoesNotNotify() {
        let (tracker, finished) = makeTracker()
        tracker.beginUpgrade("plex")
        tracker.bind(jobID: 9, to: "plex")
        tracker.cancel("plex")
        #expect(!tracker.isPending("plex"))
        // The binding is gone too, so a late terminal event can't resurrect it.
        tracker.note(TNJob(id: 9, state: .success))
        #expect(finished().isEmpty)
    }

    @Test("reset drops every operation and binding")
    func resetClearsEverything() {
        let (tracker, finished) = makeTracker()
        tracker.beginUpgrade("plex")
        tracker.beginToggle("jellyfin")
        tracker.bind(jobID: 1, to: "plex")
        tracker.reset()
        #expect(!tracker.isPending("plex"))
        #expect(!tracker.isPending("jellyfin"))
        tracker.note(TNJob(id: 1, state: .success))
        #expect(finished().isEmpty)
    }

    @Test("the watchdog keeps waiting while the server says the job is still running")
    func watchdogDefersToRunningJob() async throws {
        // A slow image pull must not be mistaken for a lost event: clearing here would
        // drop the spinner and let the user fire a second upgrade.
        let (tracker, finished) = makeTracker()
        tracker.watchdogTimeout = .milliseconds(50)
        tracker.jobStateProbe = { _ in .running }
        tracker.beginToggle("plex")
        tracker.bind(jobID: 5, to: "plex")

        try await Task.sleep(for: .milliseconds(400))

        #expect(tracker.isPending("plex"))
        #expect(finished().isEmpty)

        // ...and it still completes normally once the job really does finish.
        tracker.note(TNJob(id: 5, state: .success))
        #expect(finished() == ["plex"])
    }

    @Test("the watchdog clears once the server reports the job finished")
    func watchdogClearsFinishedJob() async throws {
        let (tracker, finished) = makeTracker()
        tracker.watchdogTimeout = .milliseconds(50)
        tracker.jobStateProbe = { _ in .success }
        tracker.beginToggle("plex")
        tracker.bind(jobID: 5, to: "plex")

        try await Task.sleep(for: .milliseconds(400))

        #expect(!tracker.isPending("plex"))
        #expect(finished() == ["plex"])
    }

    @Test("the watchdog clears when the server no longer knows the job")
    func watchdogClearsUnknownJob() async throws {
        let (tracker, finished) = makeTracker()
        tracker.watchdogTimeout = .milliseconds(50)
        tracker.jobStateProbe = { _ in nil }
        tracker.beginToggle("plex")
        tracker.bind(jobID: 5, to: "plex")

        try await Task.sleep(for: .milliseconds(400))

        #expect(finished() == ["plex"])
    }

    @Test("a probe that fails keeps the operation rather than guessing")
    func watchdogKeepsWaitingWhenProbeFails() async throws {
        struct ProbeFailure: Error {}
        let (tracker, finished) = makeTracker()
        tracker.watchdogTimeout = .milliseconds(50)
        tracker.jobStateProbe = { _ in throw ProbeFailure() }
        tracker.beginToggle("plex")
        tracker.bind(jobID: 5, to: "plex")

        try await Task.sleep(for: .milliseconds(400))

        #expect(tracker.isPending("plex"))
        #expect(finished().isEmpty)
    }

    @Test("the watchdog clears an operation whose terminal event never arrives")
    func watchdogFires() async throws {
        let (tracker, finished) = makeTracker()
        tracker.watchdogTimeout = .milliseconds(50)
        tracker.beginToggle("plex")
        #expect(tracker.isPending("plex"))

        try await Task.sleep(for: .milliseconds(400))

        #expect(!tracker.isPending("plex"))
        #expect(finished() == ["plex"])
    }

    @Test("completing in time cancels the watchdog")
    func watchdogCancelledOnCompletion() async throws {
        let (tracker, finished) = makeTracker()
        tracker.watchdogTimeout = .milliseconds(50)
        tracker.beginToggle("plex")
        tracker.bind(jobID: 3, to: "plex")
        tracker.note(TNJob(id: 3, state: .success))

        try await Task.sleep(for: .milliseconds(400))

        // Exactly one completion: the watchdog must not fire a second one.
        #expect(finished() == ["plex"])
    }
}

@Suite("demo mode data")
struct DemoDataTests {
    @Test("the snapshot is populated enough to show every screen")
    func snapshotIsPopulated() {
        let demo = DemoMode.snapshot()
        #expect(!demo.pools.isEmpty)
        #expect(!demo.apps.isEmpty)
        #expect(!demo.alerts.isEmpty)
        #expect(demo.apps.contains { $0.hasUpgrade })
        #expect(demo.apps.contains { $0.state == .stopped })
        #expect(demo.systemInfo.hostname != nil)
    }

    @Test("the fake realtime walk stays inside plausible bounds")
    func statsWalkStaysBounded() {
        var stats = DemoMode.snapshot().stats
        for _ in 0..<500 {
            stats = DemoMode.nextStats(after: stats)
            let cpu = stats.cpuUsagePercent ?? -1
            #expect(cpu >= 2 && cpu <= 85)
            let used = stats.memoryUsedBytes ?? -1
            let total = stats.memoryTotalBytes ?? 0
            #expect(used >= 0 && used <= total)
        }
    }

    @Test("the walk keeps total memory fixed and starts from nothing")
    func statsWalkFromNil() throws {
        let first = DemoMode.nextStats(after: nil)
        let total: Int64 = try #require(first.memoryTotalBytes)
        #expect(total == Int64(32) * 1024 * 1024 * 1024)
        #expect(DemoMode.nextStats(after: first).memoryTotalBytes == total)
    }
}
