import Foundation
import Testing
@testable import TrueStats

@Suite("app-list refresh gate")
@MainActor
struct AppRefreshGateTests {
    @Test("overlapping requests run serially with one follow-up fetch")
    func coalescesBurst() async {
        let gate = AppRefreshGate()
        let started = AsyncStream<Void>.makeStream()
        var releaseFirst: CheckedContinuation<Void, Never>?
        var runs = 0
        var active = 0
        var maxActive = 0
        var followersEntered = 0

        let refresh: @MainActor () async -> Void = {
            runs += 1
            active += 1
            maxActive = max(maxActive, active)
            if runs == 1 {
                started.continuation.yield()
                await withCheckedContinuation { releaseFirst = $0 }
            }
            active -= 1
        }

        let first = Task { await gate.run(refresh) }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()

        let followers = (0..<5).map { _ in
            Task {
                followersEntered += 1
                await gate.run(refresh)
            }
        }
        while followersEntered < followers.count { await Task.yield() }
        releaseFirst?.resume()

        await first.value
        for follower in followers { await follower.value }
        #expect(runs == 2)
        #expect(maxActive == 1)
    }
}
