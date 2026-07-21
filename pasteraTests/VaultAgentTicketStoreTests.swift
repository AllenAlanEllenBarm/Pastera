import CryptoKit
import Foundation
import PasteraAgentProtocol
import Security
import Testing
@testable import Pastera

@Suite("Vault agent tickets, rate limits, and audit", .serialized)
struct VaultAgentTicketStoreTests {
    private let base = Date(timeIntervalSince1970: 10_000)

    @Test("only one concurrent redeemer receives a receipt")
    func ticketCanBeRedeemedOnce() throws {
        let store = makeTicketStore(bytes: Data(repeating: 7, count: 32))
        let issued = try store.issue(
            client: .codex,
            entryID: UUID(),
            field: .password,
            mode: .stdin,
            now: base
        )
        let outcomes = LockedArray<Result<UUID, Error>>()

        DispatchQueue.concurrentPerform(iterations: 2) { _ in
            let result = Result {
                try store.redeem(
                    token: issued.token,
                    client: .codex,
                    mode: .stdin,
                    now: base.addingTimeInterval(1)
                ).receiptID
            }
            outcomes.append(result)
        }

        let values = outcomes.values
        #expect(values.compactMap { try? $0.get() }.count == 1)
        #expect(values.compactMap { result -> VaultAgentTicketError? in
            guard case let .failure(error) = result else { return nil }
            return error as? VaultAgentTicketError
        } == [.used])
    }

    @Test("wrong client and mode never consume a valid ticket")
    func bindingMismatchDoesNotConsume() throws {
        let store = makeTicketStore(bytes: Data(repeating: 8, count: 32))
        let entryID = UUID()
        let issued = try store.issue(
            client: .codex,
            entryID: entryID,
            field: .username,
            mode: .fileDescriptor,
            now: base
        )

        #expect(throws: VaultAgentTicketError.bindingMismatch) {
            try store.redeem(token: issued.token, client: .claude, mode: .fileDescriptor, now: base)
        }
        #expect(throws: VaultAgentTicketError.bindingMismatch) {
            try store.redeem(token: issued.token, client: .codex, mode: .stdin, now: base)
        }

        let redeemed = try store.redeem(
            token: issued.token,
            client: .codex,
            mode: .fileDescriptor,
            now: base
        )
        #expect(redeemed.binding == VaultAgentTicketBinding(
            client: .codex,
            entryID: entryID,
            field: .username,
            mode: .fileDescriptor
        ))
    }

    @Test("ticket and receipt expiration use exclusive upper boundaries")
    func expirationBoundaries() throws {
        let sequence = TicketRandomSequence()
        let store = makeTicketStore(randomBytes: sequence.next)
        let expired = try store.issue(
            client: .cli,
            entryID: UUID(),
            field: .password,
            mode: .stdin,
            now: base
        )
        #expect(throws: VaultAgentTicketError.expired) {
            try store.redeem(
                token: expired.token,
                client: .cli,
                mode: .stdin,
                now: base.addingTimeInterval(VaultAgentTicketStore.ticketLifetime)
            )
        }

        let valid = try store.issue(
            client: .cli,
            entryID: UUID(),
            field: .password,
            mode: .stdin,
            now: base
        )
        let receipt = try store.redeem(
            token: valid.token,
            client: .cli,
            mode: .stdin,
            now: base.addingTimeInterval(VaultAgentTicketStore.ticketLifetime - 0.001)
        )
        #expect(throws: VaultAgentTicketError.expired) {
            try store.complete(
                receiptID: receipt.receiptID,
                client: .cli,
                now: base.addingTimeInterval(VaultAgentTicketStore.ticketLifetime - 0.001 + VaultAgentTicketStore.receiptLifetime)
            )
        }
    }

    @Test("lazy cleanup preserves expired ticket and receipt outcomes")
    func lazyCleanupPreservesExpiredOutcomes() throws {
        let sequence = TicketRandomSequence()
        let store = makeTicketStore(randomBytes: sequence.next)
        let ticket = try issueOne(store, at: base)
        let receiptTicket = try issueOne(store, at: base)
        let receipt = try store.redeem(
            token: receiptTicket.token,
            client: .codex,
            mode: .stdin,
            now: base
        )

        _ = try issueOne(store, at: base.addingTimeInterval(31))

        for _ in 0..<2 {
            #expect(throws: VaultAgentTicketError.expired) {
                try store.redeem(
                    token: ticket.token,
                    client: .codex,
                    mode: .stdin,
                    now: base.addingTimeInterval(31)
                )
            }
            #expect(throws: VaultAgentTicketError.expired) {
                try store.complete(
                    receiptID: receipt.receiptID,
                    client: .codex,
                    now: base.addingTimeInterval(31)
                )
            }
        }
    }

    @Test("redeemed tickets and completed receipts are stable one-shot values")
    func replayAndCompleteAreOneShot() throws {
        let store = makeTicketStore(bytes: Data(repeating: 9, count: 32))
        let issued = try store.issue(
            client: .claude,
            entryID: UUID(),
            field: .password,
            mode: .stdin,
            now: base
        )
        let receipt = try store.redeem(token: issued.token, client: .claude, mode: .stdin, now: base)

        #expect(throws: VaultAgentTicketError.used) {
            try store.redeem(token: issued.token, client: .claude, mode: .stdin, now: base)
        }
        #expect(throws: VaultAgentTicketError.bindingMismatch) {
            try store.complete(receiptID: receipt.receiptID, client: .codex, now: base)
        }
        #expect(try store.complete(receiptID: receipt.receiptID, client: .claude, now: base) == receipt.binding)
        #expect(throws: VaultAgentTicketError.used) {
            try store.complete(receiptID: receipt.receiptID, client: .claude, now: base)
        }
    }

    @Test("random failures, malformed output, and three collisions fail closed")
    func randomnessFailuresFailClosed() throws {
        let unavailable = VaultAgentTicketStore(
            randomBytes: { throw TicketProbeError.failed },
            commandBuilder: validCommand
        )
        #expect(throws: VaultAgentTicketError.randomnessUnavailable) {
            try issueOne(unavailable, at: base)
        }

        for length in [0, 31, 33] {
            let malformed = makeTicketStore(bytes: Data(repeating: 1, count: length))
            #expect(throws: VaultAgentTicketError.randomnessUnavailable) {
                try issueOne(malformed, at: base)
            }
        }

        let colliding = makeTicketStore(bytes: Data(repeating: 2, count: 32))
        _ = try issueOne(colliding, at: base)
        #expect(throws: VaultAgentTicketError.randomnessUnavailable) {
            try issueOne(colliding, at: base)
        }
    }

    @Test("invalid commands never insert pending tokens")
    func invalidCommandDoesNotInsert() throws {
        let bytes = Data(repeating: 3, count: 32)
        let tooMany = VaultAgentTicketStore(
            randomBytes: { bytes },
            commandBuilder: { _, _, _ in
                Array(repeating: "argument", count: VaultAgentLimits.maximumCommandArguments + 1)
            }
        )
        #expect(throws: VaultAgentTicketError.invalidCommand) {
            try issueOne(tooMany, at: base)
        }

        let tooLarge = VaultAgentTicketStore(
            randomBytes: { bytes },
            commandBuilder: { _, _, _ in
                [String(repeating: "x", count: VaultAgentLimits.maximumCommandArgumentBytes + 1)]
            }
        )
        #expect(throws: VaultAgentTicketError.invalidCommand) {
            try issueOne(tooLarge, at: base)
        }

        let validAfterFailure = VaultAgentTicketStore(
            randomBytes: { bytes },
            commandBuilder: CommandSequence(commands: [
                Array(repeating: "argument", count: VaultAgentLimits.maximumCommandArguments + 1),
                validCommand(.codex, .stdin, "token")
            ]).next
        )
        #expect(throws: VaultAgentTicketError.invalidCommand) {
            try issueOne(validAfterFailure, at: base)
        }
        _ = try issueOne(validAfterFailure, at: base)
    }
}

extension VaultAgentTicketStoreTests {

    @Test("pending, receipt, and tombstone capacity are hard bounded")
    func capacitiesAreBounded() throws {
        let pendingSequence = TicketRandomSequence()
        let pendingStore = makeTicketStore(randomBytes: pendingSequence.next)
        for _ in 0..<128 { _ = try issueOne(pendingStore, at: base) }
        #expect(throws: VaultAgentTicketError.capacityExceeded) {
            try issueOne(pendingStore, at: base)
        }

        let receiptSequence = TicketRandomSequence()
        let receiptStore = makeTicketStore(randomBytes: receiptSequence.next)
        var receiptIDs = [UUID]()
        for _ in 0..<128 {
            let ticket = try issueOne(receiptStore, at: base)
            receiptIDs.append(try receiptStore.redeem(
                token: ticket.token,
                client: .codex,
                mode: .stdin,
                now: base
            ).receiptID)
        }
        let blocked = try issueOne(receiptStore, at: base)
        #expect(throws: VaultAgentTicketError.capacityExceeded) {
            try receiptStore.redeem(token: blocked.token, client: .codex, mode: .stdin, now: base)
        }
        _ = try receiptStore.complete(receiptID: receiptIDs[0], client: .codex, now: base)
        _ = try receiptStore.redeem(token: blocked.token, client: .codex, mode: .stdin, now: base)

        let tombstoneSequence = TicketRandomSequence()
        let tombstoneStore = makeTicketStore(randomBytes: tombstoneSequence.next)
        for _ in 0..<256 {
            let ticket = try issueOne(tombstoneStore, at: base)
            let receipt = try tombstoneStore.redeem(
                token: ticket.token,
                client: .codex,
                mode: .stdin,
                now: base
            )
            _ = try tombstoneStore.complete(receiptID: receipt.receiptID, client: .codex, now: base)
        }
        let tombstoneBlocked = try issueOne(tombstoneStore, at: base)
        #expect(throws: VaultAgentTicketError.capacityExceeded) {
            try tombstoneStore.redeem(
                token: tombstoneBlocked.token,
                client: .codex,
                mode: .stdin,
                now: base
            )
        }
        _ = try issueOne(tombstoneStore, at: base.addingTimeInterval(31))
    }

    @Test("expired ticket and receipt markers share the tombstone hard limit")
    func expiredMarkersShareTombstoneCapacity() throws {
        let sequence = TicketRandomSequence()
        let store = makeTicketStore(randomBytes: sequence.next)
        for _ in 0..<128 {
            let ticket = try issueOne(store, at: base)
            _ = try store.redeem(token: ticket.token, client: .codex, mode: .stdin, now: base)
        }
        for _ in 0..<128 {
            _ = try issueOne(store, at: base)
        }

        let blocked = try issueOne(store, at: base.addingTimeInterval(31))

        #expect(throws: VaultAgentTicketError.capacityExceeded) {
            try store.redeem(
                token: blocked.token,
                client: .codex,
                mode: .stdin,
                now: base.addingTimeInterval(31)
            )
        }
        store.removeAll()
        let recovered = try issueOne(store, at: base.addingTimeInterval(31))
        _ = try store.redeem(
            token: recovered.token,
            client: .codex,
            mode: .stdin,
            now: base.addingTimeInterval(31)
        )
    }

    @Test("removeAll atomically invalidates tickets and receipts")
    func removeAllInvalidatesEverything() throws {
        let sequence = TicketRandomSequence()
        let store = makeTicketStore(randomBytes: sequence.next)
        let pending = try issueOne(store, at: base)
        let redeemedTicket = try issueOne(store, at: base)
        let receipt = try store.redeem(
            token: redeemedTicket.token,
            client: .codex,
            mode: .stdin,
            now: base
        )

        store.removeAll()

        #expect(throws: VaultAgentTicketError.used) {
            try store.redeem(token: pending.token, client: .codex, mode: .stdin, now: base)
        }
        #expect(throws: VaultAgentTicketError.used) {
            try store.complete(receiptID: receipt.receiptID, client: .codex, now: base)
        }
        _ = try issueOne(store, at: base)
    }

    private func makeTicketStore(bytes: Data) -> VaultAgentTicketStore {
        makeTicketStore(randomBytes: { bytes })
    }

    private func makeTicketStore(
        randomBytes: @escaping () throws -> Data
    ) -> VaultAgentTicketStore {
        VaultAgentTicketStore(randomBytes: randomBytes, commandBuilder: validCommand)
    }

    private func issueOne(_ store: VaultAgentTicketStore, at date: Date) throws -> VaultAgentPreparedTicket {
        try store.issue(
            client: .codex,
            entryID: UUID(),
            field: .password,
            mode: .stdin,
            now: date
        )
    }
}

extension VaultAgentTicketStoreTests {

    @Test("all client and category buckets enforce their fixed limits")
    func allRateLimitBuckets() throws {
        #expect(Set(VaultAgentRateLimitCategory.allCases) == Set([.metadata, .directSecret, .ticket]))
        let limits: [(VaultAgentRateLimitCategory, Int)] = [
            (.metadata, 60),
            (.directSecret, 10),
            (.ticket, 10)
        ]
        for client in VaultAgentClientKind.allCases {
            for (category, limit) in limits {
                let limiter = VaultAgentRateLimiter()
                for _ in 0..<limit {
                    try limiter.check(client: client, category: category, at: base)
                }
                #expect(throws: VaultAgentRateLimitError.self) {
                    try limiter.check(client: client, category: category, at: base)
                }
            }
        }
    }

    @Test("rate limits isolate buckets and recover at exactly sixty seconds")
    func rateLimitIsolationAndBoundary() throws {
        let limiter = VaultAgentRateLimiter()
        for _ in 0..<10 {
            try limiter.check(client: .codex, category: .ticket, at: base)
        }
        #expect(throws: VaultAgentRateLimitError.self) {
            try limiter.check(client: .codex, category: .ticket, at: base)
        }

        try limiter.check(client: .claude, category: .ticket, at: base)
        try limiter.check(client: .codex, category: .directSecret, at: base)
        try limiter.check(client: .codex, category: .ticket, at: base.addingTimeInterval(60))
    }

    @Test("rejected rate-limit attempts do not extend the window")
    func rejectedAttemptsAreNotCounted() throws {
        let limiter = VaultAgentRateLimiter()
        for _ in 0..<10 {
            try limiter.check(client: .cli, category: .directSecret, at: base)
        }
        do {
            try limiter.check(client: .cli, category: .directSecret, at: base)
            Issue.record("expected rate limit")
        } catch let error as VaultAgentRateLimitError {
            #expect(error.retryAfterMilliseconds == 60_000)
        }
        do {
            try limiter.check(client: .cli, category: .directSecret, at: base.addingTimeInterval(10.0001))
            Issue.record("expected rate limit")
        } catch let error as VaultAgentRateLimitError {
            #expect(error.retryAfterMilliseconds == 50_000)
        }
        do {
            try limiter.check(client: .cli, category: .directSecret, at: base.addingTimeInterval(59.9999))
            Issue.record("expected rate limit")
        } catch let error as VaultAgentRateLimitError {
            #expect(error.retryAfterMilliseconds == 1)
        }
        try limiter.check(client: .cli, category: .directSecret, at: base.addingTimeInterval(60))
    }

    @Test("clock rollback fails closed without an oversized retry delay")
    func clockRollbackFailsClosed() throws {
        let limiter = VaultAgentRateLimiter()
        for _ in 0..<10 {
            try limiter.check(client: .codex, category: .ticket, at: base)
        }
        do {
            try limiter.check(client: .codex, category: .ticket, at: base.addingTimeInterval(-120))
            Issue.record("clock rollback must not reset the bucket")
        } catch let error as VaultAgentRateLimitError {
            #expect(error.retryAfterMilliseconds == 60_000)
        }
    }

    @Test("concurrent rate-limit checks admit only the bucket capacity")
    func concurrentRateLimitChecks() {
        let limiter = VaultAgentRateLimiter()
        let outcomes = LockedArray<Bool>()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            outcomes.append((try? limiter.check(client: .claude, category: .ticket, at: base)) != nil)
        }
        #expect(outcomes.values.filter { $0 }.count == 10)
    }

    @Test("audit key reads an existing independent non-synchronizing item")
    func auditKeyReadsExistingItem() throws {
        let key = Data(repeating: 0x41, count: 32)
        let probe = AuditKeychainProbe(copyResults: [(errSecSuccess, key)])
        let store = VaultAgentAuditKeyStore(
            keychain: probe,
            usesDataProtectionKeychain: true,
            randomBytes: { throw TicketProbeError.failed }
        )

        #expect(try store.loadOrCreate() == key)
        let query = try #require(probe.copyQueries.first)
        assertAuditBaseQuery(query)
        #expect(Set(query.keys) == Set([
            kSecClass, kSecAttrService, kSecAttrAccount, kSecAttrSynchronizable,
            kSecAttrAccessible, kSecUseDataProtectionKeychain, kSecReturnData, kSecMatchLimit
        ].map { $0 as String }))
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        #expect(probe.updateQueries.isEmpty)
        #expect(probe.addQueries.isEmpty)
    }

    @Test("audit key creation uses update then secure device-only add")
    func auditKeyCreatesSecureItem() throws {
        let key = Data(repeating: 0x42, count: 32)
        let probe = AuditKeychainProbe(
            copyResults: [(errSecItemNotFound, nil)],
            updateStatuses: [errSecItemNotFound],
            addStatuses: [errSecSuccess]
        )
        let store = VaultAgentAuditKeyStore(
            keychain: probe,
            usesDataProtectionKeychain: true,
            randomBytes: { key }
        )

        #expect(try store.loadOrCreate() == key)
        let update = try #require(probe.updateQueries.first)
        let attributes = try #require(probe.updateAttributes.first)
        let add = try #require(probe.addQueries.first)
        assertAuditBaseQuery(update)
        assertAuditBaseQuery(add)
        #expect(Set(update.keys) == Set([
            kSecClass, kSecAttrService, kSecAttrAccount, kSecAttrSynchronizable,
            kSecAttrAccessible, kSecUseDataProtectionKeychain
        ].map { $0 as String }))
        #expect(Set(attributes.keys) == Set([kSecValueData as String]))
        #expect(Set(add.keys) == Set([
            kSecClass, kSecAttrService, kSecAttrAccount, kSecAttrSynchronizable,
            kSecValueData, kSecAttrAccessible, kSecUseDataProtectionKeychain
        ].map { $0 as String }))
        #expect(attributes[kSecValueData as String] as? Data == key)
        #expect(add[kSecValueData as String] as? Data == key)
        #expect(add[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(add[kSecAttrAccessControl as String] == nil)
    }

    @Test("audit key handles update and duplicate-add creation races")
    func auditKeyCreationRaces() throws {
        let generated = Data(repeating: 0x43, count: 32)
        let updated = AuditKeychainProbe(
            copyResults: [(errSecItemNotFound, nil)],
            updateStatuses: [errSecSuccess]
        )
        #expect(try VaultAgentAuditKeyStore(keychain: updated, randomBytes: { generated }).loadOrCreate() == generated)
        #expect(updated.addQueries.isEmpty)

        let established = Data(repeating: 0x44, count: 32)
        let duplicate = AuditKeychainProbe(
            copyResults: [(errSecItemNotFound, nil), (errSecSuccess, established)],
            updateStatuses: [errSecItemNotFound],
            addStatuses: [errSecDuplicateItem]
        )
        #expect(try VaultAgentAuditKeyStore(keychain: duplicate, randomBytes: { generated }).loadOrCreate() == established)
        #expect(duplicate.copyQueries.count == 2)
    }

    @Test("ad-hoc builds omit the unavailable Data Protection Keychain selector")
    func auditKeyAdHocBuildUsesLegacyKeychain() throws {
        let key = Data(repeating: 0x45, count: 32)
        let probe = AuditKeychainProbe(copyResults: [(errSecSuccess, key)])
        let store = VaultAgentAuditKeyStore(
            keychain: probe,
            usesDataProtectionKeychain: false,
            randomBytes: { throw TicketProbeError.failed }
        )

        #expect(try store.loadOrCreate() == key)
        #expect(probe.copyQueries.first?[kSecUseDataProtectionKeychain as String] == nil)
    }

    @Test("a weaker same-name audit item cannot be accepted or migrated")
    func weakerAuditItemFailsClosed() {
        let generated = Data(repeating: 0x46, count: 32)
        let weakItem = AuditKeychainProbe(
            copyResults: [(errSecItemNotFound, nil), (errSecItemNotFound, nil)],
            updateStatuses: [errSecItemNotFound],
            addStatuses: [errSecDuplicateItem]
        )

        #expect(throws: VaultAgentAuditKeyStoreError.unavailable) {
            try VaultAgentAuditKeyStore(keychain: weakItem, randomBytes: { generated }).loadOrCreate()
        }
        #expect(weakItem.copyQueries.count == 2)
        #expect(weakItem.copyQueries.allSatisfy(hasSecureAuditAccessibility))
        #expect(weakItem.updateQueries.allSatisfy(hasSecureAuditAccessibility))
        #expect(weakItem.addQueries.allSatisfy(hasSecureAuditAccessibility))
    }

    @Test("audit key failures never return weak or malformed keys")
    func auditKeyFailuresFailClosed() {
        let key = Data(repeating: 0x45, count: 32)
        let readFailure = AuditKeychainProbe(copyResults: [(errSecAuthFailed, nil)])
        #expect(throws: VaultAgentAuditKeyStoreError.unavailable) {
            try VaultAgentAuditKeyStore(keychain: readFailure, randomBytes: { key }).loadOrCreate()
        }

        let malformed = AuditKeychainProbe(copyResults: [(errSecSuccess, Data(repeating: 0, count: 31))])
        #expect(throws: VaultAgentAuditKeyStoreError.unavailable) {
            try VaultAgentAuditKeyStore(keychain: malformed, randomBytes: { key }).loadOrCreate()
        }

        let randomFailure = AuditKeychainProbe(copyResults: [(errSecItemNotFound, nil)])
        #expect(throws: VaultAgentAuditKeyStoreError.unavailable) {
            try VaultAgentAuditKeyStore(keychain: randomFailure, randomBytes: { throw TicketProbeError.failed }).loadOrCreate()
        }

        for length in [31, 33] {
            let malformedRandom = AuditKeychainProbe(copyResults: [(errSecItemNotFound, nil)])
            #expect(throws: VaultAgentAuditKeyStoreError.unavailable) {
                try VaultAgentAuditKeyStore(
                    keychain: malformedRandom,
                    randomBytes: { Data(repeating: 0, count: length) }
                ).loadOrCreate()
            }
            #expect(malformedRandom.updateQueries.isEmpty)
        }

        let updateFailure = AuditKeychainProbe(
            copyResults: [(errSecItemNotFound, nil)],
            updateStatuses: [errSecAuthFailed]
        )
        #expect(throws: VaultAgentAuditKeyStoreError.unavailable) {
            try VaultAgentAuditKeyStore(keychain: updateFailure, randomBytes: { key }).loadOrCreate()
        }

        let addFailure = AuditKeychainProbe(
            copyResults: [(errSecItemNotFound, nil)],
            updateStatuses: [errSecItemNotFound],
            addStatuses: [errSecAuthFailed]
        )
        #expect(throws: VaultAgentAuditKeyStoreError.unavailable) {
            try VaultAgentAuditKeyStore(keychain: addFailure, randomBytes: { key }).loadOrCreate()
        }
    }

    @Test("audit entry identifiers are HMAC digests and JSON keys are allowlisted")
    func auditDigestAndSchema() throws {
        #expect(Set(VaultAgentAuditAction.allCases.map(\.rawValue)) == Set([
            "status", "search", "get", "paste", "copy", "prepareExec", "redeemTicket",
            "completeTicket", "integrationStatus", "integrationInstall", "integrationUninstall"
        ]))
        #expect(Set(VaultAgentLatencyBucket.allCases.map(\.rawValue)) == Set([
            "under10ms", "under50ms", "under200ms", "under1s", "atLeast1s"
        ]))
        let key = Data(repeating: 0x51, count: 32)
        let logger = try makeAuditLogger(key: key)
        let entryID = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        logger.record(
            client: .codex,
            action: .prepareExec,
            entryID: entryID,
            result: .ticketExpired,
            latencyBucket: .under200ms,
            at: base
        )

        let record = try #require(logger.records(at: base).first)
        let expected = Data(HMAC<SHA256>.authenticationCode(
            for: Data(entryID.uuidString.utf8),
            using: SymmetricKey(data: key)
        )).base64URLEncodedWithoutPadding
        #expect(record.entryDigest == expected)
        let encoded = try JSONEncoder().encode(record)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == Set([
            "client", "action", "entryDigest", "result", "latencyBucket", "timestamp"
        ]))
        #expect(!(String(data: encoded, encoding: .utf8) ?? "").contains(entryID.uuidString))
    }

    @Test("audit ring keeps only fresh latest one thousand records")
    func auditRingBoundsAndRetention() throws {
        let logger = try makeAuditLogger(key: Data(repeating: 0x52, count: 32))
        for index in 0..<1_002 {
            logger.record(
                client: .claude,
                action: .search,
                entryID: nil,
                result: nil,
                latencyBucket: .under10ms,
                at: base.addingTimeInterval(Double(index))
            )
        }
        let bounded = logger.records(at: base.addingTimeInterval(1_001))
        #expect(bounded.count == 1_000)
        #expect(bounded.first?.timestamp == base.addingTimeInterval(2))

        let month = 30 * 24 * 60 * 60.0
        let cutoff = base.addingTimeInterval(month)
        let retentionLogger = try makeAuditLogger(key: Data(repeating: 0x53, count: 32))
        retentionLogger.record(client: .cli, action: .status, entryID: nil, result: nil, latencyBucket: .under10ms, at: base)
        retentionLogger.record(client: .cli, action: .get, entryID: nil, result: nil, latencyBucket: .under50ms, at: base.addingTimeInterval(0.001))
        #expect(retentionLogger.records(at: cutoff).map(\.action) == [.get])
    }

    @Test("audit recording is thread safe and returns a snapshot")
    func auditRecordingIsThreadSafe() throws {
        let logger = try makeAuditLogger(key: Data(repeating: 0x54, count: 32))
        DispatchQueue.concurrentPerform(iterations: 2_000) { index in
            logger.record(
                client: .codex,
                action: .get,
                entryID: UUID(),
                result: index.isMultiple(of: 2) ? nil : .entryNotFound,
                latencyBucket: .under50ms,
                at: base.addingTimeInterval(Double(index) / 1_000)
            )
        }

        var snapshot = logger.records(at: base.addingTimeInterval(2))
        #expect(snapshot.count == 1_000)
        snapshot.removeAll()
        #expect(logger.records(at: base.addingTimeInterval(2)).count == 1_000)
    }

    private func makeAuditLogger(key: Data) throws -> VaultAgentAuditLogger {
        let probe = AuditKeychainProbe(copyResults: [(errSecSuccess, key)])
        return try VaultAgentAuditLogger(keyStore: VaultAgentAuditKeyStore(keychain: probe))
    }
}

private func validCommand(
    _ client: VaultAgentClientKind,
    _ mode: VaultAgentInjectionMode,
    _ token: String
) -> [String] {
    ["pastera-agent", client.rawValue, mode.rawValue, "--ticket", token]
}

private func assertAuditBaseQuery(_ query: [String: Any]) {
    #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
    #expect(query[kSecAttrService as String] as? String == "com.pastera-app.Pastera.password-vault.agent-audit.v1")
    #expect(query[kSecAttrAccount as String] as? String == "PasteraVaultAgentAuditKey")
    #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
    #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    #expect(hasSecureAuditAccessibility(query))
}

private func hasSecureAuditAccessibility(_ query: [String: Any]) -> Bool {
    query[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
}

private enum TicketProbeError: Error {
    case failed
}

private final class TicketRandomSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func next() -> Data {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        var bigEndian = value.bigEndian
        var data = Data(bytes: &bigEndian, count: MemoryLayout<UInt64>.size)
        data.append(Data(repeating: UInt8(truncatingIfNeeded: value), count: 24))
        return data
    }
}

private final class CommandSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [[String]]

    init(commands: [[String]]) {
        self.commands = commands
    }

    func next(
        client: VaultAgentClientKind,
        mode: VaultAgentInjectionMode,
        token: String
    ) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard !commands.isEmpty else { return validCommand(client, mode, token) }
        return commands.removeFirst()
    }
}

private final class LockedArray<Element>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = [Element]()

    var values: [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: Element) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}

private final class AuditKeychainProbe: VaultAgentAuditKeychainAccessing {
    private let lock = NSLock()
    private var copyResults: [(OSStatus, Data?)]
    private var updateStatuses: [OSStatus]
    private var addStatuses: [OSStatus]
    private(set) var copyQueries = [[String: Any]]()
    private(set) var updateQueries = [[String: Any]]()
    private(set) var updateAttributes = [[String: Any]]()
    private(set) var addQueries = [[String: Any]]()

    init(
        copyResults: [(OSStatus, Data?)] = [],
        updateStatuses: [OSStatus] = [],
        addStatuses: [OSStatus] = []
    ) {
        self.copyResults = copyResults
        self.updateStatuses = updateStatuses
        self.addStatuses = addStatuses
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, Data?) {
        lock.lock()
        defer { lock.unlock() }
        copyQueries.append(query)
        return copyResults.isEmpty ? (errSecItemNotFound, nil) : copyResults.removeFirst()
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        updateQueries.append(query)
        updateAttributes.append(attributes)
        return updateStatuses.isEmpty ? errSecItemNotFound : updateStatuses.removeFirst()
    }

    func add(_ query: [String: Any]) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        addQueries.append(query)
        return addStatuses.isEmpty ? errSecSuccess : addStatuses.removeFirst()
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
