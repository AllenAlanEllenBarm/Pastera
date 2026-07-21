import Foundation
import PasteraAgentProtocol

struct VaultAgentPeerIdentity: Codable, Equatable {
    let client: VaultAgentClientKind
    let helperRequirement: String
    let helperCDHash: Data?
    let helperIsAdHoc: Bool
    let helperPath: String
    let hostRequirement: String?
    let hostCDHash: Data?
    let hostIsAdHoc: Bool?
    let hostPath: String?
}

struct VaultAgentGrant: Codable, Equatable {
    let identity: VaultAgentPeerIdentity
    let authenticatedAt: Date
    var idleExpiresAt: Date
    let hardExpiresAt: Date
    var lastSensitiveUseAt: Date?
    var revokedAt: Date?
}

enum VaultAgentGrantDecision: Equatable {
    case allowed(VaultAgentGrant)
    case missing
    case identityChanged
    case idleExpired
    case hardExpired
    case revoked
}

protocol VaultAgentGrantStoring {
    func load() throws -> [VaultAgentClientKind: VaultAgentGrant]
    func save(_ grants: [VaultAgentClientKind: VaultAgentGrant]) throws
}

final class VaultAgentSerialExecutor {
    private let queue: DispatchQueue
    private let key = DispatchSpecificKey<UUID>()
    private let value = UUID()

    init(queue: DispatchQueue) {
        self.queue = queue
        queue.setSpecific(key: key, value: value)
    }

    func sync<T>(_ work: () throws -> T) rethrows -> T {
        if DispatchQueue.getSpecific(key: key) == value {
            return try work()
        }
        return try queue.sync(execute: work)
    }

    func async(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    var isCurrent: Bool {
        DispatchQueue.getSpecific(key: key) == value
    }
}

final class VaultAgentAuthorizationPolicy {
    static let idleLifetime: TimeInterval = 7 * 24 * 60 * 60
    static let hardLifetime: TimeInterval = 30 * 24 * 60 * 60

    private let store: VaultAgentGrantStoring
    private let executor: VaultAgentSerialExecutor
    private var grants: [VaultAgentClientKind: VaultAgentGrant]

    init(store: VaultAgentGrantStoring, executor: VaultAgentSerialExecutor) throws {
        self.store = store
        self.executor = executor
        grants = try executor.sync { try store.load() }
    }

    @discardableResult
    func authorize(identity: VaultAgentPeerIdentity, authenticatedAt: Date) throws -> VaultAgentGrant {
        try executor.sync {
            guard Self.isValid(identity) else {
                throw VaultAgentErrorCode.authorizationRequired
            }
            let grant = VaultAgentGrant(
                identity: identity,
                authenticatedAt: authenticatedAt,
                idleExpiresAt: authenticatedAt.addingTimeInterval(Self.idleLifetime),
                hardExpiresAt: authenticatedAt.addingTimeInterval(Self.hardLifetime),
                lastSensitiveUseAt: nil,
                revokedAt: nil
            )
            var updated = grants
            updated[identity.client] = grant
            try store.save(updated)
            grants = updated
            return grant
        }
    }

    func decision(for identity: VaultAgentPeerIdentity, at date: Date) -> VaultAgentGrantDecision {
        executor.sync { decision(for: identity, at: date, in: grants) }
    }

    func grantSnapshot(for client: VaultAgentClientKind) -> VaultAgentGrant? {
        executor.sync { grants[client] }
    }

    func recordSensitiveSuccess(for identity: VaultAgentPeerIdentity, at date: Date) throws {
        try executor.sync {
            guard case .allowed(var grant) = decision(for: identity, at: date, in: grants) else { return }
            grant.lastSensitiveUseAt = date
            grant.idleExpiresAt = min(
                date.addingTimeInterval(Self.idleLifetime),
                grant.hardExpiresAt
            )
            var updated = grants
            updated[identity.client] = grant
            try store.save(updated)
            grants = updated
        }
    }

    func recordInteractiveSensitiveSuccess(at date: Date) throws {
        try executor.sync {
            var updated = grants
            var changed = false
            for (client, existingGrant) in grants {
                guard case .allowed(var grant) = decision(
                    for: existingGrant.identity,
                    at: date,
                    in: grants
                ) else { continue }
                grant.lastSensitiveUseAt = date
                grant.idleExpiresAt = min(
                    date.addingTimeInterval(Self.idleLifetime),
                    grant.hardExpiresAt
                )
                updated[client] = grant
                changed = true
            }
            guard changed else { return }
            try store.save(updated)
            grants = updated
        }
    }

    func recordFailure(for _: VaultAgentPeerIdentity, at _: Date) {}

    func revoke(_ client: VaultAgentClientKind, at date: Date) throws {
        try executor.sync {
            guard var grant = grants[client] else { return }
            grant.revokedAt = date
            var updated = grants
            updated[client] = grant
            try store.save(updated)
            grants = updated
        }
    }

    func revokeAll(at date: Date) throws {
        try executor.sync {
            guard !grants.isEmpty else { return }
            var updated = grants
            for client in updated.keys {
                updated[client]?.revokedAt = date
            }
            try store.save(updated)
            grants = updated
        }
    }

    func validGrantCount(at date: Date) -> Int {
        executor.sync {
            grants.values.reduce(into: 0) { count, grant in
                if case .allowed = decision(for: grant.identity, at: date, in: grants) {
                    count += 1
                }
            }
        }
    }

    private func decision(
        for identity: VaultAgentPeerIdentity,
        at date: Date,
        in grants: [VaultAgentClientKind: VaultAgentGrant]
    ) -> VaultAgentGrantDecision {
        guard let grant = grants[identity.client] else { return .missing }
        if grant.revokedAt != nil { return .revoked }
        guard Self.identitiesMatch(grant.identity, identity) else { return .identityChanged }
        if date >= grant.hardExpiresAt { return .hardExpired }
        if date >= grant.idleExpiresAt { return .idleExpired }
        return .allowed(grant)
    }

    static func identitiesMatch(
        _ stored: VaultAgentPeerIdentity,
        _ current: VaultAgentPeerIdentity
    ) -> Bool {
        guard isValid(stored),
              isValid(current),
              stored.client == current.client,
              signaturesMatch(stored, current, useHost: false) else { return false }
        return hostsMatch(stored, current)
    }

    static func isValid(_ identity: VaultAgentPeerIdentity) -> Bool {
        guard !identity.helperRequirement.isEmpty,
              !identity.helperPath.isEmpty,
              !identity.helperIsAdHoc || identity.helperCDHash != nil else { return false }
        switch identity.client {
        case .codex, .claude:
            guard let hostRequirement = identity.hostRequirement,
                  !hostRequirement.isEmpty,
                  let hostIsAdHoc = identity.hostIsAdHoc,
                  let hostPath = identity.hostPath,
                  !hostPath.isEmpty else { return false }
            return !hostIsAdHoc || identity.hostCDHash != nil
        case .cli:
            return identity.hostRequirement == nil &&
                identity.hostCDHash == nil &&
                identity.hostIsAdHoc == nil &&
                identity.hostPath == nil
        }
    }

    private static func hostsMatch(
        _ stored: VaultAgentPeerIdentity,
        _ current: VaultAgentPeerIdentity
    ) -> Bool {
        let storedHasHost = stored.hostRequirement != nil || stored.hostCDHash != nil ||
            stored.hostIsAdHoc != nil || stored.hostPath != nil
        let currentHasHost = current.hostRequirement != nil || current.hostCDHash != nil ||
            current.hostIsAdHoc != nil || current.hostPath != nil
        guard storedHasHost == currentHasHost else { return false }
        guard storedHasHost else { return true }
        return signaturesMatch(stored, current, useHost: true)
    }

    private static func signaturesMatch(
        _ stored: VaultAgentPeerIdentity,
        _ current: VaultAgentPeerIdentity,
        useHost: Bool
    ) -> Bool {
        let storedRequirement: String
        let storedCDHash: Data?
        let storedIsAdHoc: Bool
        let storedPath: String
        let currentRequirement: String
        let currentCDHash: Data?
        let currentIsAdHoc: Bool
        let currentPath: String
        if useHost {
            guard let resolvedStoredRequirement = stored.hostRequirement,
                  let resolvedStoredIsAdHoc = stored.hostIsAdHoc,
                  let resolvedStoredPath = stored.hostPath,
                  let resolvedCurrentRequirement = current.hostRequirement,
                  let resolvedCurrentIsAdHoc = current.hostIsAdHoc,
                  let resolvedCurrentPath = current.hostPath else { return false }
            storedRequirement = resolvedStoredRequirement
            storedCDHash = stored.hostCDHash
            storedIsAdHoc = resolvedStoredIsAdHoc
            storedPath = resolvedStoredPath
            currentRequirement = resolvedCurrentRequirement
            currentCDHash = current.hostCDHash
            currentIsAdHoc = resolvedCurrentIsAdHoc
            currentPath = resolvedCurrentPath
        } else {
            storedRequirement = stored.helperRequirement
            storedCDHash = stored.helperCDHash
            storedIsAdHoc = stored.helperIsAdHoc
            storedPath = stored.helperPath
            currentRequirement = current.helperRequirement
            currentCDHash = current.helperCDHash
            currentIsAdHoc = current.helperIsAdHoc
            currentPath = current.helperPath
        }
        guard !storedRequirement.isEmpty,
              !currentRequirement.isEmpty,
              !storedPath.isEmpty,
              !currentPath.isEmpty,
              storedRequirement == currentRequirement,
              canonicalPath(storedPath) == canonicalPath(currentPath),
              storedIsAdHoc == currentIsAdHoc else { return false }
        guard storedIsAdHoc else { return true }
        guard let storedCDHash, let currentCDHash else { return false }
        return storedCDHash == currentCDHash
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
