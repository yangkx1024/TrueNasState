import Foundation
import Security

struct Credentials: Equatable {
    let endpoint: URL
    let apiKey: String
}

enum CredentialStoreError: Error, LocalizedError {
    case keychainStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .keychainStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            return "Keychain error \(status): \(message)"
        case .invalidData:
            return "Stored credentials are corrupted."
        }
    }
}

/// `@unchecked Sendable`: every stored property is an immutable `let`, and both
/// backing stores it touches — `UserDefaults` and the `SecItem*` Keychain API —
/// are documented as thread-safe. `UserDefaults` itself is explicitly declared
/// non-`Sendable` by Foundation, so the conformance can't be checked.
final class CredentialStore: @unchecked Sendable {
    static let shared = CredentialStore()

    private let service = "net.yangkx.truestate"
    private let endpointDefaultsKey = "truenas.endpoint"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Keychain account for an endpoint. Scheme, host *and port* all take part, so two
    /// TrueNAS instances behind one hostname on different ports no longer overwrite
    /// each other's key — earlier versions keyed on the bare host alone.
    static func account(for endpoint: URL) -> String {
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            return endpoint.absoluteString
        }
        components.stripPathQueryAndFragment()
        components.user = nil
        components.password = nil
        return components.url?.absoluteString ?? endpoint.absoluteString
    }

    func save(_ credentials: Credentials) throws {
        // Pointing the app at a different server used to strand the previous key in
        // the Keychain permanently, since `clear()` only ever saw the current one.
        if let previous = storedEndpoint(), previous != credentials.endpoint {
            deleteKeys(for: previous)
        }
        defaults.set(credentials.endpoint.absoluteString, forKey: endpointDefaultsKey)
        try writeKey(credentials.apiKey, account: Self.account(for: credentials.endpoint))
    }

    func load() -> Credentials? {
        guard let endpoint = storedEndpoint() else { return nil }
        if let key = readKey(account: Self.account(for: endpoint)) {
            return Credentials(endpoint: endpoint, apiKey: key)
        }
        // Adopt a key written by a version that used the bare host as the account, so
        // upgrading doesn't silently sign the user out.
        guard let host = endpoint.host, let legacy = readKey(account: host) else { return nil }
        try? writeKey(legacy, account: Self.account(for: endpoint))
        deleteKey(account: host)
        return Credentials(endpoint: endpoint, apiKey: legacy)
    }

    func clear() {
        if let endpoint = storedEndpoint() {
            deleteKeys(for: endpoint)
        }
        defaults.removeObject(forKey: endpointDefaultsKey)
    }

    private func storedEndpoint() -> URL? {
        defaults.string(forKey: endpointDefaultsKey).flatMap(URL.init(string:))
    }

    private func deleteKeys(for endpoint: URL) {
        deleteKey(account: Self.account(for: endpoint))
        if let host = endpoint.host { deleteKey(account: host) }
    }

    // MARK: - Keychain

    private func writeKey(_ apiKey: String, account: String) throws {
        guard let data = apiKey.data(using: .utf8) else { throw CredentialStoreError.invalidData }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Delete any existing entry first to keep the store idempotent.
        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialStoreError.keychainStatus(status) }
    }

    private func readKey(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKey(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
