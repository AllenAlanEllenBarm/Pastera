import Foundation
import LocalAuthentication
import PasteraAgentProtocol

protocol VaultAgentIdentityAuthenticating {
    func authenticate(completion: @escaping (Result<Void, Error>) -> Void)
}

final class SystemVaultAgentIdentityAuthenticator: VaultAgentIdentityAuthenticating {
    func authenticate(completion: @escaping (Result<Void, Error>) -> Void) {
        let context = LAContext()
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            completion(.failure(evaluationError ?? LAError(.authenticationFailed)))
            return
        }
        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "Authenticate to authorize password vault automation."
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

    private struct PendingAuthorization {
        let identity: VaultAgentPeerIdentity
        let trigger: Trigger
        let prepare: PrepareAction?
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

    init(
        executor: VaultAgentSerialExecutor,
        policy: VaultAgentAuthorizationPolicy,
        authenticator: VaultAgentIdentityAuthenticating = SystemVaultAgentIdentityAuthenticator(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.executor = executor
        self.policy = policy
        self.authenticator = authenticator
        self.defaults = defaults
        self.now = now
    }

    func authorize(
        identity: VaultAgentPeerIdentity,
        trigger: Trigger,
        authentication: AuthenticationAction? = nil,
        prepare: PrepareAction? = nil,
        completion: @escaping (Result<VaultAgentGrant, VaultAgentErrorCode>) -> Void
    ) {
        executor.async { [self] in
            guard VaultAgentAuthorizationPolicy.isValid(identity) else {
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

            pending[identity.client] = PendingAuthorization(
                identity: identity,
                trigger: trigger,
                prepare: prepare,
                completions: [completion]
            )
            let lifetime = InFlightLifetime(self)
            let authenticate = authentication ?? authenticator.authenticate
            authenticate { [executor] result in
                executor.async {
                    guard let coordinator = lifetime.coordinator else { return }
                    coordinator.finishAuthentication(for: identity.client, result: result)
                    lifetime.coordinator = nil
                }
            }
        }
    }

    private func finishAuthentication(
        for client: VaultAgentClientKind,
        result: Result<Void, Error>
    ) {
        guard let current = pending.removeValue(forKey: client) else { return }
        let authorizationResult: Result<VaultAgentGrant, VaultAgentErrorCode>
        switch result {
        case .success:
            do {
                try current.prepare?()
                let grant = try policy.authorize(identity: current.identity, authenticatedAt: now())
                defaults.removeObject(forKey: cooldownKey(client))
                authorizationResult = .success(grant)
            } catch {
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
