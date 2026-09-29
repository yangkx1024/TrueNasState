/// Runs app-list fetches one at a time. Requests made during a fetch are
/// coalesced into one follow-up fetch, so the latest server state wins.
@MainActor
final class AppRefreshGate {
    private var task: Task<Void, Never>?
    private var rerunRequested = false

    func run(_ refresh: @escaping @MainActor () async -> Void) async {
        if let task {
            rerunRequested = true
            await task.value
            return
        }

        let task = Task {
            repeat {
                rerunRequested = false
                await refresh()
            } while rerunRequested
            self.task = nil
        }
        self.task = task
        await task.value
    }
}
