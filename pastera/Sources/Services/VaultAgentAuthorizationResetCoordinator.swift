import Foundation

protocol VaultAgentAuthorizationResetting: AnyObject {
    func revokeAll() throws
}

final class VaultAgentAuthorizationResetCoordinator: VaultAgentAuthorizationResetting {
    typealias StoreFactory = () -> VaultAgentGrantStoring

    private let executor: VaultAgentSerialExecutor
    private let storeFactory: StoreFactory
    private let now: () -> Date
    private let lock = NSLock()
    private weak var livePolicy: VaultAgentAuthorizationPolicy?

    init(
        executor: VaultAgentSerialExecutor,
        storeFactory: @escaping StoreFactory = { VaultAgentGrantStore() },
        now: @escaping () -> Date = Date.init
    ) {
        self.executor = executor
        self.storeFactory = storeFactory
        self.now = now
    }

    func install(_ policy: VaultAgentAuthorizationPolicy) throws {
        try executor.sync {
            try policy.reloadFromStore()
            lock.withLock { livePolicy = policy }
        }
    }

    func uninstall(_ policy: VaultAgentAuthorizationPolicy) {
        lock.withLock {
            guard livePolicy === policy else { return }
            livePolicy = nil
        }
    }

    func revokeAll() throws {
        try executor.sync {
            if let policy = lock.withLock({ livePolicy }) {
                try policy.revokeAll(at: now())
                return
            }
            let policy = try VaultAgentAuthorizationPolicy(
                store: storeFactory(),
                executor: executor
            )
            try policy.revokeAll(at: now())
        }
    }
}
