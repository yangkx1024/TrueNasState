import Foundation

enum TNJobState: String, Equatable {
    case waiting = "WAITING"
    case running = "RUNNING"
    case success = "SUCCESS"
    case failed  = "FAILED"
    case aborted = "ABORTED"
}

struct TNJob: Equatable {
    let id: Int
    let state: TNJobState?

    var isTerminal: Bool {
        switch state {
        case .success, .failed, .aborted: return true
        default: return false
        }
    }
}
