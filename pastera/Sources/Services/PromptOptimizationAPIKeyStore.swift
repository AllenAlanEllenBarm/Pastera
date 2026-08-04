import Foundation
import Security

protocol PromptOptimizationAPIKeyStoring: AnyObject {
    func containsAPIKey(for profileID: UUID) -> Bool
    func save(_ apiKey: String, for profileID: UUID) throws
    func load(for profileID: UUID) throws -> String?
    func delete(for profileID: UUID) throws
    func migrateLegacyAPIKeyIfNeeded(to profileID: UUID) throws
}

extension PromptOptimizationSettingsStoring {
    func migrateLegacyAPIKeyIfNeeded(
        using apiKeyStore: any PromptOptimizationAPIKeyStoring
    ) throws {
        guard let profileID = pendingLegacyCredentialProfileID else { return }
        try apiKeyStore.migrateLegacyAPIKeyIfNeeded(to: profileID)
        completeLegacyCredentialMigration(for: profileID)
    }
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
    static let legacyAccount = "PasteraPromptOptimizationAPIKey"

    static func account(for profileID: UUID) -> String {
        "PasteraPromptOptimizationAPIKey.\(profileID.uuidString.lowercased())"
    }

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

    func containsAPIKey(for profileID: UUID) -> Bool {
        keychain.copyMatching(availabilityQuery(for: profileID)).0 == errSecSuccess
    }

    func save(_ apiKey: String, for profileID: UUID) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let attributes = credentialAttributes(for: apiKey)
        let itemQuery = itemQuery(for: profileID)
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

    func load(for profileID: UUID) throws -> String? {
        let (status, result) = keychain.copyMatching(loadQuery(for: profileID))
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

    func delete(for profileID: UUID) throws {
        let status = keychain.delete(itemQuery(for: profileID))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PromptOptimizationError.keychainUnavailable
        }
    }

    func migrateLegacyAPIKeyIfNeeded(to profileID: UUID) throws {
        guard let legacyAPIKey = try loadLegacyAPIKey() else { return }
        var attributes = itemQuery(for: profileID)
        credentialAttributes(for: legacyAPIKey).forEach { attributes[$0.key] = $0.value }
        switch keychain.add(attributes) {
        case errSecSuccess, errSecDuplicateItem:
            try deleteLegacyAPIKey()
        default:
            throw PromptOptimizationError.keychainUnavailable
        }
    }

    private func itemQuery(for profileID: UUID) -> [String: Any] {
        itemQuery(account: Self.account(for: profileID))
    }

    private func legacyItemQuery() -> [String: Any] {
        itemQuery(account: Self.legacyAccount)
    }

    private func itemQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
        VaultAgentKeychainBackend.configure(
            &query,
            usesDataProtectionKeychain: usesDataProtectionKeychain
        )
        return query
    }

    private func credentialAttributes(for apiKey: String) -> [String: Any] {
        [
            kSecValueData as String: Data(apiKey.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }

    private func availabilityQuery(for profileID: UUID) -> [String: Any] {
        var query = itemQuery(for: profileID)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private func loadQuery(for profileID: UUID) -> [String: Any] {
        var query = availabilityQuery(for: profileID)
        query[kSecReturnData as String] = true
        return query
    }

    private func loadLegacyAPIKey() throws -> String? {
        let (status, result) = keychain.copyMatching(legacyLoadQuery)
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

    private func deleteLegacyAPIKey() throws {
        let status = keychain.delete(legacyItemQuery())
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PromptOptimizationError.keychainUnavailable
        }
    }

    private var legacyLoadQuery: [String: Any] {
        var query = legacyItemQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        return query
    }
}
