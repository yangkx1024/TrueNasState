import Foundation

extension AppState {
    var displayName: String {
        switch self {
        case .running: return String(localized: "Running")
        case .stopped: return String(localized: "Stopped")
        case .deploying: return String(localized: "Deploying")
        case .stopping: return String(localized: "Stopping")
        case .crashed: return String(localized: "Crashed")
        }
    }
}
