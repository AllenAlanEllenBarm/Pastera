import AppKit
import Foundation
import PasteraAgentProtocol
import Security
import Testing
@testable import Pastera

@Suite("Vault automation unlock key store")
struct VaultAutomationUnlockKeyStoreTests {
    @Test("automation key uses a distinct noninteractive local Keychain item")
    func automationKeyUsesDistinctNoninteractiveItem() throws {
        let client = VaultAutomationKeychainProbe()
        client.updateStatuses = [errSecItemNotFound]
        let store = VaultAutomationUnlockKeyStore(client: client, usesDataProtectionKeychain: true)
        let key = Data(repeating: 0x2A, count: 32)

        try store.save(key)

        let query = try #require(client.updateQueries.first)
        let attributes = try #require(client.updateAttributes.first)
        let added = try #require(client.addQueries.first)
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "com.pastera-app.Pastera.password-vault.agent-unlock.v1")
        #expect(query[kSecAttrAccount as String] as? String == "PasteraVaultAgentUnlock")
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(attributes[kSecValueData as String] as? Data == key)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(added[kSecValueData as String] as? Data == key)
        #expect(added[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(added[kSecAttrAccessControl as String] == nil)
    }

    @Test("an existing automation key is updated without a delete or add window")
    func existingKeyUpdatesInPlace() throws {
        let client = VaultAutomationKeychainProbe()
        client.updateStatuses = [errSecSuccess]
        let store = VaultAutomationUnlockKeyStore(client: client, usesDataProtectionKeychain: true)

        try store.save(Data(repeating: 0x11, count: 32))

        #expect(client.updateQueries.count == 1)
        #expect(client.addQueries.isEmpty)
        #expect(client.deleteQueries.isEmpty)
    }

    @Test("automation key save adds only after item-not-found")
    func saveAddsOnlyAfterItemNotFound() {
        let client = VaultAutomationKeychainProbe()
        client.updateStatuses = [errSecAuthFailed]
        let store = VaultAutomationUnlockKeyStore(client: client)

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try store.save(Data(repeating: 0x11, count: 32))
        }
        #expect(client.addQueries.isEmpty)
        #expect(client.deleteQueries.isEmpty)
    }

    @Test("automation key rejects malformed values before Keychain access")
    func malformedValuesAreRejected() {
        let client = VaultAutomationKeychainProbe()
        let store = VaultAutomationUnlockKeyStore(client: client)

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try store.save(Data(repeating: 0x11, count: 31))
        }
        #expect(client.updateQueries.isEmpty)

        client.copyStatus = errSecSuccess
        client.copyResult = Data(repeating: 0x11, count: 33) as CFData
        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try store.load()
        }
    }

    @Test("containsKey checks existence without returning secret data")
    func availabilityDoesNotReadSecretData() {
        let client = VaultAutomationKeychainProbe()
        client.copyStatus = errSecSuccess
        let store = VaultAutomationUnlockKeyStore(client: client)

        #expect(store.containsKey)
        let query = client.copyQueries.first
        #expect(query?[kSecReturnData as String] == nil)
        #expect(query?[kSecUseAuthenticationContext as String] == nil)
        #expect(query?[kSecAttrAccessControl as String] == nil)
        #expect(query?[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
    }

    @Test("load returns only an exact 32 byte automation key")
    func loadReturnsExactKey() throws {
        let client = VaultAutomationKeychainProbe()
        let expected = Data(repeating: 0x55, count: 32)
        client.copyStatus = errSecSuccess
        client.copyResult = expected as CFData
        let store = VaultAutomationUnlockKeyStore(client: client, usesDataProtectionKeychain: true)

        #expect(try store.load() == expected)
        let query = try #require(client.copyQueries.first)
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecAttrAccessible as String] == nil)
        #expect(query[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    @Test("ad-hoc builds omit the unavailable Data Protection Keychain selector")
    func adHocBuildUsesLegacyKeychain() {
        let client = VaultAutomationKeychainProbe()
        client.copyStatus = errSecItemNotFound
        let store = VaultAutomationUnlockKeyStore(client: client, usesDataProtectionKeychain: false)

        _ = store.containsKey
        #expect(client.copyQueries.first?[kSecUseDataProtectionKeychain as String] == nil)
    }

    @Test("load maps missing and Keychain errors to unavailable")
    func loadMapsErrors() {
        for status in [errSecItemNotFound, errSecAuthFailed] {
            let client = VaultAutomationKeychainProbe()
            client.copyStatus = status
            let store = VaultAutomationUnlockKeyStore(client: client)

            #expect(throws: PasswordVaultError.keychainUnavailable) {
                try store.load()
            }
        }
    }

    @Test("delete is idempotent but preserves other Keychain failures")
    func deleteStatusMapping() throws {
        for status in [errSecSuccess, errSecItemNotFound] {
            let client = VaultAutomationKeychainProbe()
            client.deleteStatus = status
            try VaultAutomationUnlockKeyStore(client: client).delete()
            #expect(client.deleteQueries.count == 1)
        }

        let client = VaultAutomationKeychainProbe()
        client.deleteStatus = errSecAuthFailed
        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try VaultAutomationUnlockKeyStore(client: client).delete()
        }
    }

    @Test("failed automation unlock clears old secrets and cannot re-enable")
    func failedAutomationUnlockClearsOldSecrets() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let automation = AgentAutomationUnlockKeyStore()
        let store = KDBXPasswordVaultStore(
            syncRootProvider: { root },
            automationUnlockKeyStore: automation
        )
        try store.createDatabase(masterPassword: "master", rememberQuickUnlock: false)
        let folder = try store.createFolder(name: "Work")
        let entry = try store.create(.init(
            folderID: folder.id,
            title: "Mail",
            website: "",
            username: "alice",
            note: "",
            password: "secret-value"
        ))
        try store.enableAutomationUnlock()
        let saveCountBeforeFailure = automation.saveCallCount
        automation.data = Data(repeating: 0x7F, count: 32)

        #expect(throws: PasswordVaultError.keychainUnavailable) {
            try store.unlockForAutomation()
        }

        #expect(store.state == .locked)
        #expect(throws: PasswordVaultError.vaultLocked) { try store.listEntries() }
        #expect(throws: PasswordVaultError.vaultLocked) {
            try store.revealPassword(id: entry.id, reason: "test")
        }
        #expect(throws: PasswordVaultError.vaultLocked) {
            try store.enableAutomationUnlock()
        }
        #expect(automation.saveCallCount == saveCountBeforeFailure)
    }

    @Test("a cancelled session timer cannot lock a newer session")
    func cancelledSessionTimerCannotLockNewSession() throws {
        var scheduledActions = [() -> Void]()
        var lockCount = 0
        let session = VaultSessionController(
            timeoutProvider: { 300 },
            notificationCenter: NotificationCenter(),
            timerScheduler: { _, action in
                scheduledActions.append(action)
                return {}
            },
            lockAction: { lockCount += 1 }
        )

        session.touch()
        session.cancel()
        session.touch()
        #expect(scheduledActions.count == 2)

        let firstAction = try #require(scheduledActions.first)
        firstAction()
        #expect(lockCount == 0)
        let latestAction = try #require(scheduledActions.last)
        latestAction()
        #expect(lockCount == 1)
    }
}

@MainActor
@Suite("Password vault agent access", .serialized)
struct PasswordVaultAgentAccessTests {
    @Test("agent access restores with automation and never uses UI authorization or interactive renewal")
    func agentAccessUsesAutomationWithoutInteractivePaths() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let automation = AgentAutomationUnlockKeyStore()
        let store = KDBXPasswordVaultStore(
            syncRootProvider: { root },
            automationUnlockKeyStore: automation
        )
        try store.createDatabase(masterPassword: "agent-password", rememberQuickUnlock: false)
        let folder = try store.createFolder(name: "Work")
        let entry = try store.create(.init(
            folderID: folder.id,
            title: "Mail",
            website: "https://mail.example.com",
            username: "alice",
            note: "",
            password: "secret-value"
        ))
        try store.enableAutomationUnlock()
        store.lock()
        let authorizer = AgentCountingAuthorizer(result: .failure(.authenticationFailed))
        let clipboard = AgentClipboardProbe()
        var pasteCommands = 0
        let pasteService = makeAgentPasteService(pasteCommands: { pasteCommands += 1 })
        let storeQueue = DispatchQueue(label: "PasswordVaultAgentAccessTests.agent.store")
        let controller = PasswordVaultUIController(
            store: store,
            clipboard: clipboard,
            authorizer: authorizer,
            pasteService: pasteService,
            storeQueue: storeQueue
        )
        var interactiveRenewals = 0
        controller.onInteractiveSensitiveUse = { interactiveRenewals += 1 }
        var readyChanges = 0
        var readyChangeWasOffMain = false
        controller.onChange = {
            readyChanges += 1
            readyChangeWasOffMain = readyChangeWasOffMain || !Thread.isMainThread
        }

        try await vaultAgentResult(controller.ensureReadyForAgent).get()
        #expect(readyChanges == 1)
        #expect(!readyChangeWasOffMain)
        let metadata = try await vaultAgentResult(controller.agentMetadata).get()
        let username = try await vaultAgentResult { completion in
            controller.agentSecret(entryID: entry.id, field: .username, completion: completion)
        }.get()
        let password = try await vaultAgentResult { completion in
            controller.agentSecret(entryID: entry.id, field: .password, completion: completion)
        }.get()
        let target = PasteTargetContext(
            processIdentifier: 4242,
            bundleIdentifier: "com.example.target",
            application: nil,
            focusedElement: nil
        )
        try await vaultAgentResult { completion in
            controller.agentPaste(entryID: entry.id, field: .password, target: target, completion: completion)
        }.get()
        await waitForAgentCondition("agent paste dispatched") { pasteCommands == 1 }

        #expect(store.state == .unlocked)
        #expect(metadata.0.map(\.id) == [folder.id])
        #expect(metadata.1.map(\.id) == [entry.id])
        #expect(username == Data("alice".utf8))
        #expect(password == Data("secret-value".utf8))
        #expect(clipboard.value == "secret-value")
        #expect(authorizer.callCount == 0)
        #expect(interactiveRenewals == 0)
    }

    @Test("interactive sensitive successes renew exactly once on the shared store queue")
    func interactiveSensitiveSuccessesRenewExactlyOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = KDBXPasswordVaultStore(syncRootProvider: { root })
        try store.createDatabase(masterPassword: "ui-password", rememberQuickUnlock: false)
        store.lock()
        let queueKey = DispatchSpecificKey<Int>()
        let storeQueue = DispatchQueue(label: "PasswordVaultAgentAccessTests.interactive.store")
        storeQueue.setSpecific(key: queueKey, value: 1)
        let controller = PasswordVaultUIController(
            store: store,
            clipboard: AgentClipboardProbe(),
            authorizer: AgentAllowAuthorizer(),
            pasteService: makeAgentPasteService(pasteCommands: {}),
            storeQueue: storeQueue
        )
        var renewals = 0
        var renewedOffQueue = false
        controller.onInteractiveSensitiveUse = {
            renewals += 1
            renewedOffQueue = renewedOffQueue || DispatchQueue.getSpecific(key: queueKey) != 1
        }

        try await vaultAgentResult { completion in
            controller.unlock(masterPassword: "ui-password", completion: completion)
        }.get()
        let folder = try await vaultAgentResult { completion in
            controller.createFolder(name: "Work", completion: completion)
        }.get()
        #expect(renewals == 0)

        try await vaultAgentResult { completion in
            controller.createEntry(.init(
                folderID: folder.id,
                title: "Mail",
                website: "",
                username: "alice",
                note: "",
                password: "secret"
            ), completion: completion)
        }.get()
        let entry = try #require(controller.entries().first)
        #expect(renewals == 1)

        _ = try await vaultAgentResult { completion in
            controller.loadDraft(id: entry.id, completion: completion)
        }.get()
        #expect(renewals == 1)
        try await vaultAgentResult { completion in
            controller.updateEntry(id: entry.id, draft: .init(
                folderID: folder.id,
                title: "Mail",
                website: "",
                username: "bob",
                note: "",
                password: "updated"
            ), completion: completion)
        }.get()
        try await vaultAgentResult { completion in controller.copyPassword(id: entry.id, completion: completion) }.get()
        try await vaultAgentResult { completion in
            controller.pasteUsername(id: entry.id, targetContext: nil, completion: completion)
        }.get()
        try await vaultAgentResult { completion in
            controller.pastePassword(id: entry.id, targetContext: nil, completion: completion)
        }.get()
        #expect(renewals == 5)

        let failedDelete = await vaultAgentResult { completion in
            controller.deleteEntry(id: UUID(), completion: completion)
        }
        #expect(throws: PasswordVaultError.entryNotFound) { try failedDelete.get() }
        #expect(renewals == 5)
        try await vaultAgentResult { completion in
            controller.deleteEntry(id: entry.id, completion: completion)
        }.get()

        #expect(renewals == 6)
        #expect(!renewedOffQueue)
    }

    @Test("session auto-lock waits behind the shared agent executor")
    func sessionAutoLockUsesSharedExecutor() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sessionNotificationCenter = NotificationCenter()
        let store = KDBXPasswordVaultStore(
            syncRootProvider: { root },
            sessionNotificationCenter: sessionNotificationCenter
        )
        try store.createDatabase(masterPassword: "session-password", rememberQuickUnlock: false)
        let storeQueue = DispatchQueue(label: "PasswordVaultAgentAccessTests.session.store")
        let controller = PasswordVaultUIController(store: store, storeQueue: storeQueue)
        let blockerEntered = DispatchSemaphore(value: 0)
        let releaseBlocker = DispatchSemaphore(value: 0)
        defer { releaseBlocker.signal() }
        storeQueue.async {
            blockerEntered.signal()
            releaseBlocker.wait()
        }
        #expect(blockerEntered.wait(timeout: .now() + 1) == .success)

        sessionNotificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)

        #expect(store.state == .unlocked)
        releaseBlocker.signal()
        controller.vaultAgentExecutor.sync {}
        #expect(store.state == .locked)
    }

    @Test("mandatory system lock survives metadata queued ahead of it")
    func mandatorySystemLockSurvivesQueuedMetadataTouch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sessionNotificationCenter = NotificationCenter()
        let store = KDBXPasswordVaultStore(
            syncRootProvider: { root },
            sessionNotificationCenter: sessionNotificationCenter
        )
        try store.createDatabase(masterPassword: "session-password", rememberQuickUnlock: false)
        let storeQueue = DispatchQueue(label: "PasswordVaultAgentAccessTests.mandatory-lock.store")
        let controller = PasswordVaultUIController(store: store, storeQueue: storeQueue)
        let blockerEntered = DispatchSemaphore(value: 0)
        let releaseBlocker = DispatchSemaphore(value: 0)
        defer { releaseBlocker.signal() }
        storeQueue.async {
            blockerEntered.signal()
            releaseBlocker.wait()
        }
        #expect(blockerEntered.wait(timeout: .now() + 1) == .success)

        controller.agentMetadata { _ in }
        sessionNotificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        releaseBlocker.signal()
        controller.vaultAgentExecutor.sync {}

        #expect(store.state == .locked)
    }

    @Test("controller state reads only its snapshot")
    func controllerStateReadsOnlySnapshot() {
        let store = AgentStateCountingStore(state: .locked)
        let controller = PasswordVaultUIController(
            store: store,
            storeQueue: DispatchQueue(label: "PasswordVaultAgentAccessTests.snapshot.store")
        )
        store.resetStateReadCount()

        #expect(controller.state == .locked)
        #expect(store.stateReadCount == 0)
    }

    @Test("session lock refreshes controller snapshot and notifies on main")
    func sessionLockRefreshesControllerSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sessionNotificationCenter = NotificationCenter()
        let store = KDBXPasswordVaultStore(
            syncRootProvider: { root },
            sessionNotificationCenter: sessionNotificationCenter
        )
        try store.createDatabase(masterPassword: "session-password", rememberQuickUnlock: false)
        let controller = PasswordVaultUIController(
            store: store,
            storeQueue: DispatchQueue(label: "PasswordVaultAgentAccessTests.snapshot-lock.store")
        )
        var changeCount = 0
        var changeWasOffMain = false
        controller.onChange = {
            changeCount += 1
            changeWasOffMain = changeWasOffMain || !Thread.isMainThread
        }

        sessionNotificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
        controller.vaultAgentExecutor.sync {}
        await waitForAgentCondition("session lock snapshot refresh", timeout: 1) {
            controller.viewState.state == .locked && changeCount == 1
        }

        #expect(controller.state == .locked)
        #expect(changeCount == 1)
        #expect(!changeWasOffMain)
    }

    @Test("an unbound store still handles session auto-lock")
    func unboundStoreSessionAutoLock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let sessionNotificationCenter = NotificationCenter()
        let store = KDBXPasswordVaultStore(
            syncRootProvider: { root },
            sessionNotificationCenter: sessionNotificationCenter
        )
        try store.createDatabase(masterPassword: "session-password", rememberQuickUnlock: false)

        sessionNotificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)

        #expect(store.state == .locked)
    }

    @Test("an initialized MenuManager follows environment push replace and pop")
    func initializedMenuManagerFollowsEnvironmentStack() {
        let firstStore = KDBXPasswordVaultStore(syncRootProvider: { nil })
        let secondStore = KDBXPasswordVaultStore(syncRootProvider: { nil })
        let thirdStore = KDBXPasswordVaultStore(syncRootProvider: { nil })
        let firstController = PasswordVaultUIController(store: firstStore)
        let secondController = PasswordVaultUIController(store: secondStore)
        let thirdController = PasswordVaultUIController(store: thirdStore)
        let firstEnvironment = Environment(
            passwordVaultStore: firstStore,
            passwordVaultUIController: firstController
        )
        let secondEnvironment = Environment(
            passwordVaultStore: secondStore,
            passwordVaultUIController: secondController
        )
        let thirdEnvironment = Environment(
            passwordVaultStore: thirdStore,
            passwordVaultUIController: thirdController
        )
        AppEnvironment.push(environment: firstEnvironment)
        defer { AppEnvironment.popLast() }
        let menuManager = MenuManager()

        #expect(menuManager.passwordVaultUIController === firstController)
        #expect(firstController.onChange != nil)

        AppEnvironment.push(environment: secondEnvironment)
        #expect(menuManager.passwordVaultUIController === secondController)
        #expect(firstController.onChange == nil)
        #expect(secondController.onChange != nil)

        AppEnvironment.replaceCurrent(environment: thirdEnvironment)
        #expect(menuManager.passwordVaultUIController === thirdController)
        #expect(secondController.onChange == nil)
        #expect(thirdController.onChange != nil)

        _ = AppEnvironment.popLast()
        #expect(menuManager.passwordVaultUIController === firstController)
        #expect(firstController.onChange != nil)
        #expect(thirdController.onChange == nil)
    }
}

private final class AgentAutomationUnlockKeyStore: VaultAutomationUnlockKeyStoring {
    var data: Data?
    private(set) var saveCallCount = 0
    var containsKey: Bool { data != nil }

    func save(_ data: Data) throws {
        saveCallCount += 1
        self.data = data
    }
    func load() throws -> Data {
        guard let data else { throw PasswordVaultError.keychainUnavailable }
        return data
    }
    func delete() throws { data = nil }
}

private final class AgentCountingAuthorizer: PasswordVaultAuthorizing {
    private let result: Result<Void, PasswordVaultError>
    private(set) var callCount = 0

    init(result: Result<Void, PasswordVaultError>) {
        self.result = result
    }

    func authorize(reason: String, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        callCount += 1
        completion(result)
    }
}

private final class AgentAllowAuthorizer: PasswordVaultAuthorizing {
    func authorize(reason: String, completion: @escaping (Result<Void, PasswordVaultError>) -> Void) {
        completion(.success(()))
    }
}

private final class AgentClipboardProbe: SecureClipboardWriting {
    var value: String?

    func copySecret(_ secret: String, clearAfter: Duration) { value = secret }
}

private final class AgentStateCountingStore: PasswordVaultStore {
    private let storedState: PasswordVaultState
    private(set) var stateReadCount = 0

    init(state: PasswordVaultState) {
        storedState = state
    }

    var state: PasswordVaultState {
        stateReadCount += 1
        return storedState
    }

    func resetStateReadCount() { stateReadCount = 0 }
    func listFolders() throws -> [PasswordVaultFolder] { [] }
    func listEntries() throws -> [PasswordVaultEntry] { [] }
    func createFolder(name: String) throws -> PasswordVaultFolder { throw PasswordVaultError.unsupportedFormat }
    func renameFolder(id: UUID, name: String) throws -> PasswordVaultFolder { throw PasswordVaultError.unsupportedFormat }
    func deleteFolder(id: UUID) throws { throw PasswordVaultError.unsupportedFormat }
    func reorderFolders(_ folderIDs: [UUID]) throws { throw PasswordVaultError.unsupportedFormat }
    func moveEntry(id: UUID, to folderID: UUID) throws { throw PasswordVaultError.unsupportedFormat }
    func moveEntry(id: UUID, to folderID: UUID, orderedEntryIDsByFolder: [UUID: [UUID]]) throws {
        throw PasswordVaultError.unsupportedFormat
    }
    func create(_ draft: PasswordVaultDraft) throws -> PasswordVaultEntry { throw PasswordVaultError.unsupportedFormat }
    func update(id: UUID, draft: PasswordVaultDraft) throws -> PasswordVaultEntry {
        throw PasswordVaultError.unsupportedFormat
    }
    func revealPassword(id: UUID, reason: String) throws -> String { throw PasswordVaultError.unsupportedFormat }
    func delete(id: UUID, reason: String) throws { throw PasswordVaultError.unsupportedFormat }
}

@MainActor
private func vaultAgentResult<Value>(
    _ start: (@escaping (Result<Value, PasswordVaultError>) -> Void) -> Void
) async -> Result<Value, PasswordVaultError> {
    await withCheckedContinuation { continuation in
        start { continuation.resume(returning: $0) }
    }
}

@MainActor
private func waitForAgentCondition(
    _ label: String,
    timeout: TimeInterval = 5,
    condition: () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition(), Comment(rawValue: label))
}

@MainActor
private func makeAgentPasteService(pasteCommands: @escaping () -> Void) -> PasteService {
    let pasteboard = NSPasteboard(name: .init("PasswordVaultAgentAccessTests.paste.\(UUID().uuidString)"))
    return PasteService(
        inputPasteCommandEnabledProvider: { true },
        accessibilityEnabledProvider: { true },
        accessibilityAlertPresenter: {},
        frontmostProcessIdentifierProvider: { 4242 },
        targetApplicationActivator: { _ in },
        focusedElementRestorer: { _ in },
        pasteCommandSender: pasteCommands,
        secureEventInputEnabledProvider: { false },
        clipboardScriptCoordinatorProvider: { nil },
        pasteboardProvider: { pasteboard },
        scheduleAfter: { _, work in work() }
    )
}

private final class VaultAutomationKeychainProbe: VaultAutomationKeychainAccessing {
    var copyStatus = errSecItemNotFound
    var copyResult: CFTypeRef?
    var updateStatuses = [OSStatus]()
    var addStatus = errSecSuccess
    var deleteStatus = errSecSuccess
    private(set) var copyQueries = [[String: Any]]()
    private(set) var updateQueries = [[String: Any]]()
    private(set) var updateAttributes = [[String: Any]]()
    private(set) var addQueries = [[String: Any]]()
    private(set) var deleteQueries = [[String: Any]]()

    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        copyQueries.append(query)
        return (copyStatus, copyResult)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        updateQueries.append(query)
        updateAttributes.append(attributes)
        return updateStatuses.removeFirst()
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        addQueries.append(attributes)
        return addStatus
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        deleteQueries.append(query)
        return deleteStatus
    }
}
