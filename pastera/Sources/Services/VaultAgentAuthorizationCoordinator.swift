import Foundation
import LocalAuthentication
import PasteraAgentProtocol

protocol VaultAgentIdentityAuthenticating {
    func authenticate(completion: @escaping (Result<Void, Error>) -> Void)
    func authenticate(
        identity: VaultAgentPeerIdentity,
        completion: @escaping (Result<Void, Error>) -> Void
    )
}

extension VaultAgentIdentityAuthenticating {
    func authenticate(
        identity _: VaultAgentPeerIdentity,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        authenticate(completion: completion)
    }
}

final class SystemVaultAgentIdentityAuthenticator: VaultAgentIdentityAuthenticating {
    func authenticate(completion: @escaping (Result<Void, Error>) -> Void) {
        evaluate(
            reason: "Authenticate to authorize password vault automation.",
            completion: completion
        )
    }

    func authenticate(
        identity: VaultAgentPeerIdentity,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        evaluate(reason: Self.authorizationReason(for: identity), completion: completion)
    }

    static func authorizationReason(for identity: VaultAgentPeerIdentity) -> String {
        let client: String
        switch identity.client {
        case .codex: client = "Codex"
        case .claude: client = "Claude Code"
        case .cli: client = "Pastera CLI"
        }
        let scopeKey = identity.client == .cli
            ? "Metadata, paste, copy, and controlled injection"
            : "Metadata, paste, and controlled injection"
        return [
            "\(pasteraPreferenceString("Authorize")) \(client): \(pasteraPreferenceString(scopeKey)).",
            pasteraPreferenceString("7 idle days · 30 days total"),
            pasteraPreferenceString("Unattended automation can expose secrets to client commands.")
        ].joined(separator: " ")
    }

    private func evaluate(
        reason: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            completion(.failure(evaluationError ?? LAError(.authenticationFailed)))
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        ) { success, error in
            if success {
                completion(.success(()))
            } else {
                completion(.failure(error ?? LAError(.authenticationFailed)))
            }
        }
    }
}

final class VaultAgentAuthorizationCoordinator {
    enum Trigger {
        case automaticFirstRequest
        case explicitPreferencesAction
    }

    private typealias Completion = (Result<VaultAgentGrant, VaultAgentErrorCode>) -> Void
    typealias AuthenticationAction = (@escaping (Result<Void, Error>) -> Void) -> Void
    typealias PrepareAction = () throws -> Void

    enum LifecycleMutationKind: Hashable {
        case install
        case uninstall
    }

    struct LifecycleMutationToken: Hashable {
        fileprivate let client: VaultAgentClientKind
        fileprivate let ownerID: UUID
        fileprivate let kind: LifecycleMutationKind
    }

    private struct ActiveLifecycleMutation {
        let token: LifecycleMutationToken
        let restoresSuspendedStateOnAbort: Bool
    }

    private enum ClientLifecycleState {
        case suspended
        case mutating(ActiveLifecycleMutation)
    }

    private struct PendingAuthorization {
        let id: UUID
        let identity: VaultAgentPeerIdentity
        let trigger: Trigger
        let prepare: PrepareAction?
        let rollbackPrepare: PrepareAction?
        var completions: [Completion]
    }

    private final class InFlightLifetime {
        var coordinator: VaultAgentAuthorizationCoordinator?

        init(_ coordinator: VaultAgentAuthorizationCoordinator) {
            self.coordinator = coordinator
        }
    }

    private static let cooldownLifetime: TimeInterval = 24 * 60 * 60
    private static let cooldownKeyPrefix = "Pastera.Agent.AuthorizationCooldownUntil.v1."

    private let executor: VaultAgentSerialExecutor
    private let policy: VaultAgentAuthorizationPolicy
    private let authenticator: VaultAgentIdentityAuthenticating
    private let defaults: UserDefaults
    private let now: () -> Date
    private var pending: [VaultAgentClientKind: PendingAuthorization] = [:]
    private var lifecycleStates = [VaultAgentClientKind: ClientLifecycleState]()

    init(
        executor: VaultAgentSerialExecutor,
        policy: VaultAgentAuthorizationPolicy,
        authenticator: VaultAgentIdentityAuthenticating = SystemVaultAgentIdentityAuthenticator(),
        defaults: UserDefaults = .standard,
        initiallySuspendedClients: Set<VaultAgentClientKind> = [],
        now: @escaping () -> Date = Date.init
    ) {
        self.executor = executor
        self.policy = policy
        self.authenticator = authenticator
        self.defaults = defaults
        self.now = now
        lifecycleStates = Dictionary(uniqueKeysWithValues: initiallySuspendedClients.map {
            ($0, .suspended)
        })
    }

    func beginLifecycleMutation(
        for client: VaultAgentClientKind,
        kind: LifecycleMutationKind
    ) -> Result<LifecycleMutationToken, VaultAgentErrorCode> {
        let result = executor.sync { () -> (LifecycleMutationToken?, PendingAuthorization?) in
            if case .some(.mutating) = lifecycleStates[client] { return (nil, nil) }
            let token = LifecycleMutationToken(client: client, ownerID: UUID(), kind: kind)
            let active = ActiveLifecycleMutation(
                token: token,
                restoresSuspendedStateOnAbort: lifecycleStates[client] != nil
            )
            lifecycleStates[client] = .mutating(active)
            return (token, pending.removeValue(forKey: client))
        }
        guard let token = result.0 else { return .failure(.vaultBusy) }
        if let cancelled = result.1 {
            deliver(.failure(.authorizationRequired), to: cancelled.completions)
        }
        return .success(token)
    }

    func commitLifecycleMutation(_ token: LifecycleMutationToken) {
        resolveLifecycleMutation(
            token,
            authorizationEligible: token.kind == .install
        )
    }

    @discardableResult
    func resolveLifecycleMutation(
        _ token: LifecycleMutationToken,
        authorizationEligible: Bool
    ) -> Bool {
        executor.sync {
            guard case let .some(.mutating(active)) = lifecycleStates[token.client],
                  active.token == token else { return false }
            lifecycleStates[token.client] = authorizationEligible ? nil : .suspended
            return true
        }
    }

    func abortLifecycleMutation(_ token: LifecycleMutationToken) {
        executor.sync {
            guard case let .some(.mutating(active)) = lifecycleStates[token.client],
                  active.token == token else { return }
            lifecycleStates[token.client] = active.restoresSuspendedStateOnAbort ? .suspended : nil
        }
    }

    func isAuthorizationBlocked(for client: VaultAgentClientKind) -> Bool {
        executor.sync { lifecycleStates[client] != nil }
    }

    func authorize(
        identity: VaultAgentPeerIdentity,
        trigger: Trigger,
        authentication: AuthenticationAction? = nil,
        prepare: PrepareAction? = nil,
        rollbackPrepare: PrepareAction? = nil,
        completion: @escaping (Result<VaultAgentGrant, VaultAgentErrorCode>) -> Void
    ) {
        executor.async { [self] in
            guard VaultAgentAuthorizationPolicy.isValid(identity) else {
                deliver(.failure(.authorizationRequired), to: [completion])
                return
            }
            guard lifecycleStates[identity.client] == nil else {
                deliver(.failure(.authorizationRequired), to: [completion])
                return
            }
            if trigger == .automaticFirstRequest,
               let cooldownUntil = defaults.object(forKey: cooldownKey(identity.client)) as? Date,
               now() < cooldownUntil {
                deliver(.failure(.authorizationRequired), to: [completion])
                return
            }
            if var current = pending[identity.client] {
                guard VaultAgentAuthorizationPolicy.identitiesMatch(current.identity, identity) else {
                    deliver(.failure(.authorizationRequired), to: [completion])
                    return
                }
                current.completions.append(completion)
                pending[identity.client] = current
                return
            }

            let pendingID = UUID()
            pending[identity.client] = PendingAuthorization(
                id: pendingID,
                identity: identity,
                trigger: trigger,
                prepare: prepare,
                rollbackPrepare: rollbackPrepare,
                completions: [completion]
            )
            let lifetime = InFlightLifetime(self)
            let authenticate = authentication ?? { callback in
                self.authenticator.authenticate(identity: identity, completion: callback)
            }
            authenticate { [executor] result in
                executor.async {
                    guard let coordinator = lifetime.coordinator else { return }
                    coordinator.finishAuthentication(
                        for: identity.client,
                        pendingID: pendingID,
                        result: result
                    )
                    lifetime.coordinator = nil
                }
            }
        }
    }

    private func finishAuthentication(
        for client: VaultAgentClientKind,
        pendingID: UUID,
        result: Result<Void, Error>
    ) {
        guard pending[client]?.id == pendingID,
              let current = pending.removeValue(forKey: client) else { return }
        let authorizationResult: Result<VaultAgentGrant, VaultAgentErrorCode>
        switch result {
        case .success:
            var prepared = false
            let authorizationDate = now()
            do {
                try current.prepare?()
                prepared = true
                let grant = try policy.authorize(
                    identity: current.identity,
                    authenticatedAt: authorizationDate
                )
                defaults.removeObject(forKey: cooldownKey(client))
                authorizationResult = .success(grant)
            } catch {
                if prepared, policy.validGrantCount(at: authorizationDate) == 0 {
                    try? current.rollbackPrepare?()
                }
                authorizationResult = .failure(.automationUnlockUnavailable)
            }
        case let .failure(error):
            if current.trigger == .automaticFirstRequest, Self.isCancellation(error) {
                defaults.set(now().addingTimeInterval(Self.cooldownLifetime), forKey: cooldownKey(client))
            }
            authorizationResult = .failure(.authorizationRequired)
        }
        deliver(authorizationResult, to: current.completions)
    }

    private func cooldownKey(_ client: VaultAgentClientKind) -> String {
        Self.cooldownKeyPrefix + client.rawValue
    }

    private static func isCancellation(_ error: Error) -> Bool {
        guard let code = (error as? LAError)?.code else { return false }
        return code == .userCancel || code == .systemCancel || code == .appCancel
    }

    private func deliver(
        _ result: Result<VaultAgentGrant, VaultAgentErrorCode>,
        to completions: [Completion]
    ) {
        DispatchQueue.main.async {
            completions.forEach { $0(result) }
        }
    }
}
