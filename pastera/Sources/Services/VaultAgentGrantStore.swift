import Foundation
import PasteraAgentProtocol
import Security

protocol VaultAgentKeychainAccessing {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ query: [String: Any]) -> OSStatus
}

final class VaultAgentGrantStore: VaultAgentGrantStoring {
    static let service = "com.pastera-app.Pastera.agent-grants.v1"
    private static let account = "grants"

    private let keychain: VaultAgentKeychainAccessing
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(keychain: VaultAgentKeychainAccessing = SystemVaultAgentKeychainAccess()) {
        self.keychain = keychain
    }

    func load() throws -> [VaultAgentClientKind: VaultAgentGrant] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = keychain.copyMatching(query)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data else {
            throw VaultAgentErrorCode.automationUnlockUnavailable
        }
        do {
            return try decoder.decode([VaultAgentClientKind: VaultAgentGrant].self, from: data)
        } catch {
            throw VaultAgentErrorCode.automationUnlockUnavailable
        }
    }

    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) throws {
        let data: Data
        do {
            data = try encoder.encode(grants)
        } catch {
            throw VaultAgentErrorCode.automationUnlockUnavailable
        }
        let attributes = [kSecValueData as String: data]
        let updateStatus = keychain.update(baseQuery, attributes: attributes)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw VaultAgentErrorCode.automationUnlockUnavailable
        }
        var addQuery = baseQuery
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecValueData as String] = data
        guard keychain.add(addQuery) == errSecSuccess else {
            throw VaultAgentErrorCode.automationUnlockUnavailable
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

final class SystemVaultAgentKeychainAccess: VaultAgentKeychainAccessing {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(_ query: [String: Any]) -> OSStatus {
        SecItemAdd(query as CFDictionary, nil)
    }
}
