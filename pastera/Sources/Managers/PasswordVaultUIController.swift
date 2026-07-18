import AppKit
import Foundation
import LocalAuthentication

protocol PasswordVaultAuthorizing {
    func authorize(reason: String, completion: @escaping (Result<Void, PasswordVaultError>) -> Void)
}

final class SystemPasswordVaultAuthorizer: PasswordVaultAuthorizing {
    func authorize(reason: String, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(.failure(.authenticationFailed))
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
            DispatchQueue.main.async {
                if success {
                    completion(.success(()))
                } else if (error as? LAError)?.code == .userCancel || (error as? LAError)?.code == .appCancel {
                    completion(.failure(.userCancelled))
                } else {
                    completion(.failure(.authenticationFailed))
                }
            }
        }
    }
}

final class PasswordVaultUIController {
    private let store: PasswordVaultStore
    private let clipboard: SecureClipboardWriting
    private let authorizer: PasswordVaultAuthorizing
    private let pasteService: PasteService
    private let storeQueue = DispatchQueue(label: "com.pastera.password-vault.store", qos: .userInitiated)
    private let snapshotLock = NSLock()
    private var snapshot: PasswordVaultViewState
    var onChange: (() -> Void)?

    init(
        store: PasswordVaultStore = AppEnvironment.current.passwordVaultStore,
        clipboard: SecureClipboardWriting = AppEnvironment.current.secureClipboard,
        authorizer: PasswordVaultAuthorizing = SystemPasswordVaultAuthorizer(),
        pasteService: PasteService = AppEnvironment.current.pasteService
    ) {
        self.store = store
        self.clipboard = clipboard
        self.authorizer = authorizer
        self.pasteService = pasteService
        snapshot = PasswordVaultViewState(state: store.state)
        refreshSnapshotFromStore()
    }

    func folders() throws -> [PasswordVaultFolder] { currentSnapshot.folders }
    func entries() throws -> [PasswordVaultEntry] { currentSnapshot.entries }
    var state: PasswordVaultState {
        currentSnapshot.isBusy ? .unlocking : store.state
    }
    var viewState: PasswordVaultViewState { currentSnapshot }

    func checkQuickUnlockAvailability(completion: @escaping (Bool) -> Void) {
        storeQueue.async { [weak self] in
            guard let self else { return }
            let isAvailable = self.store.canQuickUnlock
            DispatchQueue.main.async { completion(isAvailable) }
        }
    }

    func createDatabase(
        masterPassword: String,
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) {
        performLifecycle(completion: completion) {
            try self.store.createDatabase(masterPassword: masterPassword, rememberQuickUnlock: true)
        }
    }

    func unlock(masterPassword: String, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        performLifecycle(completion: completion) {
            try self.store.unlock(masterPassword: masterPassword, rememberQuickUnlock: true)
        }
    }

    func unlockWithQuickKey(completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        performLifecycle(completion: completion) {
            try self.store.unlockWithQuickKey(reason: String(localized: "Authenticate to unlock the password database."))
        }
    }
    func createFolder(name: String, completion: @escaping (Result<PasswordVaultFolder, PasswordVaultError>) -> Void) {
        perform(completion: completion) { try self.store.createFolder(name: name) }
    }

    func renameFolder(id: UUID, name: String, completion: @escaping (Result<PasswordVaultFolder, PasswordVaultError>) -> Void) {
        perform(completion: completion) { try self.store.renameFolder(id: id, name: name) }
    }

    func deleteFolder(id: UUID, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        perform(completion: completion) { try self.store.deleteFolder(id: id) }
    }

    func moveEntry(id: UUID, to folderID: UUID, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        perform(completion: completion) { try self.store.moveEntry(id: id, to: folderID) }
    }

    func reorderFolders(_ folderIDs: [UUID], completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        perform(completion: completion) { try self.store.reorderFolders(folderIDs) }
    }

    func moveEntry(
        id: UUID,
        to folderID: UUID,
        orderedEntryIDsByFolder: [UUID: [UUID]],
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void
    ) {
        perform(completion: completion) {
            try self.store.moveEntry(
                id: id,
                to: folderID,
                orderedEntryIDsByFolder: orderedEntryIDsByFolder
            )
        }
    }

    private func performLifecycle(
        completion: @escaping (Result<Void, PasswordVaultError>) -> Void,
        operation: @escaping () throws -> Void
    ) {
        publishBusyState()
        storeQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<Void, PasswordVaultError>
            do { try operation(); result = .success(()) }
            catch let error as PasswordVaultError { result = .failure(error) }
            catch { result = .failure(.corruptedData) }
            self.finish(result, completion: completion)
        }
    }

    func createEntry(_ draft: PasswordVaultDraft, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        authorize(reason: String(localized: "Authenticate to save this password."), completion: completion) {
            _ = try self.store.create(draft)
        }
    }

    func loadDraft(id: UUID, completion: @escaping (Result<PasswordVaultDraft, PasswordVaultError>) -> Void) {
        authorize(reason: String(localized: "Authenticate to view or edit this password."), completion: completion) {
            guard let entry = try self.store.listEntries().first(where: { $0.id == id }) else {
                throw PasswordVaultError.entryNotFound
            }
            let password = try self.store.revealPassword(
                id: id,
                reason: String(localized: "Authenticate to view or edit this password.")
            )
            return PasswordVaultDraft(
                folderID: entry.folderID,
                title: entry.title,
                website: entry.website,
                username: entry.username,
                note: entry.note,
                password: password
            )
        }
    }

    func updateEntry(id: UUID, draft: PasswordVaultDraft, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        authorize(reason: String(localized: "Authenticate to save this password."), completion: completion) {
            _ = try self.store.update(id: id, draft: draft)
        }
    }

    func copyPassword(id: UUID, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        authorize(reason: String(localized: "Authenticate to copy this password."), completion: completion) {
            let password = try self.store.revealPassword(
                id: id,
                reason: String(localized: "Authenticate to copy this password.")
            )
            self.clipboard.copySecret(password, clearAfter: .seconds(60))
        }
    }

    func pasteUsername(id: UUID, targetContext: PasteTargetContext?, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        perform(completion: completion) {
            guard let entry = try self.store.listEntries().first(where: { $0.id == id }) else {
                throw PasswordVaultError.entryNotFound
            }
            guard !entry.username.isEmpty else { throw PasswordVaultError.invalidUsername }
            DispatchQueue.main.async { self.pasteService.pasteText(entry.username, restoring: targetContext) }
        }
    }

    func pastePassword(id: UUID, targetContext: PasteTargetContext?, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        authorize(reason: String(localized: "Authenticate to paste this password."), completion: completion) {
            let password = try self.store.revealPassword(id: id, reason: String(localized: "Authenticate to paste this password."))
            self.clipboard.copySecret(password, clearAfter: .seconds(60))
            DispatchQueue.main.async { self.pasteService.paste(restoring: targetContext) }
        }
    }

    func deleteEntry(id: UUID, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        authorize(reason: String(localized: "Authenticate to delete this password."), completion: completion) {
            try self.store.delete(id: id, reason: String(localized: "Authenticate to delete this password."))
        }
    }

    private func authorize<T>(
        reason: String,
        completion: @escaping (Result<T, PasswordVaultError>) -> Void,
        operation: @escaping () throws -> T
    ) {
        authorizer.authorize(reason: reason) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.perform(completion: completion, operation: operation)
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    private func perform<T>(
        completion: @escaping (Result<T, PasswordVaultError>) -> Void,
        operation: @escaping () throws -> T
    ) {
        publishBusyState()
        storeQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<T, PasswordVaultError>
            do { result = .success(try operation()) }
            catch let error as PasswordVaultError { result = .failure(error) }
            catch { result = .failure(.keychainUnavailable) }
            self.finish(result, completion: completion)
        }
    }

    private var currentSnapshot: PasswordVaultViewState {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshot
    }

    private func publishBusyState() {
        let current = currentSnapshot
        setSnapshot(PasswordVaultViewState(
            state: .unlocking,
            folders: current.folders,
            entries: current.entries,
            isBusy: true,
            error: nil
        ))
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    private func refreshSnapshotFromStore(error: PasswordVaultError? = nil) {
        let state = store.state
        let folders = (state == .unlocked || state.isReadableWarning) ? (try? store.listFolders()) ?? [] : []
        let entries = (state == .unlocked || state.isReadableWarning) ? (try? store.listEntries()) ?? [] : []
        setSnapshot(.init(state: state, folders: folders, entries: entries, isBusy: false, error: error))
    }

    private func setSnapshot(_ value: PasswordVaultViewState) {
        snapshotLock.lock()
        snapshot = value
        snapshotLock.unlock()
    }

    private func finish<T>(
        _ result: Result<T, PasswordVaultError>,
        completion: @escaping (Result<T, PasswordVaultError>) -> Void
    ) {
        let error: PasswordVaultError?
        if case let .failure(value) = result { error = value } else { error = nil }
        refreshSnapshotFromStore(error: error)
        DispatchQueue.main.async { completion(result) }
    }
}

private extension PasswordVaultState {
    var isReadableWarning: Bool {
        if case .readOnlyWarning = self { return true }
        return false
    }
}
