import Foundation
import Security
import Testing
@testable import Pastera

struct PromptOptimizationSettingsTests {
    @Test
    func defaultsToFreeAutomaticWithoutRemoteConfiguration() {
        let store = PromptOptimizationSettingsStore(defaults: makeIsolatedDefaults())

        let settings = store.load()

        #expect(settings.provider == .automaticFree)
        #expect(settings.remote.model.isEmpty)
        #expect(settings.remote.baseURL.isEmpty)
        #expect(settings.confirmedOrigins.isEmpty)
        #expect(!settings.remote.allowsInsecureHTTP)
    }

    @Test
    func persistsRemoteConfigurationAndConfirmedOrigins() {
        let defaults = makeIsolatedDefaults()
        let store = PromptOptimizationSettingsStore(defaults: defaults)
        let settings = PromptOptimizationSettings(
            provider: .openAICompatible,
            remote: PromptOptimizationRemoteConfiguration(
                preset: .custom,
                baseURL: "https://models.example.com/v1",
                model: "private-model",
                allowsInsecureHTTP: false
            ),
            confirmedOrigins: ["https://models.example.com"]
        )

        store.save(settings)

        #expect(store.load() == settings)
    }

    @Test
    func apiKeyUsesDedicatedNonSynchronizingKeychainItem() throws {
        let keychain = RecordingPromptOptimizationKeychain()
        let store = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )

        try store.save("secret")

        #expect(keychain.lastAddQuery?[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(
            keychain.lastAddQuery?[kSecAttrService as String] as? String
                == PromptOptimizationAPIKeyStore.service
        )
        #expect(
            PromptOptimizationAPIKeyStore.service
                == "com.pastera-app.Pastera.prompt-optimization.v1"
        )
        #expect(
            keychain.lastAddQuery?[kSecAttrAccessible as String] as? String
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
        )
    }

    @Test
    func apiKeyUpdatesLoadsAndDeletesWithoutSynchronizing() throws {
        let keychain = RecordingPromptOptimizationKeychain()
        keychain.updateStatus = errSecSuccess
        keychain.copyResult = (errSecSuccess, Data("stored".utf8) as CFTypeRef)
        let store = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )

        try store.save("replacement")
        #expect(try store.load() == "stored")
        try store.delete()

        #expect(keychain.lastUpdateQuery?[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(keychain.lastCopyQuery?[kSecReturnData as String] as? Bool == true)
        #expect(keychain.lastDeleteQuery?[kSecAttrSynchronizable as String] as? Bool == false)
    }

    @Test
    func emptyAPIKeyInputDoesNotDeleteExistingCredential() throws {
        let keychain = RecordingPromptOptimizationKeychain()
        let store = PromptOptimizationAPIKeyStore(
            keychain: keychain,
            usesDataProtectionKeychain: false
        )

        try store.save("   ")

        #expect(keychain.lastAddQuery == nil)
        #expect(keychain.lastUpdateQuery == nil)
        #expect(keychain.lastDeleteQuery == nil)
    }

    private func makeIsolatedDefaults() -> UserDefaults {
        let suiteName = "PromptOptimizationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class RecordingPromptOptimizationKeychain: PromptOptimizationKeychainAccessing {
    var updateStatus: OSStatus = errSecItemNotFound
    var addStatus: OSStatus = errSecSuccess
    var deleteStatus: OSStatus = errSecSuccess
    var copyResult: (OSStatus, CFTypeRef?) = (errSecItemNotFound, nil)

    private(set) var lastCopyQuery: [String: Any]?
    private(set) var lastUpdateQuery: [String: Any]?
    private(set) var lastUpdateAttributes: [String: Any]?
    private(set) var lastAddQuery: [String: Any]?
    private(set) var lastDeleteQuery: [String: Any]?

    func copyMatching(_ query: [String: Any]) -> (OSStatus, CFTypeRef?) {
        lastCopyQuery = query
        return copyResult
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        lastUpdateQuery = query
        lastUpdateAttributes = attributes
        return updateStatus
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lastAddQuery = attributes
        return addStatus
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        lastDeleteQuery = query
        return deleteStatus
    }
}
