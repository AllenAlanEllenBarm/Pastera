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
    var onChange: (() -> Void)?

    init(
        store: PasswordVaultStore = AppEnvironment.current.passwordVaultStore,
        clipboard: SecureClipboardWriting = AppEnvironment.current.secureClipboard,
        authorizer: PasswordVaultAuthorizing = SystemPasswordVaultAuthorizer()
    ) {
        self.store = store
        self.clipboard = clipboard
        self.authorizer = authorizer
    }

    func folders() throws -> [PasswordVaultFolder] { try store.listFolders() }
    func entries() throws -> [PasswordVaultEntry] { try store.listEntries() }
    func createFolder(name: String) throws -> PasswordVaultFolder { try store.createFolder(name: name) }
    func renameFolder(id: UUID, name: String) throws -> PasswordVaultFolder { try store.renameFolder(id: id, name: name) }
    func deleteFolder(id: UUID) throws { try store.deleteFolder(id: id) }
    func moveEntry(id: UUID, to folderID: UUID) throws { try store.moveEntry(id: id, to: folderID) }

    func createEntry(_ draft: PasswordVaultDraft, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        authorize(reason: String(localized: "Authenticate to save this password."), completion: completion) {
            _ = try self.store.create(draft)
        }
    }

    func loadDraft(id: UUID, completion: @escaping (Result<PasswordVaultDraft, PasswordVaultError>) -> Void) {
        perform(completion: completion) {
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
        perform(completion: completion) {
            _ = try self.store.update(id: id, draft: draft)
        }
    }

    func copyPassword(id: UUID, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        perform(completion: completion) {
            let password = try self.store.revealPassword(
                id: id,
                reason: String(localized: "Authenticate to copy this password.")
            )
            self.clipboard.copySecret(password, clearAfter: .seconds(60))
        }
    }

    func deleteEntry(id: UUID, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        perform(completion: completion) {
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
                do {
                    let value = try operation()
                    self.onChange?()
                    completion(.success(value))
                } catch let error as PasswordVaultError {
                    completion(.failure(error))
                } catch {
                    completion(.failure(.keychainUnavailable))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    private func perform<T>(
        completion: @escaping (Result<T, PasswordVaultError>) -> Void,
        operation: () throws -> T
    ) {
        do {
            let value = try operation()
            onChange?()
            completion(.success(value))
        } catch let error as PasswordVaultError {
            completion(.failure(error))
        } catch {
            completion(.failure(.keychainUnavailable))
        }
    }
}
