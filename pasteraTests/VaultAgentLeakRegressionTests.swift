import AppKit
import Foundation
import PasteraAgentProtocol
import Security
import Testing

@testable import Pastera

@Suite("Vault agent leak regression", .serialized)
struct VaultAgentLeakRegressionTests {
    @Test("audit and stable app errors never encode the raw sentinel")
    func auditAndErrorsOmitSentinel() throws {
        let sentinelID = UUID()
        let sentinel = sentinelID.uuidString
        let keyStore = VaultAgentAuditKeyStore(
            keychain: LeakAuditKeychain(key: Data(repeating: 0xA5, count: 32)),
            usesDataProtectionKeychain: false
        )
        let logger = try VaultAgentAuditLogger(keyStore: keyStore)

        logger.record(
            client: .codex,
            action: .paste,
            entryID: sentinelID,
            result: .brokerUnavailable,
            latencyBucket: .under50ms,
            at: Date(timeIntervalSince1970: 1)
        )

        let encodedAudit = try JSONEncoder().encode(logger.records(at: Date(timeIntervalSince1970: 2)))
        let errorDescriptions = VaultAgentErrorCode.allCases.flatMap {
            [String(describing: $0), String(reflecting: $0), $0.localizedDescription]
        }
        #expect(!encodedAudit.contains(Data(sentinel.utf8)))
        #expect(errorDescriptions.allSatisfy { !$0.contains(sentinel) })
    }

    @Test("secure clipboard is the explicit temporary exception and clears after 60 seconds")
    func secureClipboardBoundaryIsTemporary() throws {
        let sentinel = "PASTERA-CLIPBOARD-\(UUID().uuidString)"
        let pasteboard = LeakSecretPasteboard()
        var scheduledDuration: Duration?
        var scheduledAction: (() -> Void)?
        let service = SecureClipboardService(
            pasteboard: pasteboard,
            suppressHistoryChange: { _ in },
            schedule: {
                scheduledDuration = $0
                scheduledAction = $1
            }
        )

        service.copySecret(sentinel, clearAfter: .seconds(60))

        #expect(pasteboard.string == sentinel)
        #expect(scheduledDuration == .seconds(60))
        #expect(!(NSPasteboard.general.string(forType: .string) ?? "").contains(sentinel))
        let clear = try #require(scheduledAction)
        clear()
        #expect(pasteboard.string == nil)
    }
}

private final class LeakAuditKeychain: VaultAgentAuditKeychainAccessing {
    private let key: Data

    init(key: Data) { self.key = key }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        (errSecSuccess, key)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        errSecSuccess
    }

    func add(_ query: [String: Any]) -> OSStatus { errSecSuccess }
}

private final class LeakSecretPasteboard: SecretPasteboard {
    private(set) var changeCount = 0
    private(set) var string: String?

    func writeSecret(_ value: String) {
        string = value
        changeCount += 1
    }

    func clear() {
        string = nil
        changeCount += 1
    }
}
