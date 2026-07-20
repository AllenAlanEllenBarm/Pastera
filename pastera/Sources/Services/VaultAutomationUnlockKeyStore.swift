import Foundation
import Security

protocol VaultAutomationUnlockKeyStoring {
    var containsKey: Bool { get }

    func save(_ data: Data) throws
    func load() throws -> Data
    func delete() throws
}

protocol VaultAutomationKeychainAccessing {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

final class SystemVaultAutomationKeychainAccess: VaultAutomationKeychainAccessing {
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

final class VaultAutomationUnlockKeyStore: VaultAutomationUnlockKeyStoring {
    static let service = "com.pastera-app.Pastera.password-vault.agent-unlock.v1"
    static let account = "PasteraVaultAgentUnlock"

    private let client: VaultAutomationKeychainAccessing
    private let usesDataProtectionKeychain: Bool

    init(
        client: VaultAutomationKeychainAccessing = SystemVaultAutomationKeychainAccess(),
        usesDataProtectionKeychain: Bool =
            VaultAgentKeychainBackend.currentProcessUsesDataProtectionKeychain
    ) {
        self.client = client
        self.usesDataProtectionKeychain = usesDataProtectionKeychain
    }

    var containsKey: Bool {
        client.copyMatching(availabilityQuery).0 == errSecSuccess
    }

    func save(_ data: Data) throws {
        guard data.count == 32 else { throw PasswordVaultError.keychainUnavailable }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        switch client.update(itemQuery, attributes: attributes) {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = itemQuery
            attributes.forEach { addQuery[$0.key] = $0.value }
            guard client.add(addQuery) == errSecSuccess else {
                throw PasswordVaultError.keychainUnavailable
            }
        default:
            throw PasswordVaultError.keychainUnavailable
        }
    }

    func load() throws -> Data {
        let (status, result) = client.copyMatching(loadQuery)
        guard status == errSecSuccess,
              let data = result as? Data,
              data.count == 32 else {
            throw PasswordVaultError.keychainUnavailable
        }
        return data
    }

    func delete() throws {
        let status = client.delete(itemQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PasswordVaultError.keychainUnavailable
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
