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

    init(client: VaultAutomationKeychainAccessing = SystemVaultAutomationKeychainAccess()) {
        self.client = client
    }

    var containsKey: Bool {
        client.copyMatching(Self.availabilityQuery).0 == errSecSuccess
    }

    func save(_ data: Data) throws {
        guard data.count == 32 else { throw PasswordVaultError.keychainUnavailable }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        switch client.update(Self.itemQuery, attributes: attributes) {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = Self.itemQuery
            attributes.forEach { addQuery[$0.key] = $0.value }
            guard client.add(addQuery) == errSecSuccess else {
                throw PasswordVaultError.keychainUnavailable
            }
        default:
            throw PasswordVaultError.keychainUnavailable
        }
    }

    func load() throws -> Data {
        let (status, result) = client.copyMatching(Self.loadQuery)
        guard status == errSecSuccess,
              let data = result as? Data,
              data.count == 32 else {
            throw PasswordVaultError.keychainUnavailable
        }
        return data
    }

    func delete() throws {
        let status = client.delete(Self.itemQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PasswordVaultError.keychainUnavailable
        }
    }

    private static var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }

    private static var availabilityQuery: [String: Any] {
        var query = itemQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private static var loadQuery: [String: Any] {
        var query = availabilityQuery
        query[kSecReturnData as String] = true
        return query
    }
}
