import Foundation

extension URLComponents {
    /// Reduces a URL to the server it names — scheme, host and port — by dropping the
    /// path, query and fragment.
    ///
    /// Endpoints are typed by hand, so they turn up with trailing slashes,
    /// `/ui/dashboard` and query strings attached. Three call sites needed this
    /// independently: normalizing login input, deriving the WebSocket URL, and keying
    /// the Keychain entry.
    mutating func stripPathQueryAndFragment() {
        path = ""
        query = nil
        fragment = nil
    }
}
