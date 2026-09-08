import ServiceManagement

enum LoginItemError: Error, LocalizedError {
    /// `SMAppService.register()` succeeds without throwing when macOS still wants
    /// the user to approve the item, leaving the service disabled. Surfacing this
    /// is the difference between a toggle that silently snaps back and one that
    /// tells the user where to go.
    case requiresApproval

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return String(localized: "Allow TrueStats in System Settings → General → Login Items.")
        }
    }
}

@MainActor
enum LoginItemController {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Throws so the caller can surface the failure instead of leaving the UI lying
    /// about the real state.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            guard SMAppService.mainApp.status != .enabled else { return }
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                throw LoginItemError.requiresApproval
            }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}
