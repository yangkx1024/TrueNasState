import Foundation

enum AuthState: Equatable {
    case loggedOut(error: String?)
    case connecting
    case loggedIn
    case reconnecting

    var isLoggedIn: Bool {
        if case .loggedIn = self { return true }
        return false
    }
}
