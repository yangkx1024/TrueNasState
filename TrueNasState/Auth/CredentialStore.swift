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

final class CredentialStore {
    static let shared = CredentialStore()

    private let service = "net.yangkx.truestate"
    private let endpointDefaultsKey = "truenas.endpoint"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ credentials: Credentials) throws {
        defaults.set(credentials.endpoint.absoluteString, forKey: endpointDefaultsKey)
        try writeKey(credentials.apiKey, account: credentials.endpoint.host ?? credentials.endpoint.absoluteString)
    }

    func load() -> Credentials? {
        guard let urlString = defaults.string(forKey: endpointDefaultsKey),
              let url = URL(string: urlString),
              let account = url.host else {
            return nil
        }
        guard let key = readKey(account: account) else { return nil }
        return Credentials(endpoint: url, apiKey: key)
    }

    func clear() {
        if let urlString = defaults.string(forKey: endpointDefaultsKey),
           let host = URL(string: urlString)?.host {
            deleteKey(account: host)
        }
        defaults.removeObject(forKey: endpointDefaultsKey)
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
