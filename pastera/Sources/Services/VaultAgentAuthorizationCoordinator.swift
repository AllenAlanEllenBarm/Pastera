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

    private struct PendingAuthorization {
        let identity: VaultAgentPeerIdentity
        let trigger: Trigger
        var completions: [Completion]
    }

    private static let cooldownLifetime: TimeInterval = 24 * 60 * 60
    private static let cooldownKeyPrefix = "Pastera.Agent.AuthorizationCooldownUntil.v1."

    private let policy: VaultAgentAuthorizationPolicy
    private let authenticator: VaultAgentIdentityAuthenticating
    private let defaults: UserDefaults
    private let now: () -> Date
    private let queue = DispatchQueue(label: "com.pastera-app.Pastera.vault-agent.authorization")
    private var pending: [VaultAgentClientKind: PendingAuthorization] = [:]

    init(
        policy: VaultAgentAuthorizationPolicy,
        authenticator: VaultAgentIdentityAuthenticating = SystemVaultAgentIdentityAuthenticator(),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init
    ) {
        self.policy = policy
        self.authenticator = authenticator
        self.defaults = defaults
        self.now = now
    }

    func authorize(
        identity: VaultAgentPeerIdentity,
        trigger: Trigger,
        completion: @escaping (Result<VaultAgentGrant, VaultAgentErrorCode>) -> Void
    ) {
        queue.async { [self] in
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
                completions: [completion]
            )
            authenticator.authenticate { [weak self] result in
                self?.queue.async {
                    self?.finishAuthentication(for: identity.client, result: result)
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
