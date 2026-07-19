import CryptoKit
import Foundation
import PasteraAgentProtocol
import Security

enum VaultAgentAuditAction: String, Codable, CaseIterable {
    case status
    case search
    case get
    case paste
    case copy
    case prepareExec
    case redeemTicket
    case completeTicket
    case integrationStatus
    case integrationInstall
    case integrationUninstall
}

enum VaultAgentLatencyBucket: String, Codable, CaseIterable {
    case under10ms
    case under50ms
    case under200ms
    case under1s
    case atLeast1s
}

struct VaultAgentAuditRecord: Codable, Equatable {
    let client: VaultAgentClientKind
    let action: VaultAgentAuditAction
    let entryDigest: String?
    let result: VaultAgentErrorCode?
    let latencyBucket: VaultAgentLatencyBucket
    let timestamp: Date
}

protocol VaultAgentAuditKeychainAccessing {
    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?)
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(_ query: [String: Any]) -> OSStatus
}

final class SystemVaultAgentAuditKeychainAccess: VaultAgentAuditKeychainAccessing {
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

enum VaultAgentAuditKeyStoreError: Error, Equatable {
    case unavailable
}

final class VaultAgentAuditKeyStore {
    static let service = "com.pastera-app.Pastera.password-vault.agent-audit.v1"
    static let account = "PasteraVaultAgentAuditKey"

    private static let creationLock = NSLock()
    private let keychain: VaultAgentAuditKeychainAccessing
    private let randomBytes: () throws -> Data

    init(
        keychain: VaultAgentAuditKeychainAccessing = SystemVaultAgentAuditKeychainAccess(),
        randomBytes: @escaping () throws -> Data = VaultAgentAuditKeyStore.secureRandomBytes
    ) {
        self.keychain = keychain
        self.randomBytes = randomBytes
    }

    func loadOrCreate() throws -> Data {
        Self.creationLock.lock()
        defer { Self.creationLock.unlock() }

        let (readStatus, existing) = keychain.copyMatching(Self.loadQuery)
        if readStatus == errSecSuccess {
            return try Self.requireKey(existing)
        }
        guard readStatus == errSecItemNotFound else {
            throw VaultAgentAuditKeyStoreError.unavailable
        }

        let generated: Data
        do {
            generated = try randomBytes()
        } catch {
            throw VaultAgentAuditKeyStoreError.unavailable
        }
        guard generated.count == 32 else {
            throw VaultAgentAuditKeyStoreError.unavailable
        }

        let secureAttributes: [String: Any] = [kSecValueData as String: generated]
        switch keychain.update(Self.itemQuery, attributes: secureAttributes) {
        case errSecSuccess:
            return generated
        case errSecItemNotFound:
            var addQuery = Self.itemQuery
            secureAttributes.forEach { addQuery[$0.key] = $0.value }
            switch keychain.add(addQuery) {
            case errSecSuccess:
                return generated
            case errSecDuplicateItem:
                let (retryStatus, established) = keychain.copyMatching(Self.loadQuery)
                guard retryStatus == errSecSuccess else {
                    throw VaultAgentAuditKeyStoreError.unavailable
                }
                return try Self.requireKey(established)
            default:
                throw VaultAgentAuditKeyStoreError.unavailable
            }
        default:
            throw VaultAgentAuditKeyStoreError.unavailable
        }
    }

    private static var itemQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
    }

    private static var loadQuery: [String: Any] {
        var query = itemQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private static func requireKey(_ data: Data?) throws -> Data {
        guard let data, data.count == 32 else {
            throw VaultAgentAuditKeyStoreError.unavailable
        }
        return data
    }

    private static func secureRandomBytes() throws -> Data {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, address)
        }
        guard status == errSecSuccess else {
            throw VaultAgentAuditKeyStoreError.unavailable
        }
        return bytes
    }
}

final class VaultAgentAuditLogger {
    private static let capacity = 1_000
    private static let retention: TimeInterval = 30 * 24 * 60 * 60

    private let lock = NSLock()
    private let key: SymmetricKey
    private var ring = [VaultAgentAuditRecord]()

    init(keyStore: VaultAgentAuditKeyStore = VaultAgentAuditKeyStore()) throws {
        key = SymmetricKey(data: try keyStore.loadOrCreate())
    }

    // The explicit fields are the audit schema allowlist; do not replace with a free-form payload.
    // swiftlint:disable:next function_parameter_count
    func record(
        client: VaultAgentClientKind,
        action: VaultAgentAuditAction,
        entryID: UUID?,
        result: VaultAgentErrorCode?,
        latencyBucket: VaultAgentLatencyBucket,
        at date: Date
    ) {
        let entryDigest = entryID.map(digest)
        let record = VaultAgentAuditRecord(
            client: client,
            action: action,
            entryDigest: entryDigest,
            result: result,
            latencyBucket: latencyBucket,
            timestamp: date
        )

        lock.lock()
        removeExpiredLocked(at: date)
        ring.append(record)
        removeExpiredLocked(at: date)
        if ring.count > Self.capacity {
            ring.removeFirst(ring.count - Self.capacity)
        }
        lock.unlock()
    }

    func records(at now: Date) -> [VaultAgentAuditRecord] {
        lock.lock()
        defer { lock.unlock() }
        removeExpiredLocked(at: now)
        return ring
    }

    private func digest(entryID: UUID) -> String {
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: Data(entryID.uuidString.utf8),
            using: key
        )
        return Data(authenticationCode).base64URLEncodedWithoutPadding
    }

    private func removeExpiredLocked(at now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        ring.removeAll { $0.timestamp <= cutoff }
    }
}

private extension Data {
    var base64URLEncodedWithoutPadding: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
