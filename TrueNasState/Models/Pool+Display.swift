import Foundation

extension Pool {
    var localizedStatus: String {
        switch displayStatus.uppercased() {
        case "ONLINE": return String(localized: "Online")
        case "DEGRADED": return String(localized: "Degraded")
        case "OFFLINE": return String(localized: "Offline")
        case "UNKNOWN": return String(localized: "Unknown")
        default: return displayStatus
        }
    }
}
