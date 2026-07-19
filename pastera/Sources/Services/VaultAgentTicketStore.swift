import CryptoKit
import Foundation
import PasteraAgentProtocol
import Security

struct VaultAgentTicketBinding: Equatable {
    let client: VaultAgentClientKind
    let entryID: UUID
    let field: VaultAgentSecretField
    let mode: VaultAgentInjectionMode
}

enum VaultAgentTicketError: Error, Equatable {
    case expired
    case used
    case bindingMismatch
    case capacityExceeded
    case randomnessUnavailable
    case invalidCommand
}

final class VaultAgentTicketStore {
    static let ticketLifetime: TimeInterval = 30
    static let receiptLifetime: TimeInterval = 5

    private static let pendingCapacity = 128
    private static let receiptCapacity = 128
    private static let tombstoneCapacity = 256
    private static let tombstoneLifetime: TimeInterval = 30
    private static let generationAttempts = 3

    private struct PendingTicket {
        let binding: VaultAgentTicketBinding
        let expiresAt: Date
    }

    private struct Receipt {
        let binding: VaultAgentTicketBinding
        let expiresAt: Date
    }

    private enum TombstoneKey: Hashable {
        case token(Data)
        case receipt(UUID)
    }

    private enum TombstoneOutcome {
        case used
        case expired
    }

    private struct Tombstone {
        let outcome: TombstoneOutcome
        let expiresAt: Date
    }

    private let lock = NSLock()
    private let randomBytes: () throws -> Data
    private let commandBuilder: (VaultAgentClientKind, VaultAgentInjectionMode, String) -> [String]
    private var pending = [Data: PendingTicket]()
    private var receipts = [UUID: Receipt]()
    private var tombstones = [TombstoneKey: Tombstone]()

    init(
        randomBytes: @escaping () throws -> Data = VaultAgentTicketStore.secureRandomBytes,
        commandBuilder: @escaping (VaultAgentClientKind, VaultAgentInjectionMode, String) -> [String]
    ) {
        self.randomBytes = randomBytes
        self.commandBuilder = commandBuilder
    }

    func issue(
        client: VaultAgentClientKind,
        entryID: UUID,
        field: VaultAgentSecretField,
        mode: VaultAgentInjectionMode,
        now: Date
    ) throws -> VaultAgentPreparedTicket {
        let binding = VaultAgentTicketBinding(
            client: client,
            entryID: entryID,
            field: field,
            mode: mode
        )

        lock.lock()
        removeExpiredLocked(at: now)
        let hasPendingCapacity = pending.count < Self.pendingCapacity
        lock.unlock()
        guard hasPendingCapacity else {
            throw VaultAgentTicketError.capacityExceeded
        }

        for _ in 0..<Self.generationAttempts {
            let bytes: Data
            do {
                bytes = try randomBytes()
            } catch {
                throw VaultAgentTicketError.randomnessUnavailable
            }
            guard bytes.count == 32 else {
                throw VaultAgentTicketError.randomnessUnavailable
            }

            let token = bytes.base64URLEncodedWithoutPadding
            let tokenHash = Data(SHA256.hash(data: Data(token.utf8)))
            let command = commandBuilder(client, mode, token)
            guard Self.isValid(command: command) else {
                throw VaultAgentTicketError.invalidCommand
            }

            lock.lock()
            removeExpiredLocked(at: now)
            if pending.count >= Self.pendingCapacity {
                lock.unlock()
                throw VaultAgentTicketError.capacityExceeded
            }
            let collides = pending[tokenHash] != nil || tombstones[.token(tokenHash)] != nil
            if !collides {
                let expiresAt = now.addingTimeInterval(Self.ticketLifetime)
                pending[tokenHash] = PendingTicket(binding: binding, expiresAt: expiresAt)
                lock.unlock()
                return VaultAgentPreparedTicket(token: token, expiresAt: expiresAt, command: command)
            }
            lock.unlock()
        }

        throw VaultAgentTicketError.randomnessUnavailable
    }

    func redeem(
        token: String,
        client: VaultAgentClientKind,
        mode: VaultAgentInjectionMode,
        now: Date
    ) throws -> (receiptID: UUID, binding: VaultAgentTicketBinding) {
        let tokenHash = Data(SHA256.hash(data: Data(token.utf8)))
        lock.lock()
        defer { lock.unlock() }

        removeExpiredLocked(at: now)
        if let tombstone = tombstones[.token(tokenHash)] {
            throw Self.error(for: tombstone.outcome)
        }
        guard let ticket = pending[tokenHash] else {
            throw VaultAgentTicketError.used
        }
        if now >= ticket.expiresAt {
            throw VaultAgentTicketError.expired
        }
        guard ticket.binding.client == client, ticket.binding.mode == mode else {
            throw VaultAgentTicketError.bindingMismatch
        }

        guard receipts.count < Self.receiptCapacity,
              tombstones.count < Self.tombstoneCapacity else {
            throw VaultAgentTicketError.capacityExceeded
        }

        let receiptID = UUID()
        pending.removeValue(forKey: tokenHash)
        receipts[receiptID] = Receipt(
            binding: ticket.binding,
            expiresAt: now.addingTimeInterval(Self.receiptLifetime)
        )
        tombstones[.token(tokenHash)] = Tombstone(
            outcome: .used,
            expiresAt: now.addingTimeInterval(Self.tombstoneLifetime)
        )
        return (receiptID, ticket.binding)
    }

    func complete(
        receiptID: UUID,
        client: VaultAgentClientKind,
        now: Date
    ) throws -> VaultAgentTicketBinding {
        lock.lock()
        defer { lock.unlock() }

        removeExpiredLocked(at: now)
        if let tombstone = tombstones[.receipt(receiptID)] {
            throw Self.error(for: tombstone.outcome)
        }
        guard let receipt = receipts[receiptID] else {
            throw VaultAgentTicketError.used
        }
        if now >= receipt.expiresAt {
            throw VaultAgentTicketError.expired
        }
        guard receipt.binding.client == client else {
            throw VaultAgentTicketError.bindingMismatch
        }

        receipts.removeValue(forKey: receiptID)
        return receipt.binding
    }

    func removeAll() {
        lock.lock()
        pending.removeAll(keepingCapacity: false)
        receipts.removeAll(keepingCapacity: false)
        tombstones.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    private func removeExpiredLocked(at now: Date) {
        tombstones = tombstones.filter { now < $0.value.expiresAt }
        let expiredTokens = pending.compactMap { tokenHash, ticket in
            now >= ticket.expiresAt ? tokenHash : nil
        }
        for tokenHash in expiredTokens where tombstones.count < Self.tombstoneCapacity {
            pending.removeValue(forKey: tokenHash)
            tombstones[.token(tokenHash)] = Tombstone(
                outcome: .expired,
                expiresAt: now.addingTimeInterval(Self.tombstoneLifetime)
            )
        }

        let expiredReceipts = receipts.compactMap { receiptID, receipt in
            now >= receipt.expiresAt ? receiptID : nil
        }
        for receiptID in expiredReceipts where tombstones.count < Self.tombstoneCapacity {
            receipts.removeValue(forKey: receiptID)
            tombstones[.receipt(receiptID)] = Tombstone(
                outcome: .expired,
                expiresAt: now.addingTimeInterval(Self.tombstoneLifetime)
            )
        }
    }

    private static func error(for outcome: TombstoneOutcome) -> VaultAgentTicketError {
        switch outcome {
        case .used: .used
        case .expired: .expired
        }
    }

    private static func isValid(command: [String]) -> Bool {
        guard command.count <= VaultAgentLimits.maximumCommandArguments else { return false }
        return command.allSatisfy {
            $0.lengthOfBytes(using: .utf8) <= VaultAgentLimits.maximumCommandArgumentBytes
        }
    }

    private static func secureRandomBytes() throws -> Data {
        var bytes = Data(count: 32)
        let status = bytes.withUnsafeMutableBytes { buffer in
            guard let address = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, address)
        }
        guard status == errSecSuccess else {
            throw VaultAgentTicketError.randomnessUnavailable
        }
        return bytes
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
