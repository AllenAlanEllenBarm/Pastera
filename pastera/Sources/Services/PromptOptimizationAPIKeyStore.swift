import Foundation
import Security

protocol PromptOptimizationAPIKeyStoring: AnyObject {
    var containsAPIKey: Bool { get }

    func save(_ apiKey: String) throws
    func load() throws -> String?
    func delete() throws
}

protocol PromptOptimizationKeychainAccessing: AnyObject {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

final class SystemPromptOptimizationKeychainAccess: PromptOptimizationKeychainAccessing {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

final class PromptOptimizationAPIKeyStore: PromptOptimizationAPIKeyStoring {
    static let service = "com.pastera-app.Pastera.prompt-optimization.v1"
    static let account = "PasteraPromptOptimizationAPIKey"

    private let keychain: PromptOptimizationKeychainAccessing
    private let usesDataProtectionKeychain: Bool

    init(
        keychain: PromptOptimizationKeychainAccessing = SystemPromptOptimizationKeychainAccess(),
        usesDataProtectionKeychain: Bool =
            VaultAgentKeychainBackend.currentProcessUsesDataProtectionKeychain
    ) {
        self.keychain = keychain
        self.usesDataProtectionKeychain = usesDataProtectionKeychain
    }

    var containsAPIKey: Bool {
        keychain.copyMatching(availabilityQuery).0 == errSecSuccess
    }

    func save(_ apiKey: String) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: Data(apiKey.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        switch keychain.update(itemQuery, attributes: attributes) {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = itemQuery
            attributes.forEach { addQuery[$0.key] = $0.value }
            guard keychain.add(addQuery) == errSecSuccess else {
                throw PromptOptimizationError.keychainUnavailable
            }
        default:
            throw PromptOptimizationError.keychainUnavailable
        }
    }

    func load() throws -> String? {
        let (status, result) = keychain.copyMatching(loadQuery)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8),
              !apiKey.isEmpty else {
            throw PromptOptimizationError.keychainUnavailable
        }
        return apiKey
    }

    func delete() throws {
        let status = keychain.delete(itemQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PromptOptimizationError.keychainUnavailable
        }
    }

    private var itemQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false
        ]
        VaultAgentKeychainBackend.configure(
            &query,
            usesDataProtectionKeychain: usesDataProtectionKeychain
        )
        return query
    }

    private var availabilityQuery: [String: Any] {
        var query = itemQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private var loadQuery: [String: Any] {
        var query = availabilityQuery
        query[kSecReturnData as String] = true
        return query
    }
}
