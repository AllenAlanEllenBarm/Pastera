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
        let store = VaultAutomationUnlockKeyStore(client: client)
        let key = Data(repeating: 0x2A, count: 32)

        try store.save(key)

        let query = try #require(client.updateQueries.first)
        let attributes = try #require(client.updateAttributes.first)
        let added = try #require(client.addQueries.first)
        #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(query[kSecAttrService as String] as? String == "com.pastera-app.Pastera.password-vault.agent-unlock.v1")
        #expect(query[kSecAttrAccount as String] as? String == "PasteraVaultAgentUnlock")
        #expect(query[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(attributes[kSecValueData as String] as? Data == key)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(added[kSecValueData as String] as? Data == key)
        #expect(added[kSecAttrAccessControl as String] == nil)
    }

    @Test("an existing automation key is updated without a delete or add window")
    func existingKeyUpdatesInPlace() throws {
        let client = VaultAutomationKeychainProbe()
        client.updateStatuses = [errSecSuccess]
        let store = VaultAutomationUnlockKeyStore(client: client)

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
        let store = VaultAutomationUnlockKeyStore(client: client)

        #expect(try store.load() == expected)
        let query = try #require(client.copyQueries.first)
        #expect(query[kSecReturnData as String] as? Bool == true)
        #expect(query[kSecAttrAccessible as String] == nil)
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

        try await vaultAgentResult(controller.ensureReadyForAgent).get()
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
}

private final class AgentAutomationUnlockKeyStore: VaultAutomationUnlockKeyStoring {
    var data: Data?
    var containsKey: Bool { data != nil }

    func save(_ data: Data) throws { self.data = data }
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
