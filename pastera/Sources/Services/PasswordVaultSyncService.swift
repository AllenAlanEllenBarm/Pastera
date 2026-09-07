import Foundation

// The sync state machine and its transactional helpers intentionally remain co-located.
// swiftlint:disable file_length

protocol PasswordVaultSyncControlling: AnyObject {
    var snapshot: PasswordVaultSyncSnapshot { get }

    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID
    func removeObserver(_ identifier: UUID)
    func record(_ commit: PasswordVaultCommit)
    func synchronize(reason: SyncCoordinator.Reason)
    func prepareForcedReset(previousLocalDigest: String) throws
    func cancelPreparedForcedReset(previousLocalDigest: String)
    func retryForcedReset(completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void)
    // swiftlint:disable inclusive_language
    func enableOneDrive(
        rootURL: URL,
        remoteMasterPassword: String?,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    )
    func retry(
        remoteMasterPassword: String,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    )
    // swiftlint:enable inclusive_language
}

extension PasswordVaultSyncControlling {
    func prepareForcedReset(previousLocalDigest: String) throws {}
    func cancelPreparedForcedReset(previousLocalDigest: String) {}
    func retryForcedReset(completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void) {
        completion(.failure(.remoteUnavailable))
    }

    // swiftlint:disable inclusive_language
    func retry(
        remoteMasterPassword: String,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        completion(.failure(.remoteUnavailable))
    }
    // swiftlint:enable inclusive_language
}

final class PasswordVaultSyncService: PasswordVaultSyncControlling {
    typealias CallbackDispatcher = (@escaping () -> Void) -> Void

    private let access: PasswordVaultSyncAccess
    private let metadataStore: PasswordVaultSyncMetadataStoring
    private let cloudReplica: PasswordVaultCloudReplica
    private let processStatus: OneDriveProcessStatusServicing
    private let rootURLProvider: () -> URL?
    private let rootURLSetter: (URL) -> Void
    private let rootValidator: (URL) -> PasswordVaultSyncFailure?
    private let executor: VaultAgentSerialExecutor
    private let callbackDispatcher: CallbackDispatcher
    private let now: () -> Date

    private let stateLock = NSLock()
    private var metadata: PasswordVaultSyncMetadata
    private var currentSnapshot: PasswordVaultSyncSnapshot
    private var observers = [UUID: (PasswordVaultSyncSnapshot) -> Void]()

    init(
        access: PasswordVaultSyncAccess,
        metadataStore: PasswordVaultSyncMetadataStoring,
        cloudReplica: PasswordVaultCloudReplica,
        processStatus: OneDriveProcessStatusServicing,
        rootURLProvider: @escaping () -> URL?,
        rootURLSetter: @escaping (URL) -> Void,
        rootValidator: @escaping (URL) -> PasswordVaultSyncFailure?,
        queue: DispatchQueue = DispatchQueue(label: "com.pastera.password-vault-sync"),
        callbackDispatcher: CallbackDispatcher? = nil,
        now: @escaping () -> Date = Date.init
    ) throws {
        let executor = VaultAgentSerialExecutor(queue: queue)
        let metadata = try executor.sync { try metadataStore.load() }
        self.access = access
        self.metadataStore = metadataStore
        self.cloudReplica = cloudReplica
        self.processStatus = processStatus
        self.rootURLProvider = rootURLProvider
        self.rootURLSetter = rootURLSetter
        self.rootValidator = rootValidator
        self.executor = executor
        self.callbackDispatcher = callbackDispatcher ?? { callback in
            DispatchQueue.main.async(execute: callback)
        }
        self.now = now
        self.metadata = metadata
        self.currentSnapshot = Self.makeSnapshot(
            metadata: metadata,
            phase: Self.initialPhase(for: metadata),
            localVaultAvailable: Self.isLocalVaultAvailable(access.state),
            remoteVaultAvailable: nil
        )
        reconcilePendingForcedResetForTesting()
    }

    var snapshot: PasswordVaultSyncSnapshot {
        stateLock.withLock { currentSnapshot }
    }
}

extension PasswordVaultSyncService {
    func addObserver(_ observer: @escaping (PasswordVaultSyncSnapshot) -> Void) -> UUID {
        let identifier = UUID()
        let initialSnapshot = stateLock.withLock {
            observers[identifier] = observer
            return currentSnapshot
        }
        callbackDispatcher { observer(initialSnapshot) }
        return identifier
    }

    func removeObserver(_ identifier: UUID) {
        stateLock.withLock { observers.removeValue(forKey: identifier) }
    }

    func record(_ commit: PasswordVaultCommit) {
        if commit.origin == .forcedReset {
            executor.sync { recordOnQueue(commit) }
            return
        }
        executor.async { [weak self] in
            self?.recordOnQueue(commit)
        }
    }

    func synchronize(reason: SyncCoordinator.Reason) {
        executor.async { [weak self] in
            self?.synchronizeOnQueue(remotePassword: nil, completion: nil)
        }
    }

    func prepareForcedReset(previousLocalDigest: String) throws {
        try executor.sync {
            guard !access.requiresForcedResetRecovery else {
                throw PasswordVaultForcedResetError.recoveryRequired
            }
            guard metadata.mode == .oneDrive else { return }
            var candidate = metadata
            candidate.pendingForcedReset = PasswordVaultPendingForcedReset(
                previousLocalDigest: previousLocalDigest,
                replacementLocalDigest: nil,
                didInspectRemote: false,
                observedRemoteDigest: nil,
                archivedRemoteDigest: nil,
                remoteArchiveRequired: nil
            )
            try save(candidate)
            publish(phase: .pendingForcedReset(nil), remoteVaultAvailable: nil)
        }
    }

    func cancelPreparedForcedReset(previousLocalDigest: String) {
        executor.sync {
            guard let pending = metadata.pendingForcedReset,
                  pending.previousLocalDigest == previousLocalDigest,
                  pending.replacementLocalDigest == nil else { return }
            var candidate = metadata
            candidate.pendingForcedReset = nil
            do {
                try save(candidate)
                publish(phase: Self.initialPhase(for: candidate), remoteVaultAvailable: nil)
            } catch {
                publish(phase: .pendingForcedReset(.remoteUnavailable), remoteVaultAvailable: nil)
            }
        }
    }

    func reconcilePendingForcedResetForTesting() {
        executor.sync { reconcilePendingForcedResetOnQueue() }
    }

    // swiftlint:disable inclusive_language
    func enableOneDrive(
        rootURL: URL,
        remoteMasterPassword: String?,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        executor.async { [weak self] in
            guard let self else { return }
            guard !self.access.requiresForcedResetRecovery else {
                self.publish(phase: .failed(.remoteUnavailable), remoteVaultAvailable: nil)
                self.complete(.failure(.remoteUnavailable), completion: completion)
                return
            }
            if let failure = self.rootValidator(rootURL) {
                self.complete(.failure(failure), completion: completion)
                return
            }
            self.rootURLSetter(rootURL)
            var candidate = self.metadata
            candidate.mode = .oneDrive
            candidate.lastFailure = nil
            do {
                try self.save(candidate)
            } catch {
                self.complete(.failure(.remoteWriteFailed), completion: completion)
                return
            }
            self.publish(phase: .syncing(.checking), remoteVaultAvailable: nil)
            self.synchronizeOnQueue(
                remotePassword: remoteMasterPassword,
                completion: completion
            )
        }
    }
    func retry(
        remoteMasterPassword: String,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        executor.async { [weak self] in
            self?.synchronizeOnQueue(
                remotePassword: remoteMasterPassword,
                completion: completion
            )
        }
    }

    func retryForcedReset(
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        executor.async { [weak self] in
            guard let self else { return }
            guard self.metadata.mode == .oneDrive,
                  self.metadata.pendingForcedReset != nil else {
                self.complete(.failure(.remoteUnavailable), completion: completion)
                return
            }
            self.synchronizeOnQueue(
                remotePassword: nil,
                completion: completion,
                allowForcedResetRaceReobservation: true
            )
        }
    }
    // swiftlint:enable inclusive_language

}

private extension PasswordVaultSyncService {
    private func recordOnQueue(_ commit: PasswordVaultCommit) {
        var candidate: PasswordVaultSyncMetadata
        if commit.origin == .migration {
            guard let persisted = try? metadataStore.load() else { return }
            candidate = persisted
        } else {
            candidate = metadata
        }
        switch commit.origin {
        case .forcedReset:
            if candidate.pendingForcedReset?.replacementLocalDigest != commit.encryptedDigest {
                candidate.localRevision &+= 1
            }
            if var pending = candidate.pendingForcedReset {
                pending.replacementLocalDigest = commit.encryptedDigest
                candidate.pendingForcedReset = pending
            }
        case .userMutation:
            candidate.localRevision &+= 1
            if candidate.mode == .oneDrive {
                candidate.pendingChangeCount += 1
            }
        case .syncMerge where candidate.pendingMergedRemoteDigest != nil:
            break
        case .syncMerge, .migration:
            candidate.lastSyncedLocalDigest = commit.encryptedDigest
        }
        do {
            try save(candidate)
            publishCurrentState()
        } catch {
            return
        }
    }

    private func reconcilePendingForcedResetOnQueue() {
        guard let pending = metadata.pendingForcedReset else { return }
        guard !access.requiresForcedResetRecovery else {
            publish(phase: .pendingForcedReset(.remoteUnavailable), remoteVaultAvailable: nil)
            return
        }
        let local: PasswordVaultEncryptedSnapshot
        do {
            local = try access.encryptedSnapshot()
        } catch {
            publish(phase: .pendingForcedReset(.remoteUnavailable), remoteVaultAvailable: nil)
            return
        }

        guard pending.replacementLocalDigest == nil else {
            publish(phase: .pendingForcedReset(nil), remoteVaultAvailable: nil)
            return
        }

        var candidate = metadata
        if local.digest == pending.previousLocalDigest {
            candidate.pendingForcedReset = nil
        } else {
            var committed = pending
            committed.replacementLocalDigest = local.digest
            candidate.pendingForcedReset = committed
        }
        do {
            try save(candidate)
            publish(
                phase: candidate.pendingForcedReset == nil
                    ? Self.initialPhase(for: candidate)
                    : .pendingForcedReset(nil),
                remoteVaultAvailable: nil
            )
        } catch {
            publish(phase: .pendingForcedReset(.remoteUnavailable), remoteVaultAvailable: nil)
        }
    }

    private func synchronizeOnQueue(
        remotePassword: String?,
        completion: ((Result<Void, PasswordVaultSyncFailure>) -> Void)?,
        allowForcedResetRaceReobservation: Bool = false
    ) {
        guard !access.requiresForcedResetRecovery else {
            let phase: PasswordVaultSyncPhase = metadata.pendingForcedReset == nil
                ? .failed(.remoteUnavailable)
                : .pendingForcedReset(.remoteUnavailable)
            publish(phase: phase, remoteVaultAvailable: nil)
            completeIfPresent(.failure(.remoteUnavailable), completion: completion)
            return
        }
        guard metadata.mode == .oneDrive else {
            publish(phase: .disabled, remoteVaultAvailable: nil)
            completeIfPresent(.success(()), completion: completion)
            return
        }
        if let pendingForcedReset = metadata.pendingForcedReset {
            do {
                try resumeForcedReset(
                    pendingForcedReset,
                    allowRaceReobservation: allowForcedResetRaceReobservation
                )
                completeIfPresent(.success(()), completion: completion)
            } catch {
                let failure = Self.syncFailure(from: error)
                failForcedReset(failure, remoteVaultAvailable: nil)
                completeIfPresent(.failure(failure), completion: completion)
            }
            return
        }
        publish(phase: .syncing(.checking), remoteVaultAvailable: nil)
        let rootURL: URL
        do {
            rootURL = try resolvedRootURL()
        } catch {
            let failure = Self.syncFailure(from: error)
            fail(failure, remoteVaultAvailable: nil)
            completeIfPresent(.failure(failure), completion: completion)
            return
        }

        do {
            let local = try access.encryptedSnapshot()
            let remote = try cloudReplica.read(rootURL: rootURL)
            let localChanged = metadata.localRevision != metadata.lastSyncedLocalRevision
                || metadata.lastSyncedLocalDigest != local.digest
                || metadata.pendingChangeCount > 0
            let remoteChanged: Bool
            if let remote {
                remoteChanged = remote.digest != metadata.lastObservedRemoteDigest
            } else {
                remoteChanged = false
            }
            let remoteWasAlreadyMerged = metadata.pendingChangeCount > 0
                && metadata.pendingMergedRemoteDigest == remote?.digest
            let decision = remoteWasAlreadyMerged
                ? PasswordVaultSyncDecision.uploadLocal
                : passwordVaultSyncDecision(
                    localChanged: localChanged || remote == nil,
                    remoteChanged: remoteChanged
                )
            try apply(
                decision,
                local: local,
                remote: remote,
                rootURL: rootURL,
                remotePassword: remotePassword
            )
            completeIfPresent(.success(()), completion: completion)
        } catch {
            let failure = Self.syncFailure(from: error)
            fail(failure, remoteVaultAvailable: nil)
            completeIfPresent(.failure(failure), completion: completion)
        }
    }

    private func resumeForcedReset(
        _ pendingForcedReset: PasswordVaultPendingForcedReset,
        allowRaceReobservation: Bool
    ) throws {
        let rootURL = try resolvedRootURL()
        let local = try access.encryptedSnapshot()
        var pending = pendingForcedReset

        // Before the first remote observation there cannot have been an active CAS.
        // Afterwards the persisted replacement is evidence for a possibly completed CAS,
        // so keep it until the remote snapshot has been classified.
        if !pending.didInspectRemote, pending.replacementLocalDigest != local.digest {
            pending.replacementLocalDigest = local.digest
            try savePendingForcedReset(pending)
        }

        let wasPreviouslyInspected = pending.didInspectRemote
        let previousReplacementDigest = pending.replacementLocalDigest
        let remote = try cloudReplica.read(rootURL: rootURL)
        if !pending.didInspectRemote {
            pending.didInspectRemote = true
            pending.observedRemoteDigest = remote?.digest
            pending.archivedRemoteDigest = nil
            pending.remoteArchiveRequired = remote != nil
            try savePendingForcedReset(pending)

            // Seeing the replacement on the very first inspection cannot prove that an
            // older active vault was archived by this reset. Never archive the replacement
            // itself to manufacture that missing proof.
            if remote?.digest == local.digest {
                throw PasswordVaultSyncFailure.remoteVerificationFailed
            }
        }

        guard pending.remoteArchiveRequired != nil else {
            throw PasswordVaultSyncFailure.remoteVerificationFailed
        }

        if wasPreviouslyInspected,
           let previousReplacementDigest,
           remote?.digest == previousReplacementDigest {
            guard hasDurableForcedResetArchiveProof(pending) else {
                throw PasswordVaultSyncFailure.remoteVerificationFailed
            }

            if previousReplacementDigest == local.digest {
                try finalizeForcedReset(local: local, verifiedRemoteDigest: local.digest)
                return
            }

            // The prior replacement reached active, then the local vault changed again.
            // Advance the durable CAS expectation while retaining proof for the original
            // archived generation.
            pending.observedRemoteDigest = previousReplacementDigest
            pending.replacementLocalDigest = local.digest
            try savePendingForcedReset(pending)
        }

        if remote?.digest != pending.observedRemoteDigest {
            let isConfirmedRace = remote?.digest != previousReplacementDigest
                && remote?.digest != local.digest
            guard allowRaceReobservation, isConfirmedRace else {
                throw PasswordVaultSyncFailure.remoteVerificationFailed
            }
            pending.didInspectRemote = true
            pending.observedRemoteDigest = remote?.digest
            pending.archivedRemoteDigest = nil
            pending.replacementLocalDigest = local.digest
            pending.remoteArchiveRequired = remote != nil
            try savePendingForcedReset(pending)
        } else if pending.replacementLocalDigest != local.digest {
            pending.replacementLocalDigest = local.digest
            try savePendingForcedReset(pending)
        }

        if pending.remoteArchiveRequired == true,
           let remote,
           pending.archivedRemoteDigest == nil {
            let currentArchive = try cloudReplica.readLatestForcedResetArchive(rootURL: rootURL)
            let archiveExpectation: PasswordVaultRemoteExpectation = currentArchive.map {
                .digest($0.digest)
            } ?? .absent
            let archivedDigest = try cloudReplica.writeLatestForcedResetArchiveAtomically(
                remote.data,
                rootURL: rootURL,
                expecting: archiveExpectation
            )
            guard archivedDigest == remote.digest,
                  let archiveReadback = try cloudReplica.readLatestForcedResetArchive(rootURL: rootURL),
                  archiveReadback.digest == remote.digest,
                  archiveReadback.data == remote.data else {
                throw PasswordVaultSyncFailure.remoteVerificationFailed
            }
            pending.archivedRemoteDigest = remote.digest
            try savePendingForcedReset(pending)
        } else if pending.remoteArchiveRequired == true {
            guard hasDurableForcedResetArchiveProof(pending) else {
                throw PasswordVaultSyncFailure.remoteVerificationFailed
            }
        }

        let expectation: PasswordVaultRemoteExpectation = pending.observedRemoteDigest.map {
            .digest($0)
        } ?? .absent
        let writtenDigest = try cloudReplica.writeAtomically(
            local.data,
            rootURL: rootURL,
            expecting: expectation
        )
        guard writtenDigest == local.digest,
              let activeReadback = try cloudReplica.read(rootURL: rootURL),
              activeReadback.digest == local.digest,
              activeReadback.data == local.data else {
            throw PasswordVaultSyncFailure.remoteVerificationFailed
        }
        try finalizeForcedReset(local: local, verifiedRemoteDigest: activeReadback.digest)
    }

    private func hasDurableForcedResetArchiveProof(
        _ pending: PasswordVaultPendingForcedReset
    ) -> Bool {
        guard let remoteArchiveRequired = pending.remoteArchiveRequired else { return false }
        return !remoteArchiveRequired || pending.archivedRemoteDigest != nil
    }

    private func savePendingForcedReset(_ pending: PasswordVaultPendingForcedReset) throws {
        var candidate = metadata
        candidate.pendingForcedReset = pending
        try save(candidate)
    }

    private func finalizeForcedReset(
        local: PasswordVaultEncryptedSnapshot,
        verifiedRemoteDigest: String
    ) throws {
        var candidate = metadata
        candidate.lastSyncedLocalRevision = candidate.localRevision
        candidate.lastSyncedLocalDigest = local.digest
        candidate.lastObservedRemoteDigest = verifiedRemoteDigest
        candidate.pendingMergedRemoteDigest = nil
        candidate.lastSyncAt = now()
        candidate.pendingChangeCount = 0
        candidate.lastFailure = nil
        candidate.pendingForcedReset = nil
        try save(candidate)
        publish(phase: .synced, remoteVaultAvailable: true)
    }

    private func resolvedRootURL() throws -> URL {
        switch processStatus.currentStatus() {
        case .notInstalled:
            throw PasswordVaultSyncFailure.oneDriveNotInstalled
        case .notRunning:
            throw PasswordVaultSyncFailure.oneDriveNotRunning
        case .running:
            break
        }
        guard let rootURL = rootURLProvider() else {
            throw PasswordVaultSyncFailure.folderUnavailable
        }
        if let failure = rootValidator(rootURL) { throw failure }
        return rootURL
    }

    private func apply(
        _ decision: PasswordVaultSyncDecision,
        local: PasswordVaultEncryptedSnapshot,
        remote: PasswordVaultCloudSnapshot?,
        rootURL: URL,
        remotePassword: String?
    ) throws {
        switch decision {
        case .noChange:
            publish(phase: .synced, remoteVaultAvailable: remote != nil)
        case .uploadLocal:
            try upload(local, replacing: remote, rootURL: rootURL)
        case .applyRemote:
            guard let remote else {
                try upload(local, replacing: nil, rootURL: rootURL)
                return
            }
            try mergeRemote(
                remote,
                rootURL: rootURL,
                remotePassword: remotePassword,
                uploadMergedResult: false
            )
        case .mergeBoth:
            guard let remote else {
                try upload(local, replacing: nil, rootURL: rootURL)
                return
            }
            try mergeRemote(
                remote,
                rootURL: rootURL,
                remotePassword: remotePassword,
                uploadMergedResult: true
            )
        }
    }
    private func upload(
        _ local: PasswordVaultEncryptedSnapshot,
        replacing remote: PasswordVaultCloudSnapshot?,
        rootURL: URL
    ) throws {
        publish(phase: .syncing(.uploading), remoteVaultAvailable: remote != nil)
        let expectation: PasswordVaultRemoteExpectation = remote.map {
            .digest($0.digest)
        } ?? .absent
        let verifiedDigest = try cloudReplica.writeAtomically(
            local.data,
            rootURL: rootURL,
            expecting: expectation
        )
        publish(phase: .syncing(.verifying), remoteVaultAvailable: true)
        var candidate = metadata
        candidate.lastSyncedLocalRevision = candidate.localRevision
        candidate.lastSyncedLocalDigest = local.digest
        candidate.lastObservedRemoteDigest = verifiedDigest
        candidate.pendingMergedRemoteDigest = nil
        candidate.lastSyncAt = now()
        candidate.pendingChangeCount = 0
        candidate.lastFailure = nil
        try save(candidate)
        let phase: PasswordVaultSyncPhase = candidate.conflictCopyCount > 0
            ? .conflicts(candidate.conflictCopyCount)
            : .synced
        publish(phase: phase, remoteVaultAvailable: true)
    }

    private func mergeRemote(
        _ remote: PasswordVaultCloudSnapshot,
        rootURL: URL,
        remotePassword: String?,
        uploadMergedResult: Bool
    ) throws {
        guard access.state == .unlocked else {
            publish(phase: .waitingForUnlock, remoteVaultAvailable: true)
            return
        }
        publish(phase: .syncing(.downloading), remoteVaultAvailable: true)
        publish(phase: .syncing(.merging), remoteVaultAvailable: true)
        let application = try access.mergeRemoteSnapshot(
            remote.data,
            remoteMasterPassword: remotePassword
        )
        publish(phase: .syncing(.savingLocal), remoteVaultAvailable: true)

        if uploadMergedResult {
            var pending = metadata
            pending.pendingChangeCount = max(1, pending.pendingChangeCount)
            pending.pendingMergedRemoteDigest = remote.digest
            pending.conflictCopyCount += application.conflictCopyCount
            try save(pending)
            try upload(application.encryptedSnapshot, replacing: remote, rootURL: rootURL)
        } else {
            var candidate = metadata
            candidate.lastSyncedLocalRevision = candidate.localRevision
            candidate.lastSyncedLocalDigest = application.encryptedSnapshot.digest
            candidate.lastObservedRemoteDigest = remote.digest
            candidate.pendingMergedRemoteDigest = nil
            candidate.lastSyncAt = now()
            candidate.pendingChangeCount = 0
            candidate.conflictCopyCount += application.conflictCopyCount
            candidate.lastFailure = nil
            try save(candidate)
            let phase: PasswordVaultSyncPhase = candidate.conflictCopyCount > 0
                ? .conflicts(candidate.conflictCopyCount)
                : .synced
            publish(phase: phase, remoteVaultAvailable: true)
        }
    }
}

private extension PasswordVaultSyncService {
    private func save(_ candidate: PasswordVaultSyncMetadata) throws {
        try metadataStore.save(candidate)
        metadata = candidate
    }

    private func fail(
        _ failure: PasswordVaultSyncFailure,
        remoteVaultAvailable: Bool?
    ) {
        var candidate = metadata
        candidate.lastFailure = failure
        if (try? metadataStore.save(candidate)) != nil {
            metadata = candidate
        }
        let phase: PasswordVaultSyncPhase
        switch failure {
        case .oneDriveNotInstalled, .oneDriveNotRunning, .folderUnavailable, .folderNotWritable:
            phase = .disconnected(failure)
        default:
            phase = .failed(failure)
        }
        publish(phase: phase, remoteVaultAvailable: remoteVaultAvailable)
    }

    private func failForcedReset(
        _ failure: PasswordVaultSyncFailure,
        remoteVaultAvailable: Bool?
    ) {
        var candidate = metadata
        candidate.lastFailure = failure
        if (try? metadataStore.save(candidate)) != nil {
            metadata = candidate
        }
        publish(
            phase: .pendingForcedReset(failure),
            remoteVaultAvailable: remoteVaultAvailable
        )
    }

    private func publishCurrentState() {
        let previous = snapshot
        let phase: PasswordVaultSyncPhase
        if metadata.pendingForcedReset != nil {
            if case let .pendingForcedReset(failure) = previous.phase {
                phase = .pendingForcedReset(failure)
            } else {
                phase = .pendingForcedReset(nil)
            }
        } else {
            phase = metadata.mode == .localOnly ? .disabled : previous.phase
        }
        publish(
            phase: phase,
            remoteVaultAvailable: previous.remoteVaultAvailable
        )
    }

    private func publish(
        phase: PasswordVaultSyncPhase,
        remoteVaultAvailable: Bool?
    ) {
        let next = Self.makeSnapshot(
            metadata: metadata,
            phase: phase,
            localVaultAvailable: Self.isLocalVaultAvailable(access.state),
            remoteVaultAvailable: remoteVaultAvailable
        )
        let callbacks = stateLock.withLock {
            currentSnapshot = next
            return Array(observers.values)
        }
        callbacks.forEach { observer in
            callbackDispatcher { observer(next) }
        }
    }

    private func complete(
        _ result: Result<Void, PasswordVaultSyncFailure>,
        completion: @escaping (Result<Void, PasswordVaultSyncFailure>) -> Void
    ) {
        callbackDispatcher { completion(result) }
    }

    private func completeIfPresent(
        _ result: Result<Void, PasswordVaultSyncFailure>,
        completion: ((Result<Void, PasswordVaultSyncFailure>) -> Void)?
    ) {
        guard let completion else { return }
        complete(result, completion: completion)
    }
}

private extension PasswordVaultSyncService {
    static func makeSnapshot(
        metadata: PasswordVaultSyncMetadata,
        phase: PasswordVaultSyncPhase,
        localVaultAvailable: Bool,
        remoteVaultAvailable: Bool?
    ) -> PasswordVaultSyncSnapshot {
        PasswordVaultSyncSnapshot(
            mode: metadata.mode,
            phase: phase,
            localVaultAvailable: localVaultAvailable,
            remoteVaultAvailable: remoteVaultAvailable,
            pendingChangeCount: metadata.mode == .oneDrive ? metadata.pendingChangeCount : 0,
            conflictCopyCount: metadata.conflictCopyCount,
            lastSyncAt: metadata.lastSyncAt
        )
    }

    static func initialPhase(for metadata: PasswordVaultSyncMetadata) -> PasswordVaultSyncPhase {
        if metadata.pendingForcedReset != nil { return .pendingForcedReset(nil) }
        return metadata.mode == .localOnly ? .disabled : .syncing(.checking)
    }

    static func isLocalVaultAvailable(_ state: PasswordVaultState) -> Bool {
        switch state {
        case .locked, .unlocking, .unlocked, .readOnlyWarning:
            return true
        case .notConfigured, .preparingLocalCopy, .localCopyUnavailable, .recoveryRequired, .failed:
            return false
        }
    }

    static func syncFailure(from error: Error) -> PasswordVaultSyncFailure {
        (error as? PasswordVaultSyncFailure) ?? .remoteWriteFailed
    }
}

// swiftlint:enable file_length
