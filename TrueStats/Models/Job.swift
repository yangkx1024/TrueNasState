import Foundation

enum TNJobState: String, Equatable {
    case waiting = "WAITING"
    case running = "RUNNING"
    case success = "SUCCESS"
    case failed  = "FAILED"
    case aborted = "ABORTED"

    /// The job has stopped moving, however it ended.
    var isTerminal: Bool {
        switch self {
        case .success, .failed, .aborted: return true
        case .waiting, .running: return false
        }
    }
}

struct TNJob: Equatable {
    let id: Int
    let state: TNJobState?

    /// A state we don't recognize is treated as still running, so an unknown value
    /// can't silently complete an operation.
    var isTerminal: Bool { state?.isTerminal == true }
}
