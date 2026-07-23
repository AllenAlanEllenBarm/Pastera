import Foundation

final class LocalOnlyPasswordVaultSyncController: PasswordVaultSyncControlling {
    let snapshot: PasswordVaultSyncSnapshot
    private let failure: PasswordVaultSyncFailure?

    init(
        localVaultAvailable: Bool = false,
        failure: PasswordVaultSyncFailure? = nil
    ) {
        self.failure = failure
        snapshot = PasswordVaultSyncSnapshot(
            mode: .localOnly,
            phase: failure.map(PasswordVaultSyncPhase.failed) ?? .disabled,
            localVaultAvailable: localVaultAvailable,
            remoteVaultAvailable: nil,
            pendingChangeCount: 0,
            conflictCopyCount: 0,
            lastSyncAt: nil
        )
    }

    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID {
        let identifier = UUID()
        DispatchQueue.main.async { [snapshot] in observer(snapshot) }
        return identifier
    }

    func removeObserver(_ identifier: UUID) {}
    func record(_ commit: PasswordVaultCommit) {}
    func synchronize(reason: SyncCoordinator.Reason) {}
    func enableOneDrive(
        rootURL: URL,
        remoteMasterPassword: String?, // swiftlint:disable:this inclusive_language
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) { completion(.failure(.remoteUnavailable)) }
    // swiftlint:disable inclusive_language
    func retry(
        remoteMasterPassword: String,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) { completion(.failure(.remoteUnavailable)) }
    // swiftlint:enable inclusive_language
    func switchToLocalOnly(
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) { completion(failure.map(Result.failure) ?? .success(())) }
    func deleteRemoteReplica(
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) { completion(failure.map(Result.failure) ?? .success(())) }
}
